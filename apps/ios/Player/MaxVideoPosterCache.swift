@preconcurrency import AVFoundation
import CryptoKit
import SwiftUI
import UIKit

/// A generated poster frame. `UIImage` is not `Sendable`, and the image is never
/// mutated after it is created, so the box makes the hand-off explicit.
struct MaxVideoPosterImage: @unchecked Sendable {
  let image: UIImage
}

/// Produces and caches the first usable frame of a video, for every video the
/// server has no thumbnail for.
///
/// Three properties matter and each one was missing before:
/// * generation runs **off the main actor** through `AVAssetImageGenerator`'s
///   async API, so it never blocks a scroll the way the deprecated synchronous
///   `copyCGImage(at:actualTime:)` did;
/// * results are cached on disk **by media id**, never by the streaming URL —
///   the backend re-signs that URL on every request, so a URL key can never hit;
/// * only a couple of generations run at a time, so opening a grid does not fire
///   a dozen concurrent range requests against the same connection the player
///   needs.
actor MaxVideoPosterCache {
  static let shared = MaxVideoPosterCache()

  /// Frame cap. Large enough for a full-width card on a 3x device, small enough
  /// that AVFoundation only has to read the first few hundred kilobytes.
  static let defaultMaximumSize = CGSize(width: 960, height: 960)

  private static let maximumConcurrentGenerations = 2

  /// Disk cache is trimmed back toward this ceiling so posters cannot grow the
  /// Caches directory without bound over months of browsing.
  private static let maximumDiskBytes = 150 * 1024 * 1024

  private let directory: URL
  private var memory: [String: MaxVideoPosterImage] = [:]
  private var inFlight: [String: Task<MaxVideoPosterImage?, Never>] = [:]
  private var unavailableMediaIDs: Set<String> = []
  private var storesSinceTrim = 0

  private var activeGenerations = 0
  private var waitingGenerations: [CheckedContinuation<Void, Never>] = []

  init() {
    self.directory = FileManager.default
      .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MaxVideoPosters", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// Memory or disk hit for `mediaID`, without touching the network.
  func cachedPoster(mediaID: String) -> MaxVideoPosterImage? {
    if let poster = memory[mediaID] { return poster }
    let fileURL = fileURL(for: mediaID)
    guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else {
      return nil
    }
    let poster = MaxVideoPosterImage(image: image)
    memory[mediaID] = poster
    return poster
  }

  /// Stores a poster produced elsewhere so every surface shares one cache.
  func store(_ poster: MaxVideoPosterImage, mediaID: String) {
    memory[mediaID] = poster
    unavailableMediaIDs.remove(mediaID)
    guard let data = poster.image.jpegData(compressionQuality: 0.8) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: fileURL(for: mediaID), options: .atomic)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: fileURL(for: mediaID).path
    )
    storesSinceTrim += 1
    if storesSinceTrim >= 20 {
      storesSinceTrim = 0
      trimDiskCacheIfNeeded()
    }
  }

  /// Evicts the oldest posters (by modification date) whenever the on-disk cache
  /// grows past `maximumDiskBytes`, bringing it back to ~80% of the ceiling.
  private func trimDiskCacheIfNeeded() {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: keys
    ) else { return }

    var entries: [(url: URL, size: Int, date: Date)] = []
    var total = 0
    for file in files {
      let values = try? file.resourceValues(forKeys: Set(keys))
      let size = values?.fileSize ?? 0
      entries.append((file, size, values?.contentModificationDate ?? .distantPast))
      total += size
    }

    guard total > Self.maximumDiskBytes else { return }
    let target = Int(Double(Self.maximumDiskBytes) * 0.8)
    for entry in entries.sorted(by: { $0.date < $1.date }) {
      if total <= target { break }
      try? FileManager.default.removeItem(at: entry.url)
      total -= entry.size
    }
  }

  /// Cached poster for `mediaID`, generating one from `url` when there is none.
  func poster(
    for mediaID: String,
    url: URL,
    maximumSize: CGSize = MaxVideoPosterCache.defaultMaximumSize
  ) async -> MaxVideoPosterImage? {
    if let cached = cachedPoster(mediaID: mediaID) { return cached }
    if unavailableMediaIDs.contains(mediaID) { return nil }
    if let existing = inFlight[mediaID] { return await existing.value }

    let task = Task<MaxVideoPosterImage?, Never> {
      await self.acquireGenerationSlot()
      let generated = await Self.generatePoster(url: url, maximumSize: maximumSize)
      self.releaseGenerationSlot()
      return generated
    }
    inFlight[mediaID] = task

    let poster = await task.value
    inFlight[mediaID] = nil
    if let poster {
      store(poster, mediaID: mediaID)
    } else {
      // Remember the miss for this launch so a scroll does not retry a video
      // whose bytes are simply not there. A relaunch retries.
      unavailableMediaIDs.insert(mediaID)
    }
    return poster
  }

  func purge() {
    memory.removeAll()
    unavailableMediaIDs.removeAll()
    if let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ) {
      for file in files {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  // MARK: - Bounded generation

  private func acquireGenerationSlot() async {
    guard activeGenerations >= Self.maximumConcurrentGenerations else {
      activeGenerations += 1
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waitingGenerations.append(continuation)
    }
    // The releasing generation handed its slot over, so the count is unchanged.
  }

  private func releaseGenerationSlot() {
    if waitingGenerations.isEmpty {
      activeGenerations = max(0, activeGenerations - 1)
    } else {
      waitingGenerations.removeFirst().resume()
    }
  }

  // MARK: - Generation

  /// Nonisolated on purpose: the work runs on the cooperative pool rather than
  /// on this actor, so a slow decode cannot delay a cache lookup for a
  /// neighbouring tile.
  private static func generatePoster(
    url: URL,
    maximumSize: CGSize
  ) async -> MaxVideoPosterImage? {
    let asset = AVURLAsset(url: url)
    guard (try? await asset.load(.isPlayable)) == true, !Task.isCancelled else { return nil }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = maximumSize
    // The nearest sync frame is a perfectly good poster and costs far fewer
    // range requests than an exact seek.
    generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

    // A second in avoids the black lead-in most encoders start with; a clip
    // shorter than that falls back to the very first frame.
    for seconds in [1.0, 0.0] {
      guard !Task.isCancelled else { return nil }
      let time = CMTime(seconds: seconds, preferredTimescale: 600)
      if let frame = try? await generator.image(at: time).image {
        return MaxVideoPosterImage(image: UIImage(cgImage: frame))
      }
    }
    return nil
  }

  private func fileURL(for mediaID: String) -> URL {
    let digest = SHA256.hash(data: Data(mediaID.utf8))
    let name = digest.compactMap { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent("\(name).jpg")
  }
}

/// Shows a locally generated poster frame for a video the API has no thumbnail
/// for, falling back to `placeholder` until one exists.
///
/// Keyed by media id rather than by URL, so a re-signed streaming URL reuses the
/// poster that was already generated instead of regenerating it.
struct MaxVideoPosterView<Placeholder: View>: View {
  let mediaID: String
  let url: URL
  let placeholder: () -> Placeholder

  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var image: UIImage?

  init(
    mediaID: String,
    url: URL,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.mediaID = mediaID
    self.url = url
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        placeholder()
      }
    }
    .task(id: mediaID) {
      guard image == nil else { return }
      let poster = await MaxVideoPosterCache.shared.poster(for: mediaID, url: url)
      guard !Task.isCancelled, let poster else { return }
      withAnimation(MaxMotion.animation(.easeOut(duration: 0.18), enabled: motionEnabled)) {
        image = poster.image
      }
    }
  }
}
