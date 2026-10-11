@preconcurrency import AVFoundation
import Foundation
import CoreLocation
@preconcurrency import Photos
import UIKit

@MainActor
protocol DevicePhotoLibraryClient: AnyObject {
  var presentsSystemPhotoLibrary: Bool { get }
  func authorizationStatus() -> MemoryPhotoAuthorizationStatus
  func requestAuthorization() async -> MemoryPhotoAuthorizationStatus
  func cachedCandidates(filter: MemoryFilter) -> [MemoryCandidate]
  func refreshCandidates(filter: MemoryFilter) async throws -> [MemoryCandidate]
  func thumbnail(for localIdentifier: String, targetSize: CGSize) async -> UIImage?
  func image(for localIdentifier: String, targetSize: CGSize) async -> UIImage?
  func livePhoto(for localIdentifier: String, targetSize: CGSize) async -> PHLivePhoto?
  func avAsset(for localIdentifier: String) async -> AVAsset?
  func exportAssetFile(for localIdentifier: String) async throws -> URL
  func prefetch(localIdentifiers: [String], targetSize: CGSize)
  func clearThumbnailCache()
  func resetLocalIndexAndCache()
  func storageMetrics() -> MemoryStorageMetrics
  func startObservingChanges(_ onChange: @escaping @MainActor @Sendable () -> Void)
}

