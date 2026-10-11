import Foundation

/// Channels — always-running broadcasts built from a vault rule.
///
/// The one thing to understand before changing anything here: THE SERVER NEVER
/// TELLS US WHERE TO SEEK. It hands over a frozen programme and the instant it
/// started, and this store does the arithmetic (`ChannelDoc.position(atMs:)`).
/// That is what lets two devices agree with no message between them, and what
/// keeps the answer right while a request is in flight or the connection is
/// gone.
///
/// See docs/design/channels/LOGIC.md.
@MainActor
@Observable
final class ChannelStore {
  private(set) var channels: [ChannelDoc] = []
  private(set) var isLoading = false
  private(set) var loaded = false
  var failure: String?

  /// The channel this device is tuned into, if any.
  private(set) var tunedID: String?

  /// Every ref this device has ever seen, per channel, keyed by media id.
  ///
  /// A channel ships refs only for what it is about to name. That is right for
  /// the shared timeline and not enough for somebody OFF AIR, who walks their
  /// own cursor and can reach any item in the loop — so what arrives is kept,
  /// and what is missing is fetched.
  private(set) var refs: [String: [String: ChannelMediaRef]] = [:]

  /// serverNow − localNow, in milliseconds, from the last response. A device an
  /// hour fast would otherwise sit an hour into the loop, alone, with nothing
  /// on screen to explain it.
  private(set) var clockDeltaMs = 0

  private let api: any MaxService
  private var heartbeat: Task<Void, Never>?

  /// Presence has to be re-stated or it expires; the server sweeps at 90s.
  private let heartbeatSeconds: UInt64 = 30

  init(api: any MaxService) {
    self.api = api
  }

  /// Local epoch milliseconds, corrected to the server's clock.
  var nowMs: Int {
    Int(Date().timeIntervalSince1970 * 1000) + clockDeltaMs
  }

  func channel(id: String) -> ChannelDoc? {
    channels.first { $0.id == id }
  }

  func position(of id: String) -> ChannelPosition? {
    channel(id: id)?.position(atMs: nowMs)
  }

  /// A ref for one item of a channel's programme, if this device holds it.
  func ref(channelID: String, mediaID: String?) -> ChannelMediaRef? {
    guard let mediaID else { return nil }
    return refs[channelID]?[mediaID]
  }

  /// True when tuned in but off air — playing our own cursor.
  func isOffAir(channelID: String, userID: String?) -> Bool {
    guard let userID, let doc = channel(id: channelID) else { return false }
    return doc.listeners.contains { $0.userId == userID && !$0.live }
  }

  // MARK: - Loading

  func refresh() async {
    isLoading = true
    failure = nil
    do {
      let items = try await api.channels()
      channels = items
      loaded = true
      for doc in items { keep(refs: doc.media, for: doc.id) }
      if let first = items.first { clockDeltaMs = first.serverTimeMs - Int(Date().timeIntervalSince1970 * 1000) }
    } catch {
      failure = error.localizedDescription
    }
    isLoading = false
  }

  // MARK: - Tuning

  /// Tune in and start the heartbeat.
  ///
  /// Tuning in IS the heartbeat — the same call, repeated. A separate heartbeat
  /// would be a second way to be present, and two ways to be present is how a
  /// listener list starts lying.
  @discardableResult
  func tune(id: String) async -> ChannelDoc? {
    do {
      let doc = try await api.tuneChannel(id: id)
      absorb(doc)
      tunedID = id
      startHeartbeat(for: id)
      return doc
    } catch {
      failure = error.localizedDescription
      return nil
    }
  }

  func leave() async {
    heartbeat?.cancel()
    heartbeat = nil
    guard let id = tunedID else { return }
    tunedID = nil
    // Leaving is a courtesy to the other person's listener list; the server's
    // sweep says the same thing 90 seconds later.
    try? await api.leaveChannel(id: id)
    await refresh()
  }

  /// The skip, and the way back from it.
  ///
  /// Skipping is yours alone — it does not move the channel — so it necessarily
  /// forks you off the shared timeline. Rather than pretend otherwise, that
  /// fork is a named state, and this is how you enter and leave it.
  func setLive(_ live: Bool) async {
    guard let id = tunedID else { return }
    do {
      absorb(try await api.setChannelLive(id: id, live: live))
    } catch {
      failure = error.localizedDescription
    }
  }

  private func startHeartbeat(for id: String) {
    heartbeat?.cancel()
    // Hoisted: a capture list cannot name an instance property directly, and
    // the Task below inherits this store's MainActor isolation, so everything
    // inside it reads `self` without hopping.
    let seconds = heartbeatSeconds
    heartbeat = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        guard !Task.isCancelled, let self, self.tunedID == id else { return }
        // A missed beat is not worth surfacing; the next one carries it.
        if let doc = try? await self.api.tuneChannel(id: id) {
          self.absorb(doc)
        }
      }
    }
  }

  // MARK: - Editing

  func create(_ input: ChannelInput) async -> ChannelDoc? {
    do {
      let doc = try await api.createChannel(input)
      absorb(doc)
      return doc
    } catch {
      failure = message(for: error)
      return nil
    }
  }

  func update(id: String, input: ChannelInput) async -> ChannelDoc? {
    do {
      let doc = try await api.updateChannel(id: id, input: input)
      absorb(doc)
      return doc
    } catch {
      failure = message(for: error)
      return nil
    }
  }

  func delete(id: String) async -> Bool {
    do {
      try await api.deleteChannel(id: id)
      channels.removeAll { $0.id == id }
      refs[id] = nil
      if tunedID == id {
        heartbeat?.cancel()
        heartbeat = nil
        tunedID = nil
      }
      return true
    } catch {
      failure = message(for: error)
      return false
    }
  }

  /// The builder's live count. Runs the same evaluation that freezes a
  /// programme, so it cannot promise a channel the server will not produce.
  func preview(_ input: ChannelInput) async -> ChannelPreview? {
    try? await api.previewChannel(input)
  }

  // MARK: - Refs

  /// Fetch any of `mediaIDs` this device does not hold yet.
  func ensureRefs(channelID: String, mediaIDs: [String]) async {
    let held = refs[channelID] ?? [:]
    var missing: [String] = []
    for id in mediaIDs where held[id] == nil && !missing.contains(id) {
      missing.append(id)
    }
    guard !missing.isEmpty else { return }
    // The caller renders what it has; the next attempt carries the rest.
    if let fetched = try? await api.resolveChannelMedia(id: channelID, ids: Array(missing.prefix(32))) {
      keep(refs: fetched, for: channelID)
    }
  }

  private func keep(refs newRefs: [ChannelMediaRef], for channelID: String) {
    guard !newRefs.isEmpty else { return }
    var merged = refs[channelID] ?? [:]
    for ref in newRefs { merged[ref.id] = ref }
    refs[channelID] = merged
  }

  private func absorb(_ doc: ChannelDoc) {
    if let index = channels.firstIndex(where: { $0.id == doc.id }) {
      channels[index] = doc
    } else {
      channels.append(doc)
    }
    keep(refs: doc.media, for: doc.id)
    clockDeltaMs = doc.serverTimeMs - Int(Date().timeIntervalSince1970 * 1000)
  }

  /// A refused rule says WHICH contradiction it is; that sentence is the whole
  /// point of refusing it, so it must reach the builder rather than a generic
  /// "something went wrong".
  ///
  /// `MaxAPIError.server` already carries the server's own message through
  /// `errorDescription`, so this is simply that — named, so the reason it
  /// matters is not lost the next time somebody tidies it away.
  private func message(for error: Error) -> String {
    error.localizedDescription
  }
}
