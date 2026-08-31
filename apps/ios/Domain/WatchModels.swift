import Foundation

// MARK: - Watch Together wire models
//
// Every struct here mirrors docs/design/WATCH_TOGETHER_SPEC.md §§4, 6, 7 and 8
// key-for-key. The backend decodes client payloads with DisallowUnknownFields,
// so request bodies must carry exactly the documented keys; response models
// keep rarely-populated fields optional so a lean row still decodes.

/// The playback source descriptor carried inside the canonical state and the
/// room row: `{"mode":"single|queue|shuffle","kind":"","search":"","sort":""}`.
struct WatchSource: Codable, Hashable, Sendable {
  var mode: String
  var kind: String
  var search: String
  var sort: String

  init(mode: String = "single", kind: String = "", search: String = "", sort: String = "") {
    self.mode = mode
    self.kind = kind
    self.search = search
    self.sort = sort
  }
}

/// The canonical, host-authoritative sync state — the payload of
/// `watch.state.updated` and `GET /watch/rooms/{roomID}/state`.
///
/// All timestamps are epoch **milliseconds** stamped by the server. The
/// protocol identity (spec §1) is
/// `target(t) = (!playing || t < startAt) ? position : position + (t - startAt)/1000 * rate`.
struct WatchCanonicalState: Codable, Hashable, Sendable {
  let roomId: String
  /// Server-assigned monotonic version. Clients drop `version <= lastApplied`
  /// and their own echo (`actorId == me && version == myLastSentVersion`).
  let version: Int
  let mediaId: String?
  let playing: Bool
  /// Seconds into the media at `startAt` (or simply the frozen position while
  /// paused).
  let position: Double
  let rate: Double
  /// Epoch ms stamped by the server at write time.
  let serverAt: Double
  /// Epoch ms when playback becomes effective. While `now < startAt` clients
  /// freeze at `position` and render the 3-2-1 countdown.
  let startAt: Double?
  /// Shared A-B loop bounds in seconds, both nil when no loop is set.
  let loopA: Double?
  let loopB: Double?
  /// Epoch ms until which the room is on a break (`playing` is false).
  let breakUntil: Double?
  let actorId: String?
  /// One of `play|pause|seek|rate|media|tick|loop|break|buffer-wait`.
  let cause: String?
  let source: WatchSource?
}

/// Room settings (spec §4). `PATCH settings` merges known keys and broadcasts
/// the complete merged object.
struct WatchSettings: Codable, Hashable, Sendable {
  /// "host" | "everyone"
  var whoCanControl: String
  var waitForBuffering: Bool
  var allowMidRollJoin: Bool
  var chatEnabled: Bool
  var reactionsEnabled: Bool
  var autoPlayNext: Bool
  /// Loop the current item at end.
  var loop: Bool
  /// 3-2-1 countdown on play.
  var countdownEnabled: Bool
  /// Any participant may ADD to the queue.
  var queueCollaborative: Bool
  /// Image slideshow dwell, 2...30 seconds.
  var slideSeconds: Int
  /// 2...10.
  var maxParticipants: Int

  /// The server-side defaults, materialized so clients can render a settings
  /// sheet before the first `watch.settings.updated` arrives.
  static let defaults = WatchSettings(
    whoCanControl: "host",
    waitForBuffering: true,
    allowMidRollJoin: true,
    chatEnabled: true,
    reactionsEnabled: true,
    autoPlayNext: true,
    loop: false,
    countdownEnabled: true,
    queueCollaborative: true,
    slideSeconds: 5,
    maxParticipants: 10
  )
}

/// A partial settings object for `PATCH .../settings`. Synthesized Codable
/// omits nil fields, so only the keys the host actually changed are sent —
/// which is exactly what the merge endpoint expects.
struct WatchSettingsPatch: Codable, Hashable, Sendable {
  var whoCanControl: String?
  var waitForBuffering: Bool?
  var allowMidRollJoin: Bool?
  var chatEnabled: Bool?
  var reactionsEnabled: Bool?
  var autoPlayNext: Bool?
  var loop: Bool?
  var countdownEnabled: Bool?
  var queueCollaborative: Bool?
  var slideSeconds: Int?
  var maxParticipants: Int?