@MainActor
final class PhotoKitDevicePhotoLibraryClient:
  NSObject,
  DevicePhotoLibraryClient,
  PHPhotoLibraryChangeObserver
{
  private let imageManager = PHCachingImageManager()
  private let files: LocalMemoriesFileStore
  private let thumbnailMemoryCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    // Scrolling must not retain a full-resolution image for every library
    // item. This cap is deliberately small enough for older iPhones.
    cache.countLimit = 96
    cache.totalCostLimit = 48 * 1_024 * 1_024
    return cache
  }()
  private var changeHandler: (@MainActor @Sendable () -> Void)?
  private var prefetchedAssets: [PHAsset] = []
  private var isObservingChanges = false

  var presentsSystemPhotoLibrary: Bool { true }

  init(files: LocalMemoriesFileStore = LocalMemoriesFileStore()) {
    self.files = files
    super.init()
  }

  func authorizationStatus() -> MemoryPhotoAuthorizationStatus {
    Self.authorizationStatus(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  func requestAuthorization() async -> MemoryPhotoAuthorizationStatus {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return Self.authorizationStatus(from: status)
  }

  func cachedCandidates(filter: MemoryFilter) -> [MemoryCandidate] {
    guard authorizationStatus().canReadLibrary else { return [] }
    _ = filter
    return sorted(files.loadIndex()?.candidates ?? [])
  }

  func refreshCandidates(filter: MemoryFilter) async throws -> [MemoryCandidate] {
    guard authorizationStatus().canReadLibrary else { return [] }
    // Enumerating a large Photos library synchronously on the main actor can
    // freeze presentation long enough for iOS to terminate the app. PHAsset
    // objects stay entirely inside this detached scan; only Sendable value
    // candidates cross back to the UI actor.
    let catalog = await Task.detached(priority: .userInitiated) {
      Self.scanPhotoLibrary()
    }.value

    await files.saveIndex(catalog)
    _ = filter
    return sorted(catalog)
  }

  func thumbnail(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
    let key = localIdentifier as NSString
    if let cached = thumbnailMemoryCache.object(forKey: key) {
      return cached
    }
    if let cached = files.loadThumbnail(identifier: localIdentifier) {
      thumbnailMemoryCache.setObject(cached, forKey: key, cost: Self.imageCost(cached))
      return cached
    }
    let rendered = await requestImage(
      for: localIdentifier,
      targetSize: targetSize,
      contentMode: .aspectFill
    )
    if let rendered, !Task.isCancelled {
      thumbnailMemoryCache.setObject(rendered, forKey: key, cost: Self.imageCost(rendered))
      files.saveThumbnail(rendered, identifier: localIdentifier)
    }
    return Task.isCancelled ? nil : rendered
  }

  func image(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
    await requestImage(
      for: localIdentifier,
      targetSize: targetSize,
      contentMode: .aspectFit
    )
  }

  func livePhoto(for localIdentifier: String, targetSize: CGSize) async -> PHLivePhoto? {
    guard let asset = fetchAsset(localIdentifier) else { return nil }
    let request = PhotoKitRequestState<UncheckedSendableValue<PHLivePhoto>>(manager: imageManager)
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        request.install(continuation)
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = imageManager.requestLivePhoto(
          for: asset,
          targetSize: targetSize,
          contentMode: .aspectFit,
          options: options
        ) { livePhoto, info in
          if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
            return
          }
          request.finish(UncheckedSendableValue(value: livePhoto))
        }
        request.setRequestID(requestID)
      }
    } onCancel: {
      request.cancel()
    }
    return result?.value
  }

  func avAsset(for localIdentifier: String) async -> AVAsset? {
    guard let asset = fetchAsset(localIdentifier) else { return nil }
    // Use .automatic so Photos can serve a local optimised version immediately
    // instead of blocking on iCloud download (.highQualityFormat), which causes
    // crashes/timeouts when the device is offline or the video hasn't synced yet.
    let request = PhotoKitRequestState<UncheckedSendableValue<AVAsset>>(manager: imageManager)
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        request.install(continuation)
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        let requestID = imageManager.requestAVAsset(
          forVideo: asset,
          options: options
        ) { avAsset, _, _ in
          request.finish(UncheckedSendableValue(value: avAsset))
        }
        request.setRequestID(requestID)
      }
    } onCancel: {
      request.cancel()
    }
    return result?.value
  }

  func exportAssetFile(for localIdentifier: String) async throws -> URL {
    guard let asset = fetchAsset(localIdentifier) else {
      throw LocalMemoriesError.assetUnavailable
    }
    guard let resource = PHAssetResource.assetResources(for: asset).first else {
      throw LocalMemoriesError.assetUnavailable
    }
    let pathExtension = (resource.originalFilename as NSString).pathExtension
    let output = files.nextExportURL(pathExtension: pathExtension)
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    do {
      try await PHAssetResourceManager.default().writeData(
        for: resource,
        toFile: output,
        options: options
      )
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
    files.protectExport(at: output)
    return output
  }

  func prefetch(localIdentifiers: [String], targetSize: CGSize) {
    if !prefetchedAssets.isEmpty {
      imageManager.stopCachingImages(
        for: prefetchedAssets,
        targetSize: targetSize,
        contentMode: .aspectFit,
        options: nil
      )
    }
    prefetchedAssets = localIdentifiers.compactMap(fetchAsset)
    guard !prefetchedAssets.isEmpty else { return }
    imageManager.startCachingImages(
      for: prefetchedAssets,
      targetSize: targetSize,
      contentMode: .aspectFit,
      options: nil
    )
  }

  func clearThumbnailCache() {
    imageManager.stopCachingImagesForAllAssets()
    thumbnailMemoryCache.removeAllObjects()
    prefetchedAssets = []
    files.clearThumbnailCache()
  }

  func resetLocalIndexAndCache() {
    imageManager.stopCachingImagesForAllAssets()
    thumbnailMemoryCache.removeAllObjects()
    prefetchedAssets = []
    files.resetIndexAndCaches()
  }

  func storageMetrics() -> MemoryStorageMetrics {
    files.metrics()
  }

  func startObservingChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) {
    changeHandler = onChange
    guard !isObservingChanges else { return }
    isObservingChanges = true
    PHPhotoLibrary.shared().register(self)
  }

  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor [weak self] in
      self?.changeHandler?()
    }
  }

  private func requestImage(
    for localIdentifier: String,
    targetSize: CGSize,
    contentMode: PHImageContentMode
  ) async -> UIImage? {
    guard let asset = fetchAsset(localIdentifier) else { return nil }
    let request = PhotoKitRequestState<UncheckedSendableValue<UIImage>>(manager: imageManager)
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        request.install(continuation)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let requestID = imageManager.requestImage(
          for: asset,
          targetSize: targetSize,
          contentMode: contentMode,
          options: options
        ) { image, info in
          if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
            return
          }
          request.finish(UncheckedSendableValue(value: image))
        }
        request.setRequestID(requestID)
      }
    } onCancel: {
      request.cancel()
    }
    return result?.value
  }

  private func fetchAsset(_ localIdentifier: String) -> PHAsset? {
    PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
  }

  private func sorted(_ candidates: [MemoryCandidate]) -> [MemoryCandidate] {
    candidates
      .sorted {
        if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
        return $0.id < $1.id
      }
  }

  private static func authorizationStatus(
    from status: PHAuthorizationStatus
  ) -> MemoryPhotoAuthorizationStatus {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .limited: .limited
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }

  private nonisolated static func scanPhotoLibrary() -> [MemoryCandidate] {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let assets = PHAsset.fetchAssets(with: options)
    var catalog: [MemoryCandidate] = []
    catalog.reserveCapacity(assets.count)
    let titleFormatter = DateFormatter()
    titleFormatter.dateStyle = .medium
    titleFormatter.timeStyle = .none
    let subtitleFormatter = DateFormatter()
    subtitleFormatter.dateStyle = .none
    subtitleFormatter.timeStyle = .short

    assets.enumerateObjects { asset, _, _ in
      guard !asset.isHidden, let kind = mediaKind(for: asset) else { return }
      let createdAt = asset.creationDate ?? asset.modificationDate ?? Date.distantPast
      let identifier = asset.localIdentifier
      catalog.append(
        MemoryCandidate(
          key: MemoryAssetKey(identifier: identifier),
          kind: kind,
          title: titleFormatter.string(from: createdAt),
          subtitle: subtitleFormatter.string(from: createdAt),
          createdAt: createdAt,
          duration: asset.mediaType == .video ? asset.duration : nil,
          pixelWidth: asset.pixelWidth,
          pixelHeight: asset.pixelHeight,
          isFavorite: asset.isFavorite,
          isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
          isScreenRecording: asset.mediaSubtypes.contains(.videoScreenRecording),
          localIdentifier: identifier,
          location: asset.location.map {
            MemoryLocation(
              latitude: $0.coordinate.latitude,
              longitude: $0.coordinate.longitude
            )
          },
          recoveryKey: MediaRecoveryKey(
            mediaKind: kind,
            createdAt: asset.creationDate,
            modifiedAt: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.mediaType == .video ? asset.duration : nil,
            burstIdentifier: asset.burstIdentifier
          )
        )
      )
    }
    return catalog
  }

  private nonisolated static func mediaKind(for asset: PHAsset) -> MemoryMediaKind? {
    switch asset.mediaType {
    case .image:
      asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
    case .video:
      .video
    default:
      nil
    }
  }

  private static func imageCost(_ image: UIImage) -> Int {
    let pixels = max(1, Int(image.size.width * image.scale) * Int(image.size.height * image.scale))
    return min(pixels * 4, 16 * 1_024 * 1_024)
  }
}

