import Foundation

// MARK: - Channels wire models
//
// Always-running broadcasts built from a vault rule. See
// docs/design/channels/LOGIC.md for why each field exists.
//
// The one thing to understand before changing anything here: THE SERVER NEVER
// TELLS US WHERE TO SEEK. It hands over a frozen programme and the instant it
// started, and the client does the arithmetic. That is what lets two devices
// agree with no message between them, and what keeps the answer right while a
// request is in flight.
//
// Every instant on this wire is epoch MILLISECONDS. Go marshals a time with
// nanoseconds and this app decodes with `.iso8601`, which rejects fractional
// seconds outright — a timestamp string would have decoded on the desktop and
// failed here, which is the worst kind of difference to find. Watch Together
// settled the same way (WATCH_TOGETHER_SPEC §1).

/// A channel's rule. Every condition must hold.
///
/// The conditions are grouped into FACETS — rating, length, seen, favourite,
/// filing, provenance — and at most one condition per facet may be set. "Rated
/// 8 or more" and "never rated" are both good conditions, and a rule holding
/// both matches nothing forever while still calling itself a channel. The
/// server refuses such a rule; the builder cannot express one.
struct ChannelRule: Codable, Hashable, Sendable {
  var minRating: Int?
  var maxRating: Int?
  var unratedOnly: Bool?
  var minSeconds: Double?
  var maxSeconds: Double?
  var unwatchedOnly: Bool?
  var watchedOnly: Bool?
  /// Three-valued: `nil` means "either", which is not "not a favourite".
  var favourite: Bool?
  var collectionId: String?
  var uncollected: Bool?
  var ownerId: String?
  var addedWithinDays: Int?

  init(
    minRating: Int? = nil,
    maxRating: Int? = nil,
    unratedOnly: Bool? = nil,
    minSeconds: Double? = nil,
    maxSeconds: Double? = nil,
    unwatchedOnly: Bool? = nil,
    watchedOnly: Bool? = nil,
    favourite: Bool? = nil,
    collectionId: String? = nil,
    uncollected: Bool? = nil,
    ownerId: String? = nil,
    addedWithinDays: Int? = nil
  ) {
    self.minRating = minRating
    self.maxRating = maxRating
    self.unratedOnly = unratedOnly
    self.minSeconds = minSeconds
    self.maxSeconds = maxSeconds
    self.unwatchedOnly = unwatchedOnly
    self.watchedOnly = watchedOnly
    self.favourite = favourite
    self.collectionId = collectionId
    self.uncollected = uncollected
    self.ownerId = ownerId
    self.addedWithinDays = addedWithinDays
  }
}

enum ChannelOrdering: String, Codable, Hashable, Sendable, CaseIterable {
  case shuffle
  case newest
  case rating
}

/// A create or an update.
struct ChannelInput: Codable, Hashable, Sendable {
  var name: String
  var rule: ChannelRule
  var ordering: ChannelOrdering
  var alwaysRunning: Bool
}

/// One entry of a frozen programme.
struct ChannelProgrammeItem: Codable, Hashable, Sendable, Identifiable {
  let mediaId: String
  let position: Int
  /// Copied when the programme was frozen, never re-read from the media row:
  /// re-encoding an item must not silently move every later item on a timeline
  /// two people are sharing.
  let seconds: Double

  var id: Int { position }
}

struct ChannelProgramme: Codable, Hashable, Sendable {
  let generation: Int
  let items: [ChannelProgrammeItem]
}

/// Everything needed to SHOW one clip.
///
/// A channel carries these itself because the library catalogue is paged: a
/// channel draws from the whole vault, so almost nothing it plays is in the
/// page a client happens to hold.
struct ChannelMediaRef: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let name: String
  let seconds: Double
  let posterUrl: String?
  let mediaUrl: String
}

struct ChannelNowSlice: Codable, Hashable, Sendable {
  let index: Int
  let mediaId: String
  let intoSeconds: Double
  let itemSeconds: Double
  let cycle: Int
  let nextWrapAtMs: Int
  let nextMediaIds: [String]
}