  init(
    whoCanControl: String? = nil,
    waitForBuffering: Bool? = nil,
    allowMidRollJoin: Bool? = nil,
    chatEnabled: Bool? = nil,
    reactionsEnabled: Bool? = nil,
    autoPlayNext: Bool? = nil,
    loop: Bool? = nil,
    countdownEnabled: Bool? = nil,
    queueCollaborative: Bool? = nil,
    slideSeconds: Int? = nil,
    maxParticipants: Int? = nil
  ) {
    self.whoCanControl = whoCanControl
    self.waitForBuffering = waitForBuffering
    self.allowMidRollJoin = allowMidRollJoin
    self.chatEnabled = chatEnabled
    self.reactionsEnabled = reactionsEnabled
    self.autoPlayNext = autoPlayNext
    self.loop = loop
    self.countdownEnabled = countdownEnabled
    self.queueCollaborative = queueCollaborative
    self.slideSeconds = slideSeconds
    self.maxParticipants = maxParticipants
  }
}

/// One active participant row inside the room doc. Roles are
/// `viewer | controller | host`.
struct WatchParticipant: Codable, Hashable, Identifiable, Sendable {
  var id: String { userId }
  let userId: String
  var role: String
  let joinedAt: String?

  init(userId: String, role: String, joinedAt: String? = nil) {
    self.userId = userId
    self.role = role
    self.joinedAt = joinedAt
  }
}

/// One queued item — the payload rows of `watch.queue.updated`.
struct WatchQueueItem: Codable, Hashable, Identifiable, Sendable {
  var id: String { "\(position)-\(mediaId)" }
  let position: Int
  let mediaId: String
  let addedBy: String
}

/// Aggregate-only room stats, written once at room end (never per-user).
struct WatchRoomStats: Codable, Hashable, Sendable {
  let durationSeconds: Double?
  let participantCount: Int?
  let reactionCount: Int?
  let mediaChanges: Int?
  let messageCount: Int?
  /// Reaction-position histogram, 100 bins.
  let reactionBins: [Int]?
}

/// The full room document (`POST /watch/rooms`, `GET /watch/rooms/{roomID}`,
/// `POST .../join`) — row + active participants + queue + settings + live
/// state + activeVote. This is the reconnect resync source.
struct WatchRoom: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let conversationId: String
  let createdBy: String?
  var hostId: String
  var mediaId: String?
  var title: String
  var emoji: String
  var source: WatchSource?
  var settings: WatchSettings?
  let stats: WatchRoomStats?
  let finalPosition: Double?
  let createdAt: String?
  let endedAt: String?
  let endedBy: String?
  /// `host_ended | idle | empty | media_removed`.
  let endedReason: String?
  var participants: [WatchParticipant]?
  var queue: [WatchQueueItem]?
  var state: WatchCanonicalState?
  var activeVote: WatchVote?
}

/// A scheduled watch party row (`POST /watch/scheduled`, `GET /watch/scheduled`).
struct WatchScheduledEntry: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let conversationId: String
  let createdBy: String?
  let title: String
  let emoji: String
  let mediaId: String?
  let source: WatchSource?
  /// RFC3339, strictly in the future at creation time.
  let scheduledAt: String
  let remindedAt: String?
  let startedRoomId: String?
  let canceledAt: String?
  let createdAt: String?
}

/// One ended room in `GET /watch/history` — newest first.
struct WatchHistoryEntry: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let emoji: String
  let mediaId: String?
  let createdAt: String?
  let endedAt: String?
  let stats: WatchRoomStats?
  /// Where playback stopped, for "resume" (`resumeFromRoomId`).
  let finalPosition: Double?
  let source: WatchSource?
}

/// An external guest link. The create endpoint answers `{id, token, url}`;
/// list rows mirror share_links (expiry, budget, revocation).
struct WatchGuestLink: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let token: String?
  /// The public path, `/w/{token}`.
  let url: String?
  let expiresAt: String?
  let maxUses: Int?
  let useCount: Int?
  let revokedAt: String?
  let createdAt: String?
}

/// The active vote — the payload of `watch.vote.updated` and the room doc's
/// `activeVote`.
struct WatchVote: Codable, Hashable, Sendable {
  let roomId: String?
  /// Candidate media ids, 2...6.
  let options: [String]
  let counts: [Int]
  /// Epoch ms when the vote closes.
  let endsAt: Double?
  let closed: Bool
  let winnerIndex: Int?
}

// MARK: - List wrappers

/// The `{"items":[...]}` envelope the history listing answers with.
struct WatchHistoryListResponse: Codable, Sendable {
  let items: [WatchHistoryEntry]
}

/// The `{"items":[...]}` envelope the scheduled listing answers with.
struct WatchScheduledListResponse: Codable, Sendable {
  let items: [WatchScheduledEntry]
}

/// The `{"items":[...]}` envelope the guest-links listing answers with.
struct WatchGuestLinkListResponse: Codable, Sendable {
  let items: [WatchGuestLink]
}