@MainActor
final class DemoLocalMemoriesClient: DevicePhotoLibraryClient {
  private let files: LocalMemoriesFileStore
  private lazy var fixtures = makeFixtures()
  private var images: [String: UIImage] = [:]

  var presentsSystemPhotoLibrary: Bool { false }

  init(files: LocalMemoriesFileStore = LocalMemoriesFileStore()) {
    self.files = files
  }

  func authorizationStatus() -> MemoryPhotoAuthorizationStatus { .authorized }
  func requestAuthorization() async -> MemoryPhotoAuthorizationStatus { .authorized }

  func cachedCandidates(filter: MemoryFilter) -> [MemoryCandidate] {
    _ = filter
    return fixtures
  }

  func refreshCandidates(filter: MemoryFilter) async throws -> [MemoryCandidate] {
    cachedCandidates(filter: filter)
  }

  func thumbnail(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
    imageFixture(identifier: localIdentifier, targetSize: targetSize)
  }

  func image(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
    imageFixture(identifier: localIdentifier, targetSize: targetSize)
  }

  func livePhoto(for localIdentifier: String, targetSize: CGSize) async -> PHLivePhoto? {
    nil
  }

  func avAsset(for localIdentifier: String) async -> AVAsset? { nil }

  func exportAssetFile(for localIdentifier: String) async throws -> URL {
    guard let image = imageFixture(
      identifier: localIdentifier,
      targetSize: CGSize(width: 1200, height: 1600)
    ), let data = image.pngData() else {
      throw LocalMemoriesError.assetUnavailable
    }
    let url = files.nextExportURL(pathExtension: "png")
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    files.protectExport(at: url)
    return url
  }

  func prefetch(localIdentifiers: [String], targetSize: CGSize) {
    for identifier in localIdentifiers {
      _ = imageFixture(identifier: identifier, targetSize: targetSize)
    }
  }