/// Somebody with the channel open right now. Presence, not membership.
struct ChannelListener: Codable, Hashable, Sendable, Identifiable {
  let userId: String
  /// False once they have skipped: off air on their own cursor, while the
  /// channel keeps running for everyone else.
  let live: Bool
  let seenAtMs: Int

  var id: String { userId }
}

struct ChannelDoc: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let name: String
  let rule: ChannelRule
  let ordering: ChannelOrdering
  let alwaysRunning: Bool
  /// Newest frozen generation; may be ahead of `activeGeneration` while one
  /// waits for the next wrap.
  let generation: Int
  let activeGeneration: Int
  let programme: ChannelProgramme
  let totalSeconds: Double
  /// When the active generation started, epoch milliseconds. Nil for a channel
  /// that does not run unattended and that nobody has tuned into.
  let epochMs: Int?
  let serverTimeMs: Int
  let nowPlaying: ChannelNowSlice?
  let listeners: [ChannelListener]
  let media: [ChannelMediaRef]
  let started: Bool
  /// The rule currently matches nothing — a state to render, not an error.
  let empty: Bool
}

/// What the builder shows while a rule is being written.
struct ChannelPreview: Codable, Hashable, Sendable {
  let count: Int
  let totalSeconds: Double
  let sample: [String]
  let media: [ChannelMediaRef]
}

struct ChannelListResponse: Codable, Sendable {
  let items: [ChannelDoc]
}

struct ChannelMediaResponse: Codable, Sendable {
  let media: [ChannelMediaRef]
}

struct ChannelLiveRequest: Codable, Sendable {
  let live: Bool
}

struct ChannelMediaRequest: Codable, Sendable {
  let ids: [String]
}

// MARK: - The arithmetic

/// Where a channel is at an instant.
struct ChannelPosition: Hashable, Sendable {
  let index: Int
  let item: ChannelProgrammeItem
  /// Seconds into the current item — what the player seeks to.
  let into: Double
  /// Completed loops. The only moment a new generation may take over.
  let cycle: Int
  /// When the current cycle ends, epoch milliseconds.
  let nextWrapAtMs: Int
}

extension ChannelDoc {
  var cycleSeconds: Double {
    programme.items.reduce(0) { $0 + $1.seconds }
  }

  /// The same walk the server does, deliberately duplicated rather than
  /// fetched.
  ///
  /// Asking the server for the position every second would put the network in
  /// the middle of a shared moment: two clients with different round-trips
  /// would disagree by exactly their difference, which is the bug this whole
  /// feature is arranged to avoid.
  func position(atMs nowMs: Int) -> ChannelPosition? {
    let items = programme.items
    guard !items.isEmpty, let epochMs else { return nil }
    let total = cycleSeconds
    guard total > 0 else { return nil }

    let elapsed = max(0, Double(nowMs - epochMs) / 1000)
    let cycle = Int(elapsed / total)
    var offset = elapsed.truncatingRemainder(dividingBy: total)
    let wrapMs = epochMs + Int((Double(cycle + 1) * total * 1000).rounded())

    for (index, item) in items.enumerated() {
      if offset < item.seconds {
        return ChannelPosition(index: index, item: item, into: offset, cycle: cycle, nextWrapAtMs: wrapMs)
      }
      offset -= item.seconds
    }
    // Floating point can leave a sliver at the end of a cycle. It belongs to
    // the last item, not to a crash.
    let last = items.count - 1
    return ChannelPosition(index: last, item: items[last], into: 0, cycle: cycle, nextWrapAtMs: wrapMs)
  }

  /// What comes after `index`, wrapping, never naming what is playing.
  func upcoming(after index: Int, count: Int = 3) -> [ChannelProgrammeItem] {
    let items = programme.items
    // A closed range with a zero upper bound traps at runtime, so both the
    // one-item loop and a caller asking for nothing return early.
    guard items.count > 1, count > 0 else { return [] }
    let take = min(count, items.count - 1)
    return (1...take).map { step in items[(index + step) % items.count] }
  }

  func ref(for mediaId: String?) -> ChannelMediaRef? {
    guard let mediaId else { return nil }
    return media.first { $0.id == mediaId }
  }
}