/// State-mutating signals answer `{version}` so the sender can suppress its
/// own `watch.state.updated` echo. Relay-only signals answer without one.
struct WatchSignalResponse: Codable, Sendable {
  let version: Int?
}

// MARK: - Signal types (spec §6)

enum WatchSignalType {
  static let play = "play"
  static let pause = "pause"
  static let seek = "seek"
  static let rate = "rate"
  static let media = "media"
  static let loop = "loop"
  static let breakSignal = "break"
  static let tick = "tick"
  static let buffering = "buffering"
  static let reaction = "reaction"
  static let nudge = "nudge"
  static let controlRequest = "control.request"
  static let suggest = "suggest"
  static let voteStart = "vote.start"
  static let voteCast = "vote.cast"
  static let voteEnd = "vote.end"
}

// MARK: - Realtime events (spec §7)
//
// Standard envelope `{version:1, type, data, occurredAt}` — the same frame
// shape as `ChatRealtimeEnvelope`, but `data` payloads differ per type, so the
// store first peeks at the header and then decodes the typed frame.

/// The thin first-pass decode: just enough to route on `type`.
struct WatchEventHeader: Decodable, Sendable {
  let type: String
}

/// The typed second-pass decode for one known `watch.*` event.
struct WatchEventFrame<Payload: Decodable & Sendable>: Decodable, Sendable {
  let version: Int?
  let type: String
  let data: Payload
  let occurredAt: String?
}

enum WatchRealtimeEventType {
  static let roomCreated = "watch.room.created"
  static let roomEnded = "watch.room.ended"
  static let participantJoined = "watch.participant.joined"
  static let participantLeft = "watch.participant.left"
  static let participantRole = "watch.participant.role"
  static let hostChanged = "watch.host.changed"
  static let stateUpdated = "watch.state.updated"
  static let queueUpdated = "watch.queue.updated"
  static let settingsUpdated = "watch.settings.updated"
  static let metaUpdated = "watch.meta.updated"
  static let buffering = "watch.buffering"
  static let reaction = "watch.reaction"
  static let nudge = "watch.nudge"
  static let controlRequested = "watch.control.requested"
  static let suggestion = "watch.suggestion"
  static let voteUpdated = "watch.vote.updated"
  static let scheduledCreated = "watch.scheduled.created"
  static let scheduledReminder = "watch.scheduled.reminder"
  static let scheduledCanceled = "watch.scheduled.canceled"
  static let pong = "watch.pong"
}

struct WatchRoomCreatedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let conversationId: String
  let hostId: String
  let mediaId: String?
  let title: String
  let emoji: String
  let settings: WatchSettings?
  let source: WatchSource?
}

struct WatchRoomEndedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  /// `host_ended | idle | empty | media_removed`.
  let reason: String
  let endedBy: String?
  let stats: WatchRoomStats?
}

struct WatchParticipantJoinedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  let role: String
}

struct WatchParticipantLeftEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  /// `left | kicked | timeout`.
  let reason: String?
}

struct WatchParticipantRoleEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  let role: String
}

struct WatchHostChangedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let hostId: String
  let previousHostId: String?
  /// `transfer | timeout | left`.
  let reason: String?
}

struct WatchQueueUpdatedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let queue: [WatchQueueItem]
}

struct WatchSettingsUpdatedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let settings: WatchSettings
  let actorId: String?
}

struct WatchMetaUpdatedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let title: String
  let emoji: String
}

struct WatchBufferingEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  let buffering: Bool
}

struct WatchReactionEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  let emoji: String
  /// Seconds into the media when the reaction fired.
  let position: Double?
}

struct WatchNudgeEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let fromUserId: String
}

struct WatchControlRequestedEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
}

struct WatchSuggestionEvent: Decodable, Hashable, Sendable {
  let roomId: String
  let userId: String
  let mediaId: String
}

struct WatchScheduledCreatedEvent: Decodable, Hashable, Sendable {
  let id: String
  let conversationId: String
  let title: String
  let emoji: String
  let scheduledAt: String
  let mediaId: String?
}

struct WatchScheduledReminderEvent: Decodable, Hashable, Sendable {
  let id: String
  let conversationId: String
  let title: String
  let emoji: String
  let scheduledAt: String
  let mediaId: String?
  let minutesLeft: Int?
}

struct WatchScheduledCanceledEvent: Decodable, Hashable, Sendable {
  let id: String
}

/// Socket-direct ping reply, never fanned out: `{t0, serverAt}` (both epoch ms).
struct WatchPongEvent: Decodable, Hashable, Sendable {
  let t0: Double
  let serverAt: Double
}
