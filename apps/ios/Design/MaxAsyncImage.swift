import SwiftUI
import UIKit
import CryptoKit

fileprivate struct MaxLoadedImage: @unchecked Sendable {
  let image: UIImage
  let byteCount: Int
}

/// An image held by the shared memory cache together with the byte count it was
/// decoded from. Reporting the real cost on a cache hit keeps `NSCache`'s
/// eviction bound accurate instead of letting it drift towards zero.
final class MaxImageMemoryEntry: @unchecked Sendable {
  let image: UIImage
  let byteCount: Int

  init(image: UIImage, byteCount: Int) {
    self.image = image
    self.byteCount = byteCount
  }
}

/// Process-wide image memory cache.
///
/// It deliberately lives outside `MaxImageLoader` so `MaxAsyncImage.init` can
/// seed its phase from a hit *synchronously*: a cell recycled during a scroll
/// then never renders a placeholder frame for an image the process already
/// holds. `NSCache` is thread safe, so no actor is required.
final class MaxImageMemoryCache: @unchecked Sendable {
  static let shared = MaxImageMemoryCache()

  private let cache = NSCache<NSString, MaxImageMemoryEntry>()
  private let lock = NSLock()
  private var namespace = "public"

  init() {
    cache.countLimit = 240
    cache.totalCostLimit = 30 * 1_024 * 1_024
  }

  var currentNamespace: String {
    lock.lock()
    defer { lock.unlock() }
    return namespace
  }

  /// Switches the account namespace, dropping everything cached for the
  /// previous one so one account's private media can never be shown to another.
  func setNamespace(_ value: String) {
    lock.lock()
    let changed = namespace != value
    namespace = value
    lock.unlock()
    if changed { cache.removeAllObjects() }
  }

  func entry(for identity: String) -> MaxImageMemoryEntry? {
    cache.object(forKey: storageKey(identity))
  }

  func store(_ entry: MaxImageMemoryEntry, for identity: String) {
    cache.setObject(entry, forKey: storageKey(identity), cost: entry.byteCount)
  }

  func removeAll() {
    cache.removeAllObjects()
  }

  /// Identity of the object a URL points at, independent of how it was signed.
  ///
  /// The backend re-signs every media and thumbnail URL on every list response,
  /// so `X-Amz-Date` / `X-Amz-Signature` differ each time. Hashing the whole URL
  /// produced a brand-new key on every request, which is why the persistent
  /// cache never once hit and every thumbnail was re-downloaded. A URL that is
  /// not a signed URL keeps its query, where it is meaningful.
  static func identity(for url: URL) -> String {
    guard looksLikeExpiringSignedURL(url),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    components.query = nil
    components.fragment = nil
    return components.url?.absoluteString ?? url.absoluteString
  }

  static func looksLikeExpiringSignedURL(_ url: URL) -> Bool {
    let sensitiveNames = Set([
      "x-amz-signature", "x-amz-expires", "x-amz-date", "signature",
      "expires", "token", "access_token", "key-pair-id", "policy"
    ])
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .contains { sensitiveNames.contains($0.name.lowercased()) } == true
  }

  private func storageKey(_ identity: String) -> NSString {
    "\(identity)|\(currentNamespace)" as NSString
  }
}

/// Caches the resolved API origin. `MaxAsyncImage` is constructed on every
/// render pass of every cell, and `MaxConfiguration.fromBundle()` reads the
/// bundle plus two defaults each time it is called. The cache is invalidated the
/// moment the saved server address changes.
enum MaxImageBaseURL {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var cached: (baseURL: URL, savedOrigin: String?)?

  static var current: URL {
    let saved = UserDefaults.standard.string(forKey: "vault_baseURL")
    lock.lock()
    defer { lock.unlock() }
    if let cached, cached.savedOrigin == saved { return cached.baseURL }
    let resolved = MaxConfiguration.fromBundle().baseURL
    cached = (baseURL: resolved, savedOrigin: saved)
    return resolved
  }
}

