import Foundation
import Observation

/// Watch Together — the room's client brain (docs/design/WATCH_TOGETHER_SPEC.md).
///
/// Owns the room document, the canonical sync state, its OWN realtime socket
/// (ChatStore keeps its thread socket; the two never share), the server-clock
/// offset, and the host-duty engine. The player UI drives the drift corrector
/// off `computeTarget(now:)` + `applyingRemote` + `myLastSentVersion`; every
/// user intent is an async method here that turns into a §6 signal or a §8
/// REST call. Corrections are LOCAL only — this store never broadcasts drift.
@MainActor
@Observable
final class WatchRoomStore {
  /// One flying reaction, kept briefly for the overlay layer to animate.
  struct FlyingReaction: Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: String
    let emoji: String
    let position: Double?
    let receivedAt: Date
  }

  /// A pending ask-to-control capsule for the host UI (15 s lifetime).
  struct ControlRequest: Identifiable, Hashable, Sendable {
    var id: String { userId }
    let userId: String
    let receivedAt: Date
  }

  private let api: any MaxService

  // MARK: Observable room state

  private(set) var room: WatchRoom?
  /// The latest applied canonical state — the single source of playback truth.
  private(set) var state: WatchCanonicalState?
  private(set) var participants: [WatchParticipant] = []
  private(set) var bufferingUserIDs: Set<String> = []
  private(set) var reactions: [FlyingReaction] = []
  private(set) var activeVote: WatchVote?
  private(set) var suggestions: [WatchSuggestionEvent] = []
  private(set) var controlRequests: [ControlRequest] = []
  private(set) var queue: [WatchQueueItem] = []
  private(set) var guestLinks: [WatchGuestLink] = []
  private(set) var scheduledByConversation: [String: [WatchScheduledEntry]] = [:]
  private(set) var historyByConversation: [String: [WatchHistoryEntry]] = [:]
  /// Set when the room ends (any reason); the terminal card reads its stats.
  private(set) var endedEvent: WatchRoomEndedEvent?
  /// True after THIS user was kicked (soft; re-joinable) — the kicked card.
  private(set) var wasKicked = false
  /// The last T-10 reminder off the socket; chat surfaces render the banner.
  private(set) var lastScheduledReminder: WatchScheduledReminderEvent?
  /// The most recent `watch.room.created` seen on the socket — chat surfaces
  /// use it to show a "watch party live" banner.
  private(set) var lastRoomCreated: WatchRoomCreatedEvent?
  private(set) var lastNudgeFromUserID: String?
  private(set) var isRealtimeConnected = false
  private(set) var errorMessage: String?
  private(set) var myUserID: String?
  /// The playing item resolved to a full media model (the slideshow engine
  /// needs `kind`, the UI wants title/poster).
  private(set) var currentMediaItem: MaxMediaItem?

  // MARK: Drift-corrector surface (player-facing)

  /// Raised by the player around ANY remote application — including corrective
  /// seeks — so the local player-event→signal path stays mute (echo-proofing
  /// rule 1). The store never flips it; ownership is the player's.
  var applyingRemote = false
  /// The `{version}` answered by the last state-mutating signal this client
  /// sent; its own `watch.state.updated` echo carries the same number.
  private(set) var myLastSentVersion = 0
  /// True when the last applied state was this client's own echo, so the
  /// player skips re-applying what it already did locally.
  private(set) var lastStateWasOwnEcho = false

  // MARK: Private machinery

  private var lastAppliedVersion = 0
  private var realtimeRoomID: String?
  private var realtimeSocket: URLSessionWebSocketTask?
  private var realtimeTask: Task<Void, Never>?
  private var pingTask: Task<Void, Never>?
  private var tickTask: Task<Void, Never>?
  private var dutyTask: Task<Void, Never>?

  private struct ClockSample { let rtt: Double; let offset: Double }
  private var clockSamples: [ClockSample] = []
  private(set) var clockOffsetMs: Double = 0

  /// Wall-clock ms when each user's buffering report began (arbiter input).
  private var bufferingSince: [String: Double] = [:]
  private var waitPauseActive = false
  private var allClearSinceMs: Double?
  private var voteEndSentForEndsAt: Double?
  private var breakResumeSentForVersion: Int?
  private var lastSlideAdvanceAtMs: Double?
  private var advancementInFlight = false

  init(api: any MaxService) {
    self.api = api
  }

  // MARK: Derived truths

  var isInRoom: Bool { room != nil && endedEvent == nil && !wasKicked }
  var hostID: String? { room?.hostId }
  var isHost: Bool {
    guard let myUserID, let hostID = room?.hostId else { return false }
    return hostID.caseInsensitiveCompare(myUserID) == .orderedSame
  }
  var settings: WatchSettings { room?.settings ?? .defaults }
  var myRole: String {
    if isHost { return "host" }
    guard let myUserID else { return "viewer" }
    return participants.first {
      $0.userId.caseInsensitiveCompare(myUserID) == .orderedSame
    }?.role ?? "viewer"
  }
  /// Whether this user's transport is live (spec §5 permission matrix).
  var canControl: Bool {
    isHost || myRole == "controller" || settings.whoCanControl == "everyone"
  }

  /// The server's idea of "now", epoch ms — wall clock plus the EWMA offset.
  func serverNowMs() -> Double {
    Date().timeIntervalSince1970 * 1000 + clockOffsetMs
  }

  /// Spec §1, THE identity of the protocol:
  /// `target(t) = (!playing || t < startAt) ? position : position + (t - startAt)/1000 * rate`.
  /// Pass a server-time instant (epoch ms) or let it default to `serverNowMs()`.
  /// While paused — a break included — `startAt` is irrelevant and the frozen
  /// `position` IS the target; during the start countdown (`t < startAt`) the
  /// position also freezes so every screen shows the same held frame.
  func computeTarget(now: Double? = nil) -> Double? {
    guard let state else { return nil }
    let t = now ?? serverNowMs()
    guard state.playing else { return state.position }
    let startAt = state.startAt ?? state.serverAt
    guard t >= startAt else { return state.position }
    return state.position + (t - startAt) / 1000 * state.rate
  }

  /// Seconds until playback becomes effective (the 3-2-1 countdown), nil when
  /// none is pending.
  var startCountdownRemaining: Double? {
    guard let state, state.playing, let startAt = state.startAt else { return nil }
    let remaining = (startAt - serverNowMs()) / 1000
    return remaining > 0 ? remaining : nil
  }

  /// Seconds left on the shared break, nil when no break is running.
  var breakRemaining: Double? {
    guard let state, let breakUntil = state.breakUntil else { return nil }
    let remaining = (breakUntil - serverNowMs()) / 1000
    return remaining > 0 ? remaining : nil
  }

  /// True while the host has paused everyone for a buffering peer.
  var isWaitingForBuffering: Bool {
    guard let state else { return false }
    return !state.playing && state.cause == "buffer-wait"
  }

  // MARK: - Room lifecycle

  /// Opens a room on the conversation and enters it.
  @discardableResult
  func create(
    conversationID: String,
    mediaID: String? = nil,
    source: WatchSource? = nil,
    title: String? = nil,
    emoji: String? = nil,
    settings: WatchSettingsPatch? = nil,
    resumeFromRoomID: String? = nil
  ) async -> WatchRoom? {
    do {
      let created = try await api.createWatchRoom(
        conversationID: conversationID,
        mediaID: mediaID,
        source: source,
        title: title,
        emoji: emoji,
        settings: settings,
        resumeFromRoomID: resumeFromRoomID
      )
      await install(created)
      return created
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return nil
    }
  }

  /// Joins an existing room by id (invite bubble, room banner).
  @discardableResult
  func join(roomID: String) async -> Bool {
    do {
      let joined = try await api.joinWatchRoom(roomID: roomID)
      await install(joined)
      return true
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return false
    }
  }

  /// Finds and joins the conversation's active room, if one is live.
  @discardableResult
  func joinActiveRoom(conversationID: String) async -> Bool {
    do {
      let active = try await api.activeWatchRoom(conversationID: conversationID)
      return await join(roomID: active.id)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return false
    }
  }

  /// Soft-exits the room. Host handoff happens server-side.
  func leave() async {
    guard let roomID = room?.id else { return }
    _ = try? await api.leaveWatchRoom(roomID: roomID)
    teardown()
  }

  /// Host-only: ends the room for everyone (reason `host_ended`).
  func end() async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.endWatchRoom(roomID: roomID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
    // The room.ended fan-out normally lands first; this is the offline fallback.
    if endedEvent == nil {
      endedEvent = WatchRoomEndedEvent(
        roomId: roomID,
        reason: "host_ended",
        endedBy: myUserID,
        stats: nil
      )
    }
    stopRealtime()
  }

  /// Full refetch of the room doc — the reconnect resync source (§8).
  func resync() async {
    guard let roomID = room?.id else { return }
    do {
      let fresh = try await api.watchRoom(roomID: roomID)
      apply(document: fresh)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  /// Fast resync from the Redis hash only.
  func refreshState() async {
    guard let roomID = room?.id else { return }
    do {
      let fresh = try await api.watchRoomState(roomID: roomID)
      applyState(fresh)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  /// Back to idle — sign-out and app reset path.
  func reset() {
    teardown()
    scheduledByConversation = [:]
    historyByConversation = [:]
    lastRoomCreated = nil
    lastScheduledReminder = nil
    errorMessage = nil
    myUserID = nil
  }

  /// Dismisses the terminal card (ended/kicked): drops every room leftover so
  /// the player carries on solo. Conversation-scoped caches survive.
  func acknowledgeTerminalState() {
    teardown()
  }

  private func install(_ document: WatchRoom) async {
    teardown()
    myUserID = await api.currentUserID()
    endedEvent = nil
    apply(document: document)
    await resolveCurrentMedia()
    startRealtime(for: document.id)
    refreshHostDuties()
  }

  private func apply(document: WatchRoom) {
    room = document
    participants = document.participants ?? participants
    queue = document.queue ?? queue
    activeVote = document.activeVote
    if let liveState = document.state {
      lastAppliedVersion = 0
      applyState(liveState)
    }
  }

  private func teardown() {
    stopRealtime()
    room = nil
    state = nil
    participants = []
    bufferingUserIDs = []
    bufferingSince = [:]
    reactions = []
    activeVote = nil
    suggestions = []
    controlRequests = []
    queue = []
    guestLinks = []
    endedEvent = nil
    wasKicked = false
    lastNudgeFromUserID = nil
    currentMediaItem = nil
    lastAppliedVersion = 0
    myLastSentVersion = 0
    lastStateWasOwnEcho = false
    applyingRemote = false
    clockSamples = []
    clockOffsetMs = 0
    waitPauseActive = false
    allClearSinceMs = nil
    voteEndSentForEndsAt = nil
    breakResumeSentForVersion = nil
    lastSlideAdvanceAtMs = nil
    advancementInFlight = false
    MaxAccessibilityAnnouncer.shared.cancelPending()
  }

  // MARK: - Signals (spec §6)

  /// Resumes playback. The server stamps `startAt` (+3 s when the countdown is
  /// enabled) and clears any break.
  func play(atPosition position: Double) async {
    await signal(WatchSignalType.play, ["position": .number(position)])
  }

  func pause(atPosition position: Double) async {
    await signal(WatchSignalType.pause, ["position": .number(position)])
  }

  /// Absolute reposition — sent on scrub-END only, never during drag (§1.4).
  func seek(to position: Double, playing: Bool) async {
    await signal(
      WatchSignalType.seek,
      ["position": .number(position), "playing": .bool(playing)]
    )
  }

  func setRate(_ rate: Double) async {
    let clamped = min(max(rate, 0.5), 2.0)
    await signal(WatchSignalType.rate, ["rate": .number(clamped)])
  }

  /// Switches the room's media (position resets to 0, paused). The server
  /// validates visibility for every active participant.
  func changeMedia(mediaID: String, source: WatchSource? = nil) async {
    var payload: [String: JSONValue] = ["mediaId": .string(mediaID)]
    if let source {
      payload["source"] = .object([
        "mode": .string(source.mode),
        "kind": .string(source.kind),
        "search": .string(source.search),
        "sort": .string(source.sort),
      ])
    }
    await signal(WatchSignalType.media, payload)
  }

  /// Sets the shared A-B loop.
  func setLoop(a: Double, b: Double) async {
    await signal(WatchSignalType.loop, ["a": .number(a), "b": .number(b)])
  }

  func clearLoop() async {
    await signal(WatchSignalType.loop, [:])
  }

  /// Shared break, 30...1800 seconds. The host-duty engine auto-resumes.
  func startBreak(seconds: Int) async {
    let clamped = min(max(seconds, 30), 1800)
    await signal(WatchSignalType.breakSignal, ["seconds": .number(Double(clamped))])
  }

  /// Reports this client's buffering to the wait-for-buffering arbiter. Never
  /// mutates canonical state server-side.
  func setBuffering(_ buffering: Bool) async {
    if let myUserID {
      if buffering {
        bufferingUserIDs.insert(myUserID)
        if bufferingSince[myUserID] == nil {
          bufferingSince[myUserID] = Date().timeIntervalSince1970 * 1000
        }
      } else {
        bufferingUserIDs.remove(myUserID)
        bufferingSince[myUserID] = nil
      }
    }
    await signal(WatchSignalType.buffering, ["buffering": .bool(buffering)])
  }

  func sendReaction(emoji: String, position: Double) async {
    await signal(
      WatchSignalType.reaction,
      ["emoji": .string(emoji), "position": .number(position)]
    )
  }

  /// "Come watch" ping to everyone in the conversation.
  func sendNudge() async {
    await signal(WatchSignalType.nudge, [:])
  }

  /// Viewer's ask-to-control: the host gets a 15 s allow/deny capsule. Deny is
  /// client-side — no server call.
  func requestControl() async {
    await signal(WatchSignalType.controlRequest, [:])
  }

  func suggest(mediaID: String) async {
    await signal(WatchSignalType.suggest, ["mediaId": .string(mediaID)])
  }

  /// Starts a vote over 2...6 candidates lasting 15...120 seconds.
  func startVote(mediaIDs: [String], seconds: Int) async {
    let clamped = min(max(seconds, 15), 120)
    await signal(
      WatchSignalType.voteStart,
      [
        "mediaIds": .array(mediaIDs.map { .string($0) }),
        "seconds": .number(Double(clamped)),
      ]
    )
  }

  func castVote(optionIndex: Int) async {
    await signal(WatchSignalType.voteCast, ["optionIndex": .number(Double(optionIndex))])
  }

  func endVote() async {
    await signal(WatchSignalType.voteEnd, [:])
  }

  /// Dismisses a control-request capsule locally (deny or timeout).
  func dismissControlRequest(userID: String) {
    controlRequests.removeAll { $0.userId == userID }
  }

  @discardableResult
  private func signal(_ type: String, _ payload: [String: JSONValue]) async -> Int? {
    guard let roomID = room?.id else { return nil }
    do {
      let response = try await api.sendWatchSignal(
        roomID: roomID,
        type: type,
        payload: .object(payload)
      )
      if let version = response.version {
        myLastSentVersion = version
      }
      return response.version
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return nil
    }
  }

  // MARK: - Room management (spec §8)

  /// Host-only settings merge; the merged object comes back on the socket.
  func updateSettings(_ patch: WatchSettingsPatch) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.updateWatchSettings(roomID: roomID, patch: patch)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func updateMeta(title: String?, emoji: String?) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.updateWatchRoomMeta(roomID: roomID, title: title, emoji: emoji)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func replaceQueue(mediaIDs: [String]) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.replaceWatchQueue(roomID: roomID, mediaIDs: mediaIDs)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func addToQueue(mediaID: String) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.addWatchQueueItem(roomID: roomID, mediaID: mediaID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func removeQueueItem(index: Int) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.removeWatchQueueItem(roomID: roomID, index: index)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  /// Host-only promote/demote (`"controller"` / `"viewer"`).
  func setParticipantRole(userID: String, role: String) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.setWatchParticipantRole(roomID: roomID, userID: userID, role: role)
      dismissControlRequest(userID: userID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func kick(userID: String) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.kickWatchParticipant(roomID: roomID, userID: userID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func transferHost(to userID: String) async {
    guard let roomID = room?.id else { return }
    do {
      _ = try await api.transferWatchHost(roomID: roomID, userID: userID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func loadHistory(conversationID: String, limit: Int = 20) async {
    do {
      historyByConversation[conversationID] = try await api.watchHistory(
        conversationID: conversationID,
        limit: limit
      )
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func loadGuestLinks() async {
    guard let roomID = room?.id else { return }
    do {
      guestLinks = try await api.watchGuestLinks(roomID: roomID)
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  @discardableResult
  func createGuestLink(expiresInHours: Int? = nil, maxUses: Int? = nil) async -> WatchGuestLink? {
    guard let roomID = room?.id else { return nil }
    do {
      let link = try await api.createWatchGuestLink(
        roomID: roomID,
        expiresInHours: expiresInHours,
        maxUses: maxUses
      )
      await loadGuestLinks()
      return link
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return nil
    }
  }

  func revokeGuestLink(linkID: String) async {
    do {
      _ = try await api.revokeWatchGuestLink(linkID: linkID)
      guestLinks.removeAll { $0.id == linkID }
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  func loadScheduled(conversationID: String) async {
    do {
      scheduledByConversation[conversationID] = try await api.watchScheduled(
        conversationID: conversationID
      )
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  @discardableResult
  func schedule(
    conversationID: String,
    scheduledAt: String,
    title: String? = nil,
    emoji: String? = nil,
    mediaID: String? = nil,
    source: WatchSource? = nil
  ) async -> WatchScheduledEntry? {
    do {
      let entry = try await api.createWatchScheduled(
        conversationID: conversationID,
        scheduledAt: scheduledAt,
        title: title,
        emoji: emoji,
        mediaID: mediaID,
        source: source
      )
      var rows = scheduledByConversation[conversationID] ?? []
      rows.removeAll { $0.id == entry.id }
      rows.append(entry)
      rows.sort { $0.scheduledAt < $1.scheduledAt }
      scheduledByConversation[conversationID] = rows
      return entry
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
      return nil
    }
  }

  func cancelScheduled(id: String, conversationID: String) async {
    do {
      _ = try await api.deleteWatchScheduled(id: id)
      scheduledByConversation[conversationID]?.removeAll { $0.id == id }
    } catch {
      errorMessage = ProductError.from(error, area: .watch).reason
    }
  }

  // MARK: - Host duties (spec §1) — the ONE decision-maker

  /// The player calls this when the current item reaches its end (host only).
  /// Advancement order: loop → queue → shuffle (same list API normal shuffle
  /// uses) → stop. Each advancement is an ordinary `media` signal.
  func handleItemEnded(atPosition position: Double) async {
    guard isHost, !advancementInFlight else { return }
    if settings.loop {
      await seek(to: state?.loopA ?? 0, playing: true)
      return
    }
    await advanceToNextItem(stopPosition: position)
  }

  /// Queue → shuffle → stop. Also the image slideshow's "next".
  func advanceToNextItem(stopPosition: Double) async {
    guard isHost, !advancementInFlight else { return }
    advancementInFlight = true
    defer { advancementInFlight = false }

    guard settings.autoPlayNext else {
      await pause(atPosition: stopPosition)
      return
    }
    if let next = queue.min(by: { $0.position < $1.position }) {
      await changeMedia(mediaID: next.mediaId, source: room?.source)
      await removeQueueItem(index: next.position)
      await play(atPosition: 0)
      return
    }
    let source = state?.source ?? room?.source
    if source?.mode == "shuffle" {
      if let nextID = await pickShuffleItem(source: source) {
        await changeMedia(mediaID: nextID, source: source)
        await play(atPosition: 0)
        return
      }
    }
    await pause(atPosition: stopPosition)
  }

  /// Picks the next random item through the SAME list/search API the normal
  /// shuffle player uses, never repeating the current item when avoidable.
  private func pickShuffleItem(source: WatchSource?) async -> String? {
    var query = MediaQuery()
    query.mode = "shuffle"
    query.search = source?.search ?? ""
    if let kind = source?.kind, !kind.isEmpty { query.kind = kind }
    query.limit = 50
    guard let response = try? await api.media(query: query) else { return nil }
    let currentID = state?.mediaId
    let candidates = response.items.filter { $0.id != currentID }
    return (candidates.randomElement() ?? response.items.randomElement())?.id
  }

  private func refreshHostDuties() {
    if isHost, isInRoom {
      startTickLoop()
      startDutyLoop()
    } else {
      tickTask?.cancel()
      tickTask = nil
      dutyTask?.cancel()
      dutyTask = nil
    }
  }

  /// `tick` every 5 s while playing — the periodic truth refresh. Silent while
  /// paused.
  private func startTickLoop() {
    guard tickTask == nil else { return }
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, !Task.isCancelled else { return }
        guard self.isHost, self.isInRoom else { continue }
        guard let state = self.state, state.playing,
              self.startCountdownRemaining == nil else { continue }
        if let target = self.computeTarget() {
          await self.signal(WatchSignalType.tick, ["position": .number(target)])
        }
      }
    }
  }

  /// The 500 ms arbiter: wait-for-buffering, break auto-resume, vote deadline,
  /// and the image slideshow — every decision made exactly once, by the host.
  private func startDutyLoop() {
    guard dutyTask == nil else { return }
    dutyTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, !Task.isCancelled else { return }
        guard self.isHost, self.isInRoom else { continue }
        await self.runBufferingArbiter()
        await self.runBreakResume()
        await self.runVoteDeadline()
        await self.runSlideshow()
      }
    }
  }

  private func runBufferingArbiter() async {
    guard settings.waitForBuffering, let state else { return }
    let nowMs = Date().timeIntervalSince1970 * 1000
    let stalledOverSecond = bufferingSince.values.contains { nowMs - $0 > 1000 }

    if !waitPauseActive {
      guard state.playing, stalledOverSecond else { return }
      waitPauseActive = true
      allClearSinceMs = nil
      if let target = computeTarget() {
        await pause(atPosition: target)
      }
    } else {
      if bufferingUserIDs.isEmpty {
        if allClearSinceMs == nil { allClearSinceMs = nowMs }
        // 1 s hysteresis so a flapping peer cannot strobe play/pause.
        if let clearSince = allClearSinceMs, nowMs - clearSince > 1000 {
          waitPauseActive = false
          allClearSinceMs = nil
          await play(atPosition: state.position)
        }
      } else {
        allClearSinceMs = nil
      }
    }
  }

  private func runBreakResume() async {
    guard let state, let breakUntil = state.breakUntil, !state.playing else { return }
    guard serverNowMs() >= breakUntil else { return }
    guard breakResumeSentForVersion != state.version else { return }
    breakResumeSentForVersion = state.version
    await play(atPosition: state.position)
  }

  private func runVoteDeadline() async {
    guard let vote = activeVote, !vote.closed, let endsAt = vote.endsAt else { return }
    guard serverNowMs() >= endsAt else { return }
    guard voteEndSentForEndsAt != endsAt else { return }
    voteEndSentForEndsAt = endsAt
    await endVote()
  }

  private func runSlideshow() async {
    guard let state, state.playing else { return }
    guard currentMediaItem?.kind.lowercased() == "image" else { return }
    let dwellMs = Double(min(max(settings.slideSeconds, 2), 30)) * 1000
    let nowMs = Date().timeIntervalSince1970 * 1000
    let anchor = lastSlideAdvanceAtMs ?? state.serverAt - clockOffsetMs
    guard nowMs - anchor >= dwellMs else { return }
    lastSlideAdvanceAtMs = nowMs
    await advanceToNextItem(stopPosition: 0)
  }

  private func resolveCurrentMedia() async {
    guard let mediaID = state?.mediaId ?? room?.mediaId else {
      currentMediaItem = nil
      return
    }
    if currentMediaItem?.id == mediaID { return }
    currentMediaItem = try? await api.mediaItem(id: mediaID)
  }

  // MARK: - Realtime (own socket; the ChatStore pattern, untouched there)

  private func startRealtime(for roomID: String) {
    guard realtimeRoomID != roomID else { return }
    stopRealtime()
    realtimeRoomID = roomID
    realtimeTask = Task { [weak self] in
      await self?.runRealtime(for: roomID)
    }
  }

  private func stopRealtime() {
    pingTask?.cancel()
    pingTask = nil
    tickTask?.cancel()
    tickTask = nil
    dutyTask?.cancel()
    dutyTask = nil
    realtimeTask?.cancel()
    realtimeTask = nil
    realtimeSocket?.cancel(with: .goingAway, reason: nil)
    realtimeSocket = nil
    realtimeRoomID = nil
    isRealtimeConnected = false
  }

  private func runRealtime(for roomID: String) async {
    var retryDelay = 1.0
    var isFirstConnection = true
    while !Task.isCancelled, realtimeRoomID == roomID {
      do {
        let socket = try await makeRealtimeSocket()
        realtimeSocket = socket
        socket.resume()

        // 5 pings at join sharpen the clock offset before the first target
        // computation; a reconnect resyncs the whole doc first (spec §8).
        if !isFirstConnection {
          await resync()
        }
        isFirstConnection = false
        for _ in 0..<5 {
          sendPing(roomID: roomID)
          try? await Task.sleep(for: .milliseconds(220))
        }
        startPingLoop(roomID: roomID)

        while !Task.isCancelled, realtimeRoomID == roomID {
          let message = try await socket.receive()
          let data: Data
          switch message {
          case .data(let value): data = value
          case .string(let value): data = Data(value.utf8)
          @unknown default: continue
          }
          retryDelay = 1
          isRealtimeConnected = true
          handleFrame(data)
        }
      } catch is CancellationError {
        break
      } catch {
        isRealtimeConnected = false
      }
      pingTask?.cancel()
      pingTask = nil
      realtimeSocket?.cancel(with: .goingAway, reason: nil)
      realtimeSocket = nil
      isRealtimeConnected = false
      guard !Task.isCancelled, realtimeRoomID == roomID else { break }
      try? await Task.sleep(for: .seconds(retryDelay))
      retryDelay = min(retryDelay * 2, 12)
    }
  }

  private func makeRealtimeSocket() async throws -> URLSessionWebSocketTask {
    let ticket = try await api.realtimeTicket()
    let baseURL = MaxConfiguration.fromBundle().baseURL
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }
    components.scheme = baseURL.scheme?.lowercased() == "https" ? "wss" : "ws"
    components.path = "/api/v2/realtime/connect"
    components.queryItems = [URLQueryItem(name: "ticket", value: ticket.ticket)]
    guard let url = components.url else { throw URLError(.badURL) }
    return URLSession.shared.webSocketTask(with: url)
  }

  /// One `watch.ping` every 10 s — the pong refines the clock offset and the
  /// `roomId` doubles as the presence heartbeat (ZADD XX server-side).
  private func startPingLoop(roomID: String) {
    pingTask?.cancel()
    pingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(10))
        guard let self, !Task.isCancelled else { return }
        self.sendPing(roomID: roomID)
      }
    }
  }

  private func sendPing(roomID: String) {
    guard let realtimeSocket else { return }
    guard UUID(uuidString: roomID) != nil else { return }
    let payload: [String: Any] = [
      "type": "watch.ping",
      "roomId": roomID,
      "t0": Int64(Date().timeIntervalSince1970 * 1000),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8) else { return }
    Task { try? await realtimeSocket.send(.string(text)) }
  }

  private func recordPong(_ pong: WatchPongEvent) {
    let t1 = Date().timeIntervalSince1970 * 1000
    let rtt = max(t1 - pong.t0, 0)
    let offset = pong.serverAt - (pong.t0 + t1) / 2
    clockSamples.append(ClockSample(rtt: rtt, offset: offset))
    if clockSamples.count > 30 {
      clockSamples.removeFirst(clockSamples.count - 30)
    }
    // EWMA over the lowest-RTT samples: jittery pings carry the least truth.
    let best = clockSamples.sorted { $0.rtt < $1.rtt }.prefix(8)
    guard var value = best.first?.offset else { return }
    for sample in best.dropFirst() {
      value = value * 0.7 + sample.offset * 0.3
    }
    clockOffsetMs = value
  }

  // MARK: - Event decoding & application (spec §7)

  private func handleFrame(_ data: Data) {
    let decoder = JSONDecoder()
    guard let header = try? decoder.decode(WatchEventHeader.self, from: data) else { return }

    func payload<T: Decodable & Sendable>(_ type: T.Type) -> T? {
      (try? decoder.decode(WatchEventFrame<T>.self, from: data))?.data
    }

    switch header.type {
    case WatchRealtimeEventType.pong:
      if let pong = payload(WatchPongEvent.self) { recordPong(pong) }

    case WatchRealtimeEventType.stateUpdated:
      if let fresh = payload(WatchCanonicalState.self) { applyState(fresh) }

    case WatchRealtimeEventType.participantJoined:
      guard let event = payload(WatchParticipantJoinedEvent.self),
            event.roomId == room?.id else { return }
      participants.removeAll { $0.userId == event.userId }
      participants.append(WatchParticipant(userId: event.userId, role: event.role))
      announceIfNotMe(event.userId, key: "watch.a11y.participant_joined", category: .roster)

    case WatchRealtimeEventType.participantLeft:
      guard let event = payload(WatchParticipantLeftEvent.self),
            event.roomId == room?.id else { return }
      participants.removeAll { $0.userId == event.userId }
      bufferingUserIDs.remove(event.userId)
      bufferingSince[event.userId] = nil
      // A kick lands as our own participant.left; the terminal card takes over.
      if isMe(event.userId), event.reason == "kicked" {
        wasKicked = true
        stopRealtime()
      }
      announceIfNotMe(event.userId, key: "watch.a11y.participant_left", category: .roster)

    case WatchRealtimeEventType.participantRole:
      guard let event = payload(WatchParticipantRoleEvent.self),
            event.roomId == room?.id else { return }
      if let index = participants.firstIndex(where: { $0.userId == event.userId }) {
        participants[index].role = event.role
      } else {
        participants.append(WatchParticipant(userId: event.userId, role: event.role))
      }
      dismissControlRequest(userID: event.userId)
      if isMe(event.userId) {
        MaxAccessibilityAnnouncer.shared.announce(
          key: event.role == "controller"
            ? "watch.a11y.control_granted"
            : "watch.a11y.control_revoked",
          category: .control
        )
      }

    case WatchRealtimeEventType.hostChanged:
      guard let event = payload(WatchHostChangedEvent.self),
            event.roomId == room?.id else { return }
      room?.hostId = event.hostId
      if let index = participants.firstIndex(where: { $0.userId == event.hostId }) {
        participants[index].role = "host"
      }
      MaxAccessibilityAnnouncer.shared.announce(
        key: isMe(event.hostId) ? "watch.a11y.you_are_host" : "watch.a11y.host_changed",
        category: .host
      )
      // Duties travel with the crown — a viewer-turned-host starts them now.
      refreshHostDuties()

    case WatchRealtimeEventType.queueUpdated:
      guard let event = payload(WatchQueueUpdatedEvent.self),
            event.roomId == room?.id else { return }
      queue = event.queue
      room?.queue = event.queue

    case WatchRealtimeEventType.settingsUpdated:
      guard let event = payload(WatchSettingsUpdatedEvent.self),
            event.roomId == room?.id else { return }
      room?.settings = event.settings
      MaxAccessibilityAnnouncer.shared.announce(
        key: "watch.a11y.settings_changed",
        category: .settings
      )

    case WatchRealtimeEventType.metaUpdated:
      guard let event = payload(WatchMetaUpdatedEvent.self),
            event.roomId == room?.id else { return }
      room?.title = event.title
      room?.emoji = event.emoji

    case WatchRealtimeEventType.buffering:
      guard let event = payload(WatchBufferingEvent.self),
            event.roomId == room?.id else { return }
      if event.buffering {
        bufferingUserIDs.insert(event.userId)
        if bufferingSince[event.userId] == nil {
          bufferingSince[event.userId] = Date().timeIntervalSince1970 * 1000
        }
      } else {
        bufferingUserIDs.remove(event.userId)
        bufferingSince[event.userId] = nil
      }

    case WatchRealtimeEventType.reaction:
      guard let event = payload(WatchReactionEvent.self),
            event.roomId == room?.id else { return }
      reactions.append(
        FlyingReaction(
          id: UUID(),
          userId: event.userId,
          emoji: event.emoji,
          position: event.position,
          receivedAt: Date()
        )
      )
      if reactions.count > 60 {
        reactions.removeFirst(reactions.count - 60)
      }
      MaxAccessibilityAnnouncer.shared.announceReaction(emoji: event.emoji)

    case WatchRealtimeEventType.nudge:
      guard let event = payload(WatchNudgeEvent.self),
            event.roomId == room?.id else { return }
      lastNudgeFromUserID = event.fromUserId

    case WatchRealtimeEventType.controlRequested:
      guard let event = payload(WatchControlRequestedEvent.self),
            event.roomId == room?.id, !isMe(event.userId) else { return }
      controlRequests.removeAll { $0.userId == event.userId }
      controlRequests.append(ControlRequest(userId: event.userId, receivedAt: Date()))
      if isHost {
        MaxAccessibilityAnnouncer.shared.announce(
          key: "watch.a11y.control_requested",
          category: .control
        )
      }

    case WatchRealtimeEventType.suggestion:
      guard let event = payload(WatchSuggestionEvent.self),
            event.roomId == room?.id else { return }
      suggestions.append(event)
      if suggestions.count > 20 {
        suggestions.removeFirst(suggestions.count - 20)
      }

    case WatchRealtimeEventType.voteUpdated:
      guard let vote = payload(WatchVote.self) else { return }
      if let voteRoomID = vote.roomId, voteRoomID != room?.id { return }
      let wasClosed = activeVote?.closed ?? false
      activeVote = vote
      // Host duty: a freshly closed vote plays the winner via a media signal.
      if vote.closed, !wasClosed, isHost, let winnerIndex = vote.winnerIndex,
         vote.options.indices.contains(winnerIndex) {
        let winner = vote.options[winnerIndex]
        Task { [weak self] in
          await self?.changeMedia(mediaID: winner)
          await self?.play(atPosition: 0)
        }
      }

    case WatchRealtimeEventType.roomCreated:
      if let event = payload(WatchRoomCreatedEvent.self) {
        lastRoomCreated = event
      }

    case WatchRealtimeEventType.roomEnded:
      guard let event = payload(WatchRoomEndedEvent.self),
            event.roomId == room?.id else { return }
      endedEvent = event
      stopRealtime()
      MaxAccessibilityAnnouncer.shared.announce(
        key: "watch.a11y.room_ended",
        category: .lifecycle
      )

    case WatchRealtimeEventType.scheduledCreated:
      guard let event = payload(WatchScheduledCreatedEvent.self) else { return }
      var rows = scheduledByConversation[event.conversationId] ?? []
      rows.removeAll { $0.id == event.id }
      rows.append(
        WatchScheduledEntry(
          id: event.id,
          conversationId: event.conversationId,
          createdBy: nil,
          title: event.title,
          emoji: event.emoji,
          mediaId: event.mediaId,
          source: nil,
          scheduledAt: event.scheduledAt,
          remindedAt: nil,
          startedRoomId: nil,
          canceledAt: nil,
          createdAt: nil
        )
      )
      rows.sort { $0.scheduledAt < $1.scheduledAt }
      scheduledByConversation[event.conversationId] = rows

    case WatchRealtimeEventType.scheduledCanceled:
      guard let event = payload(WatchScheduledCanceledEvent.self) else { return }
      for key in scheduledByConversation.keys {
        scheduledByConversation[key]?.removeAll { $0.id == event.id }
      }

    case WatchRealtimeEventType.scheduledReminder:
      // Chat surfaces render the T-10 banner off this; only the newest matters.
      if let event = payload(WatchScheduledReminderEvent.self) {
        lastScheduledReminder = event
      }

    default:
      // Not a watch frame (the shared socket also carries chat.* traffic).
      return
    }
  }

  /// Version-guarded canonical-state application (echo-proofing rules 2).
  private func applyState(_ fresh: WatchCanonicalState) {
    guard fresh.roomId == room?.id || room == nil else { return }
    guard fresh.version > lastAppliedVersion else { return }
    lastAppliedVersion = fresh.version
    lastStateWasOwnEcho = isMe(fresh.actorId ?? "") && fresh.version == myLastSentVersion

    let mediaChanged = fresh.mediaId != state?.mediaId
    state = fresh
    room?.state = fresh
    if let mediaId = fresh.mediaId { room?.mediaId = mediaId }
    if let source = fresh.source { room?.source = source }
    if mediaChanged {
      lastSlideAdvanceAtMs = Date().timeIntervalSince1970 * 1000
      Task { [weak self] in await self?.resolveCurrentMedia() }
    }
    if fresh.breakUntil == nil { breakResumeSentForVersion = nil }
    if fresh.cause != "buffer-wait", fresh.playing { waitPauseActive = false }
    refreshHostDuties()
  }

  private func isMe(_ userID: String) -> Bool {
    guard let myUserID, !userID.isEmpty else { return false }
    return userID.caseInsensitiveCompare(myUserID) == .orderedSame
  }

  private func announceIfNotMe(
    _ userID: String,
    key: String,
    category: MaxAccessibilityAnnouncer.Category
  ) {
    guard !isMe(userID) else { return }
    MaxAccessibilityAnnouncer.shared.announce(key: key, category: category)
  }
}
