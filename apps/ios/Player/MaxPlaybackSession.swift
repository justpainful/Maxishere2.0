@preconcurrency import AVFoundation
import Foundation

/// The audio session every playback surface shares.
///
/// Only the modal player used to configure it, so Shuffle and chat videos
/// inherited the default (ambient) category and were silenced by the ringer
/// switch until the modal player had been opened at least once. `.playback` is
/// also the category the `audio` background mode in Info.plist requires for
/// Picture in Picture to keep running once the app is backgrounded.
@MainActor
enum MaxPlaybackSession {
  private static var isCategoryConfigured = false

  static func activateForPlayback() {
    let session = AVAudioSession.sharedInstance()
    do {
      if !isCategoryConfigured {
        try session.setCategory(.playback, mode: .moviePlayback)
        isCategoryConfigured = true
      }
      try session.setActive(true)
    } catch {
      // A busy or interrupted session is recoverable: playback continues on the
      // previous category rather than failing outright, and the next attempt
      // sets the category again.
      isCategoryConfigured = false
    }
  }
}

/// Expiry of the presigned media URLs the API hands out.
enum MaxPresignedURL {
  /// The instant a SigV4 presigned URL stops being accepted, when it carries the
  /// parameters that say so.
  static func expiry(of url: URL) -> Date? {
    guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }

    var signedAtValue: String?
    var lifetimeValue: String?
    for item in queryItems {
      switch item.name.lowercased() {
      case "x-amz-date": signedAtValue = item.value
      case "x-amz-expires": lifetimeValue = item.value
      default: break
      }
    }

    guard let signedAtValue,
          let lifetimeValue,
          let lifetime = TimeInterval(lifetimeValue) else { return nil }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    guard let signedAt = formatter.date(from: signedAtValue) else { return nil }
    return signedAt.addingTimeInterval(lifetime)
  }

  /// Whether the URL is past its signature's lifetime, or close enough to it
  /// that a stream started now would be cut off mid-playback.
  ///
  /// A URL with no expiry parameters is never reported as expired.
  static func isExpired(
    _ url: URL,
    now: Date = Date(),
    safetyMargin: TimeInterval = 120
  ) -> Bool {
    guard let expiry = expiry(of: url) else { return false }
    return expiry.timeIntervalSince(now) <= safetyMargin
  }
}

/// Re-fetches a media item so its presigned URLs are signed again.
///
/// The API signs playback URLs for a short window and the client had no way to
/// ask for a new one: browsing for a while and then tapping a video handed
/// AVFoundation a signature the server had already rejected, and Retry reused
/// the very same dead URL.
@MainActor
enum MaxMediaRefresh {
  static func refreshedItem(for item: MaxMediaItem, api: any MaxService) async -> MaxMediaItem? {
    for query in queries(for: item) {
      guard let response = try? await api.media(query: query) else { continue }
      if let match = response.items.first(where: { $0.id == item.id }) { return match }
      if Task.isCancelled { return nil }
    }
    return nil
  }

  /// The narrow search first — it usually returns the one row we need — then the
  /// first browse page as a fallback for a title the search cannot match.
  private static func queries(for item: MaxMediaItem) -> [MediaQuery] {
    var result: [MediaQuery] = []
    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !title.isEmpty {
      var byTitle = MediaQuery()
      byTitle.mode = "browse"
      byTitle.search = title
      byTitle.limit = 100
      result.append(byTitle)
    }
    var browse = MediaQuery()
    browse.mode = "browse"
    browse.limit = 100
    result.append(browse)
    return result
  }
}