  func clearThumbnailCache() {
    images = [:]
    files.clearThumbnailCache()
  }

  func resetLocalIndexAndCache() {
    images = [:]
    files.resetIndexAndCaches()
  }

  func storageMetrics() -> MemoryStorageMetrics {
    MemoryStorageMetrics(
      indexedAssetCount: fixtures.count,
      thumbnailCacheBytes: 0,
      lastIndexedAt: fixtures.first?.createdAt
    )
  }

  func startObservingChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) {}

  private func makeFixtures() -> [MemoryCandidate] {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    return (1...8).compactMap { index in
      guard let date = calendar.date(byAdding: .year, value: -index, to: now) else {
        return nil
      }
      let identifier = "max-local-demo-memory-\(index)"
      return MemoryCandidate(
        key: MemoryAssetKey(identifier: identifier),
        kind: .photo,
        title: DateFormatter.memoriesPrimary.string(from: date),
        subtitle: String(localized: "memories.demo.subtitle"),
        createdAt: date,
        duration: nil,
        pixelWidth: 1200,
        pixelHeight: 1600,
        isFavorite: index.isMultiple(of: 3),
        isScreenshot: false,
        isScreenRecording: false,
        localIdentifier: identifier,
        location: MemoryLocation(
          latitude: 24.7136 + (Double(index) * 0.02),
          longitude: 46.6753 + (Double(index) * 0.02)
        ),
        recoveryKey: MediaRecoveryKey(
          mediaKind: .photo,
          createdAt: date,
          modifiedAt: date,
          pixelWidth: 1200,
          pixelHeight: 1600,
          duration: nil,
          burstIdentifier: nil
        )
      )
    }
  }

  private func imageFixture(identifier: String, targetSize: CGSize) -> UIImage? {
    let width = max(480, min(targetSize.width, 1200))
    let height = max(640, min(targetSize.height, 1600))
    let cacheKey = "\(identifier)-\(Int(width))x\(Int(height))"
    if let image = images[cacheKey] { return image }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
    let seed = stableSeed(for: identifier)
    let image = renderer.image { context in
      UIColor(
        red: CGFloat((seed % 47) + 30) / 100,
        green: CGFloat((seed % 31) + 44) / 100,
        blue: CGFloat((seed % 23) + 62) / 100,
        alpha: 1
      ).setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      UIColor.white.withAlphaComponent(0.22).setFill()
      context.cgContext.fillEllipse(
        in: CGRect(x: width * 0.12, y: height * 0.18, width: width * 0.72, height: width * 0.72)
      )
      UIColor.black.withAlphaComponent(0.18).setFill()
      context.cgContext.fillEllipse(
        in: CGRect(x: width * 0.34, y: height * 0.55, width: width * 0.84, height: width * 0.84)
      )
    }
    images[cacheKey] = image
    return image
  }

  private func stableSeed(for value: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }
    return Int(hash % 10_000)
  }
}

private struct UncheckedSendableValue<Value>: @unchecked Sendable {
  let value: Value?
}

private final class PhotoKitRequestState<Value: Sendable>: @unchecked Sendable {
  private let manager: PHImageManager
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value?, Never>?
  private var requestID = PHInvalidImageRequestID
  private var isCancelled = false
  private var isFinished = false

  init(manager: PHImageManager) {
    self.manager = manager
  }

  func install(_ continuation: CheckedContinuation<Value?, Never>) {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      continuation.resume(returning: nil)
      return
    }
    self.continuation = continuation
    lock.unlock()
  }

  func setRequestID(_ requestID: PHImageRequestID) {
    lock.lock()
    self.requestID = requestID
    let shouldCancel = isCancelled
    lock.unlock()
    if shouldCancel {
      manager.cancelImageRequest(requestID)
    }
  }

  func finish(_ value: Value?) {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      return
    }
    isFinished = true
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(returning: value)
  }

  func cancel() {
    lock.lock()
    guard !isFinished else {
      lock.unlock()
      return
    }
    isCancelled = true
    isFinished = true
    let requestID = requestID
    let continuation = continuation
    self.continuation = nil
    lock.unlock()

    if requestID != PHInvalidImageRequestID {
      manager.cancelImageRequest(requestID)
    }
    continuation?.resume(returning: nil)
  }
}

enum LocalMemoriesError: Error {
  case assetUnavailable
}