/// A bounded, process-wide thumbnail loader with smart persistent caching.
actor MaxImageLoader {
  static let shared = MaxImageLoader()

  private let session: URLSession
  private let tokenStore: KeychainSessionStore
  private var inFlight: [String: Task<MaxLoadedImage, Error>] = [:]
  private let cacheDir: URL

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.session = URLSession(configuration: configuration)
    self.tokenStore = KeychainSessionStore(service: "app.max.iphone")

    // Set up cache directory
    self.cacheDir = FileManager.default
      .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MaxImageCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
  }

  fileprivate func image(for sourceURL: URL, baseURL: URL) async throws -> MaxLoadedImage {
    let resolvedURL = Self.resolve(sourceURL, relativeTo: baseURL)
    let requestContext = makeRequest(url: resolvedURL, baseURL: baseURL)
    let identity = requestContext.identity

    // Read cache configurations from User Defaults
    let enableThumbnailCache = UserDefaults.standard.object(forKey: "app.max.preferences.enableThumbnailCache") as? Bool ?? true
    let limitMB = UserDefaults.standard.object(forKey: "app.max.preferences.thumbnailCacheLimitMB") as? Int ?? 250
    let limitBytes = limitMB * 1024 * 1024

    // 1. Check memory cache first
    if let cached = MaxImageMemoryCache.shared.entry(for: identity) {
      return MaxLoadedImage(image: cached.image, byteCount: cached.byteCount)
    }

    // 2. Check the persistent disk cache, keyed by the object identity rather
    //    than by the signature that changes on every request.
    let hashedKey = Self.cacheFileName(for: identity, namespace: requestContext.namespace)
    let fileURL = cacheDir.appendingPathComponent(hashedKey)
    if enableThumbnailCache, FileManager.default.fileExists(atPath: fileURL.path) {
      // Update access time for LRU eviction logic
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

      if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
        MaxImageMemoryCache.shared.store(
          MaxImageMemoryEntry(image: img, byteCount: data.count),
          for: identity
        )
        return MaxLoadedImage(image: img, byteCount: data.count)
      }
    }

    // 3. Check for in-flight downloads to prevent redundant requests
    if let task = inFlight[identity] {
      return try await task.value
    }

    let request = requestContext.request
    let task = Task<MaxLoadedImage, Error> {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
      }
      guard let image = UIImage(data: data) else {
        throw URLError(.cannotDecodeContentData)
      }

      // Persist unless the server marked the response uncacheable. The bytes
      // behind a presigned URL are the same object every time, so they are safe
      // to keep under an identity key that excludes the signature.
      if enableThumbnailCache, Self.responseAllowsPersistentCache(http) {
        try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        // Set complete protection for device security
        try? FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: fileURL.path
        )
        // Evict older files if we've exceeded the cache limit
        self.evictOldDiskCaches(limitBytes: limitBytes)
      }

      return MaxLoadedImage(image: image, byteCount: data.count)
    }

    inFlight[identity] = task
    do {
      let loaded = try await task.value
      inFlight[identity] = nil
      MaxImageMemoryCache.shared.store(
        MaxImageMemoryEntry(image: loaded.image, byteCount: loaded.byteCount),
        for: identity
      )
      return loaded
    } catch {
      inFlight[identity] = nil
      throw error
    }
  }

  func removeAll() {
    inFlight.values.forEach { $0.cancel() }
    inFlight.removeAll()
    MaxImageMemoryCache.shared.removeAll()

    // Clear disk files in CacheDir
    if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
      for file in files {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  private static func cacheFileName(for identity: String, namespace: String) -> String {
    let digest = SHA256.hash(data: Data("\(identity)|\(namespace)".utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private func evictOldDiskCaches(limitBytes: Int) {
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: cacheDir,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
      options: []
    ) else { return }

    var fileInfos: [(url: URL, size: Int, date: Date)] = []
    var totalSize = 0

    for url in files {
      guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = resourceValues.fileSize,
            let date = resourceValues.contentModificationDate else { continue }
      fileInfos.append((url: url, size: size, date: date))
      totalSize += size
    }

    guard totalSize > limitBytes else { return }
    let needed = totalSize - limitBytes
    var freed = 0

    // Sort by modification date (oldest first)
    let sorted = fileInfos.sorted { $0.date < $1.date }
    for file in sorted {
      guard freed < needed else { break }
      try? FileManager.default.removeItem(at: file.url)
      freed += file.size
    }
  }

  private func makeRequest(url: URL, baseURL: URL) -> (
    request: URLRequest,
    identity: String,
    namespace: String
  ) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(baseURL.absoluteString, forHTTPHeaderField: "X-Max-Public-Origin")

    // Single source of truth for "this host is our backend"; the hand-maintained
    // copy of this list is what let the app go on authenticating to a dead host.
    let isBackend = MaxConfiguration.isBackendHost(url.host, baseURL: baseURL)
      || url.path.hasPrefix("/api/")
      || url.path.hasPrefix("/media/")
      || url.path.hasPrefix("/uploads/")

    var token = (try? tokenStore.loadToken())?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if token?.isEmpty == true { token = nil }
    if isBackend, let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // Keep authenticated private media namespaced by a *stable* digest of the
    // session token, so account changes cannot reuse another account's image. A
    // `token == nil` request is public and shares one namespace. `hashValue` is
    // seeded randomly per process, so using it here changed the disk-cache
    // filename on every launch and the persistent cache could never hit.
    let namespace = token.map { value -> String in
      SHA256.hash(data: Data(value.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    } ?? "public"
    MaxImageMemoryCache.shared.setNamespace(namespace)
    return (request, MaxImageMemoryCache.identity(for: url), namespace)
  }

  private static func resolve(_ url: URL, relativeTo baseURL: URL) -> URL {
    return url.resolved(against: baseURL)
  }

  private static func responseAllowsPersistentCache(_ response: HTTPURLResponse) -> Bool {
    let policy = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
    return !policy.contains("no-store") && !policy.contains("private")
  }
}


struct MaxAsyncImage<Content: View>: View {
  let url: URL?
  let content: (AsyncImagePhase) -> Content

  @Environment(\.maxMotionEnabled) private var motionEnabled

  @State private var phase: AsyncImagePhase
  @State private var loadedURL: URL?

  init(
    url: URL?,
    @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
  ) {
    self.url = url
    self.content = content
    let seed = Self.memoryHit(for: url)
    _phase = State(initialValue: seed.map { .success(Image(uiImage: $0)) } ?? .empty)
    _loadedURL = State(initialValue: seed == nil ? nil : url)
  }

  init<I: View, P: View>(
    url: URL?,
    @ViewBuilder content: @escaping (Image) -> I,
    @ViewBuilder placeholder: @escaping () -> P
  ) where Content == _ConditionalContent<I, P> {
    self.url = url
    self.content = { phase in
      if let image = phase.image {
        return ViewBuilder.buildEither(first: content(image))
      } else {
        return ViewBuilder.buildEither(second: placeholder())
      }
    }
    let seed = Self.memoryHit(for: url)
    _phase = State(initialValue: seed.map { .success(Image(uiImage: $0)) } ?? .empty)
    _loadedURL = State(initialValue: seed == nil ? nil : url)
  }

  /// A synchronous memory-cache probe. `URL.resolved(against:)` is pure, so it
  /// is safe to run here, and a hit means this view renders its image on the
  /// very first frame instead of flashing a placeholder.
  private static func memoryHit(for url: URL?) -> UIImage? {
    guard let url else { return nil }
    let resolved = url.resolved(against: MaxImageBaseURL.current)
    return MaxImageMemoryCache.shared.entry(for: MaxImageMemoryCache.identity(for: resolved))?.image
  }

  var body: some View {
    content(phase)
      .task(id: url) {
        await loadImage()
      }
  }

  private func loadImage() async {
    guard let url else {
      phase = .empty
      loadedURL = nil
      return
    }

    // Only blank the surface when what is on screen belongs to a different URL.
    // Re-running this task for the image already shown must not flash a
    // placeholder over a correct picture.
    if loadedURL != url { phase = .empty }

    do {
      let loaded = try await MaxImageLoader.shared.image(
        for: url,
        baseURL: MaxImageBaseURL.current
      )
      guard !Task.isCancelled else { return }
      withAnimation(MaxMotion.animation(.easeOut(duration: 0.18), enabled: motionEnabled)) {
        phase = .success(Image(uiImage: loaded.image))
      }
      loadedURL = url
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      loadedURL = nil
      phase = .failure(error)
    }
  }
}

extension MaxImageLoader {
  static func purgeSharedCache() {
    // The memory cache and its namespace live outside the actor precisely so a
    // sign-out drops the previous account's images synchronously, before any
    // view can seed itself from them.
    MaxImageMemoryCache.shared.setNamespace("public")
    MaxImageMemoryCache.shared.removeAll()
    Task { await shared.removeAll() }
  }
}
