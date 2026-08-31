@preconcurrency import AVFoundation
import CoreImage
import Observation
import SwiftUI
import UIKit

// Watch Together — the player's room surface (docs/design/WATCH_TOGETHER_SPEC.md §11).
//
// WatchRoomStore owns the protocol (socket, clock offset, host duties); this
// file owns everything the eye sees inside the player while a room is live:
// the roster strip, the sync pill, flying reactions, the overlay chat, the
// event ticker, viewer transport gating, and the drift corrector that keeps
// the local AVPlayer glued to `computeTarget(now:)`. Corrections are LOCAL
// only — nothing here broadcasts drift (spec §1).

// MARK: - Chrome contract

/// Quality caps for the in-room quality menu. Local-only (spec §11): each
/// level maps straight onto `preferredPeakBitRate` / `preferredMaximumResolution`.
enum WatchQualityLevel: String, CaseIterable, Identifiable {
  case auto
  case p1080
  case p720
  case p480

  var id: String { rawValue }

  var labelText: String {
    switch self {
    case .auto: String(localized: "watch.quality.auto")
    case .p1080: "1080p"
    case .p720: "720p"
    case .p480: "480p"
    }
  }

  /// Zero means unconstrained — AVFoundation's "auto".
  var peakBitRate: Double {
    switch self {
    case .auto: 0
    case .p1080: 6_000_000
    case .p720: 3_000_000
    case .p480: 1_200_000
    }
  }

  var maxResolution: CGSize {
    switch self {
    case .auto: .zero
    case .p1080: CGSize(width: 1920, height: 1080)
    case .p720: CGSize(width: 1280, height: 720)
    case .p480: CGSize(width: 854, height: 480)
    }
  }
}

/// The chrome's read-only snapshot of the room. nil = solo playback, and every
/// existing chrome call site keeps compiling untouched (defaulted-last prop).
struct WatchChromeModel: Equatable {
  let canControl: Bool
  let isHost: Bool
  let reactionsEnabled: Bool
  let quality: WatchQualityLevel
}

/// Everything the chrome can ask the player to do on the room's behalf.
enum WatchAction {
  case blockedTransportTap
  case setQuality(WatchQualityLevel)
  case startBreak(Int)
  case screenshotMoment
  case openSettings
  case openInvite
  case openQueue
  case openVote
}

// MARK: - Per-open UI scratch state

/// The player's in-room scratch state. Lives as one `@State` object on
/// `MaxPlayerSingleView` (extensions cannot add stored properties), so the
/// drift corrector and the overlay share it without threading a dozen vars.
@MainActor
@Observable
final class WatchPlayerUIState {
  var quality: WatchQualityLevel = .auto
  var isChatExpanded = false
  var showsRosterSheet = false
  var showsAskControl = false
  var showsMinimizeConfirm = false
  var isCapturingMoment = false
  /// The last buffering value reported to the room — report only on change.
  var lastReportedBuffering = false
  /// When the current rate-nudge began (epoch ms); nil while no nudge runs.
  var nudgeStartedAtMs: Double?
  /// When |drift| first crossed 0.3 s (epoch ms) — feeds the pill's
  /// catching-up (3–10 s) → follow-host (>10 s) escalation.
  var outOfSyncSinceMs: Double?
  var tickerEvents: [WatchTickerEvent] = []
  /// Roster ids at the last diff, so joins/leaves become ticker lines.
  var rosterSnapshot: Set<String> = []
  /// Message count when the chat overlay was last open — the pill's badge.
  var lastSeenChatCount = 0
  /// Attached lazily on the first screenshot-moment capture.
  var videoOutput: AVPlayerItemVideoOutput?

  func clearNudge() {
    nudgeStartedAtMs = nil
  }

  /// Appends one ticker line, keeps the newest three, expires it after 4 s.
  func pushTicker(_ text: String) {
    guard !text.isEmpty else { return }
    let event = WatchTickerEvent(id: UUID(), text: text)
    tickerEvents.append(event)
    if tickerEvents.count > 3 {
      tickerEvents.removeFirst(tickerEvents.count - 3)
    }
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      self?.tickerEvents.removeAll { $0.id == event.id }
    }
  }
}

struct WatchTickerEvent: Identifiable, Hashable {
  let id: UUID
  let text: String
}

// MARK: - Player integration

extension MaxPlayerSingleView {
  var watchStore: WatchRoomStore { model.watchRoomStore }

  /// True while THIS surface is the live room screen: an active room, not demo
  /// mode, and the room's current media is the item on screen.
  var isInWatchRoom: Bool {
    guard !model.isDemoMode, watchStore.isInRoom else { return false }
    let roomMediaID = watchStore.state?.mediaId ?? watchStore.room?.mediaId
    return roomMediaID == item.id
  }

  var watchChromeModel: WatchChromeModel? {
    guard isInWatchRoom else { return nil }
    return WatchChromeModel(
      canControl: watchStore.canControl,
      isHost: watchStore.isHost,
      reactionsEnabled: watchStore.settings.reactionsEnabled,
      quality: watchUI.quality
    )
  }

  func handleWatchAction(_ action: WatchAction) {
    switch action {
    case .blockedTransportTap:
      watchUI.showsAskControl = true
    case .setQuality(let level):
      watchUI.quality = level
      player.currentItem?.preferredPeakBitRate = level.peakBitRate
      player.currentItem?.preferredMaximumResolution = level.maxResolution
    case .startBreak(let seconds):
      Task { await watchStore.startBreak(seconds: seconds) }
    case .screenshotMoment:
      captureWatchMoment()
    case .openSettings:
      activeSheet = .watchSettings
    case .openInvite:
      activeSheet = .watchInvite
    case .openQueue:
      activeSheet = .watchQueue
    case .openVote:
      activeSheet = .watchVote
    }
    showControls()
  }

  // MARK: Transport guards (spec §5 permission matrix)

  /// The room's play/pause. Pause applies locally for feel and signals; play
  /// is signal-only so the server-stamped `startAt` (3-2-1 countdown) starts
  /// everyone on the same beat — the sync loop does the local start.
  func watchTogglePlayback() {
    guard watchStore.canControl else {
      watchUI.showsAskControl = true
      return
    }
    if watchStore.state?.playing == true {
      let target = watchStore.computeTarget() ?? position
      watchStore.applyingRemote = true
      player.pause()
      watchStore.applyingRemote = false
      isPlaying = false
      Task { await watchStore.pause(atPosition: target) }
    } else {
      Task { await watchStore.play(atPosition: position) }
    }
    showControls()
  }

  func watchSkip(by seconds: Double) {
    guard watchStore.canControl else {
      watchUI.showsAskControl = true
      return
    }
    let base = watchStore.computeTarget() ?? position
    let target = min(max(base + seconds, 0), max(duration, 0))
    watchHardSeek(to: target)
    let playing = watchStore.state?.playing ?? isPlaying
    Task { await watchStore.seek(to: target, playing: playing) }
    showControls()
  }

  /// Scrub-END only, never during drag (§1.4). Viewers never reach here —
  /// their slider is disabled.
  func watchSeekEditing(_ editing: Bool) {
    isSeeking = editing
    if editing {
      hideControlsTask?.cancel()
    } else {
      watchHardSeek(to: position)
      let playing = watchStore.state?.playing ?? isPlaying
      Task { await watchStore.seek(to: position, playing: playing) }
      showControls()
    }
  }

  /// Room rate is a shared signal; the local speed preference stays untouched
  /// and `player.rate` stays owned by the sync loop.
  func watchSetSpeed(_ speed: Float) {
    guard watchStore.canControl else {
      watchUI.showsAskControl = true
      return
    }
    Task { await watchStore.setRate(Double(speed)) }
    showControls()
  }

  /// Minimize = leave the room (spec §11); the alert's confirm calls this.
  func confirmWatchMinimize() {
    Task {
      await watchStore.leave()
      // Out of the room now, so the normal hand-off path runs untouched.
      minimizeToMini()
    }
  }

  /// The follow-host pill button: one immediate hard sync.
  func watchFollowHost() {
    guard let target = watchStore.computeTarget() else { return }
    let playing = watchStore.state?.playing == true
    watchHardSeek(to: target + (playing ? 0.15 : 0))
    watchUI.outOfSyncSinceMs = nil
    watchUI.clearNudge()
  }

  // MARK: Drift corrector (spec §1 — local only, every 500 ms)

  /// Reconciles the local AVPlayer against `computeTarget(now:)`. Runs from
  /// `handleProgressTick` while playing and from the overlay's 500 ms loop
  /// while paused (a paused player emits no time-observer ticks). Idempotent,
  /// so a signal's own echo converges to a no-op instead of double-applying.
  func runWatchSync() {
    guard isInWatchRoom, isVideo, playbackState == .ready, !isSeeking else { return }
    guard let state = watchStore.state, let target = watchStore.computeTarget() else { return }
    let nowMs = Date().timeIntervalSince1970 * 1000
    reportWatchBuffering()

    let shouldPlay = state.playing && watchStore.startCountdownRemaining == nil

    if !shouldPlay {
      if player.timeControlStatus != .paused {
        watchStore.applyingRemote = true
        player.pause()
        watchStore.applyingRemote = false
      }
      if isPlaying { isPlaying = false }
      watchUI.clearNudge()
      watchUI.outOfSyncSinceMs = nil
      // Freeze on the shared frame — pause, break and countdown all land here.
      if abs(state.position - player.currentTime().seconds) > 0.5 {
        watchHardSeek(to: state.position)
      }
      return
    }

    if isFinished, target < max(duration - 0.5, 0) { isFinished = false }
    // The tail belongs to ended-handling; correcting into it fights the host's
    // advancement signal.
    if duration > 0, target >= duration - 0.3 { return }

    if playbackSpeed != Float(state.rate) { playbackSpeed = Float(state.rate) }

    if player.timeControlStatus == .paused {
      watchStore.applyingRemote = true
      player.playImmediately(atRate: Float(state.rate))
      watchStore.applyingRemote = false
    }
    if !isPlaying { isPlaying = true }

    let drift = target - player.currentTime().seconds
    if abs(drift) >= 0.3 {
      if watchUI.outOfSyncSinceMs == nil { watchUI.outOfSyncSinceMs = nowMs }
    } else {
      watchUI.outOfSyncSinceMs = nil
    }

    if abs(drift) > 2.0 {
      // One hard seek, landing slightly ahead so decode catches the moving target.
      watchHardSeek(to: target + 0.15)
      watchUI.clearNudge()
    } else if abs(drift) >= 0.3 {
      if watchUI.nudgeStartedAtMs == nil { watchUI.nudgeStartedAtMs = nowMs }
      if nowMs - (watchUI.nudgeStartedAtMs ?? nowMs) > 30_000 {
        // A nudge that never converges gives up and seeks (spec §1).
        watchHardSeek(to: target + 0.15)
        watchUI.clearNudge()
      } else {
        // Corrective nudge rides player.rate directly — never the speed prefs.
        player.rate = Float(state.rate * (drift > 0 ? 1.05 : 0.95))
      }
    } else if watchUI.nudgeStartedAtMs != nil, abs(drift) < 0.05 {
      // Restore the canonical rate once the nudge truly converges (< 0.05).
      player.rate = Float(state.rate)
      watchUI.clearNudge()
    }
  }

  /// A corrective seek with the echo-proofing flag up, so nothing local
  /// mistakes it for a user gesture.
  func watchHardSeek(to target: Double) {
    let clamped = min(max(target, 0), max(duration, 0))
    position = clamped
    watchStore.applyingRemote = true
    Task {
      await player.seek(
        to: CMTime(seconds: clamped, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
      watchStore.applyingRemote = false
    }
  }

  /// Reports this client's stall state to the wait-for-buffering arbiter,
  /// only on change and never while a correction is being applied.
  private func reportWatchBuffering() {
    guard !watchStore.applyingRemote else { return }
    let stalled = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    guard stalled != watchUI.lastReportedBuffering else { return }
    watchUI.lastReportedBuffering = stalled
    Task { await watchStore.setBuffering(stalled) }
  }

  // MARK: Screenshot moment

  /// Captures the frame on screen and sends it to the room's conversation as
  /// an ordinary image message with a "⏱ mm:ss" caption — the same upload +
  /// send path the chat's photo picker uses.
  func captureWatchMoment() {
    guard !watchUI.isCapturingMoment,
          let conversationID = watchStore.room?.conversationId,
          let playerItem = player.currentItem else { return }
    watchUI.isCapturingMoment = true

    let output: AVPlayerItemVideoOutput
    if let existing = watchUI.videoOutput, playerItem.outputs.contains(existing) {
      output = existing
    } else {
      output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ])
      playerItem.add(output)
      watchUI.videoOutput = output
    }

    let stamp = position
    Task {
      defer { watchUI.isCapturingMoment = false }
      // A freshly attached output has no rendered frame yet; poll briefly.
      var buffer: CVPixelBuffer?
      for _ in 0..<8 {
        buffer = output.copyPixelBuffer(
          forItemTime: playerItem.currentTime(),
          itemTimeForDisplay: nil
        )
        if buffer != nil { break }
        try? await Task.sleep(for: .milliseconds(120))
      }
      guard let buffer else { return }
      let ciImage = CIImage(cvPixelBuffer: buffer)
      guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent),
            let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else {
        return
      }
      let file = MobileUploadFile(
        data: data,
        fileName: "watch-moment.jpg",
        mimeType: "image/jpeg"
      )
      guard let fileIDs = await model.transferStore.upload(files: [file]) else { return }
      _ = await model.chatStore.sendMessage(
        to: conversationID,
        content: "⏱ \(stamp.watchClockString)",
        mediaFileIDs: fileIDs
      )
    }
  }

  // MARK: Overlay entry point

  /// Every in-room layer, mounted while the room is live (media match or not,
  /// so it survives a `media` signal and can open the next item itself).
  @ViewBuilder
  func watchRoomLayers(compactHeight: Bool, containerSize: CGSize) -> some View {
    WatchRoomOverlay(
      watchUI: watchUI,
      item: item,
      isActive: isActive,
      controlsVisible: controlsVisible,
      compactHeight: compactHeight,
      containerSize: containerSize,
      onSyncTick: { runWatchSync() },
      onConfirmMinimize: { confirmWatchMinimize() },
      onFollowHost: { watchFollowHost() }
    )
  }
}

// MARK: - The overlay

/// The room's visual layer stack over the player: roster strip (with the
/// chrome), sync pill, flying reactions, collapsed/expanded chat, event
/// ticker, host capsules, and the room's alerts and sheets. Also runs the
/// 500 ms sync loop so a paused player still corrects, and follows `media`
/// signals to the next item.
private struct WatchRoomOverlay: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Bindable var watchUI: WatchPlayerUIState
  let item: MaxMediaItem
  let isActive: Bool
  let controlsVisible: Bool
  let compactHeight: Bool
  let containerSize: CGSize
  let onSyncTick: () -> Void
  let onConfirmMinimize: () -> Void
  let onFollowHost: () -> Void

  private var store: WatchRoomStore { model.watchRoomStore }
  private var conversationID: String? { store.room?.conversationId }
  private var isLandscape: Bool { containerSize.width > containerSize.height }

  private var members: [String: ChatGroupMember] {
    guard let conversationID,
          let loaded = model.chatStore.membersByChat[conversationID]?.value else { return [:] }
    return Dictionary(uniqueKeysWithValues: loaded.map { ($0.userId, $0) })
  }

  private var chatMessages: [ChatMessage] {
    guard let conversationID else { return [] }
    return model.chatStore.messagesByChat[conversationID]?.value ?? []
  }

  private func displayName(for userID: String) -> String {
    members[userID]?.displayName ?? String(localized: "watch.roster.viewer")
  }

  var body: some View {
    ZStack {
      WatchFlyingReactionsLayer(reactions: store.reactions)

      VStack(spacing: MaxSpace.xs) {
        // Clear of the top control row (close/minimize sit at ~52 pt).
        Spacer().frame(height: compactHeight ? 56 : 72)

        if controlsVisible {
          WatchRosterStrip(
            participants: store.participants,
            hostID: store.hostID,
            bufferingUserIDs: store.bufferingUserIDs,
            members: members,
            myUserID: store.myUserID,
            localBehind: watchUI.outOfSyncSinceMs != nil,
            onTap: { watchUI.showsRosterSheet = true }
          )
          .accessibilitySortPriority(80)
        }

        WatchSyncPill(
          store: store,
          watchUI: watchUI,
          waitingForName: store.bufferingUserIDs.first.map { displayName(for: $0) },
          onFollowHost: onFollowHost,
          onSkipWait: {
            let position = store.state?.position ?? 0
            Task { await store.play(atPosition: position) }
          }
        )
        .accessibilitySortPriority(85)

        if store.isHost {
          WatchControlRequestCapsules(
            requests: store.controlRequests,
            nameFor: displayName(for:),
            onAllow: { userID in
              Task { await store.setParticipantRole(userID: userID, role: "controller") }
            },
            onDeny: { userID in store.dismissControlRequest(userID: userID) }
          )
        }

        if !watchUI.tickerEvents.isEmpty {
          WatchEventTicker(events: watchUI.tickerEvents)
        }

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity)

      chatLayer
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    .sheet(isPresented: $watchUI.showsRosterSheet) {
      WatchRosterSheet(
        store: store,
        members: members
      )
    }
    .alert("watch.control.request", isPresented: $watchUI.showsAskControl) {
      Button("watch.control.request") {
        Task { await store.requestControl() }
      }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("watch.control.ask_message")
    }
    .alert("watch.leave", isPresented: $watchUI.showsMinimizeConfirm) {
      Button("watch.leave", role: .destructive, action: onConfirmMinimize)
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("watch.minimize.confirm")
    }
    .task(id: store.room?.id) {
      if let conversationID {
        await model.chatStore.loadMembers(for: conversationID)
      }
      // The paused-player half of the 500 ms corrector: a paused AVPlayer
      // fires no time-observer ticks, so the play-resume decision runs here.
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        onSyncTick()
      }
    }
    .onChange(of: store.currentMediaItem?.id) { _, newID in
      // A `media` signal moved the room on; follow it into the new item.
      guard isActive, let newID, newID != item.id,
            let media = store.currentMediaItem else { return }
      model.openPlayer(for: media)
    }
    .onChange(of: store.participants.map(\.userId)) { _, fresh in
      let now = Set(fresh)
      let previous = watchUI.rosterSnapshot
      watchUI.rosterSnapshot = now
      guard !previous.isEmpty else { return }
      if !now.subtracting(previous).isEmpty {
        watchUI.pushTicker(String(localized: "watch.a11y.participant_joined"))
      }
      if !previous.subtracting(now).isEmpty {
        watchUI.pushTicker(String(localized: "watch.a11y.participant_left"))
      }
    }
    .onChange(of: store.hostID) { previous, _ in
      guard previous != nil else { return }
      watchUI.pushTicker(String(localized: "watch.a11y.host_changed"))
    }
    .onChange(of: store.settings) { _, _ in
      watchUI.pushTicker(String(localized: "watch.a11y.settings_changed"))
    }
    .onChange(of: store.lastNudgeFromUserID) { _, userID in
      guard let userID else { return }
      watchUI.pushTicker(
        String(
          format: String(localized: "watch.nudge.received"),
          displayName(for: userID)
        )
      )
    }
  }

  // MARK: Chat

  @ViewBuilder
  private var chatLayer: some View {
    if store.settings.chatEnabled, let conversationID {
      if watchUI.isChatExpanded {
        WatchChatPanel(
          conversationID: conversationID,
          isLandscape: isLandscape,
          containerSize: containerSize,
          reduceTransparency: reduceTransparency,
          reactionsEnabled: store.settings.reactionsEnabled,
          onSendReaction: sendReaction(_:),
          onCollapse: {
            watchUI.lastSeenChatCount = chatMessages.count
            watchUI.isChatExpanded = false
          }
        )
        .accessibilitySortPriority(70)
      } else {
        WatchChatPill(
          latestMessage: chatMessages.last,
          unreadCount: max(chatMessages.count - watchUI.lastSeenChatCount, 0),
          reactionsEnabled: store.settings.reactionsEnabled,
          compactHeight: compactHeight,
          onSendReaction: sendReaction(_:),
          onExpand: {
            watchUI.lastSeenChatCount = chatMessages.count
            watchUI.isChatExpanded = true
          }
        )
        .accessibilitySortPriority(70)
      }
    }
  }

  private func sendReaction(_ emoji: String) {
    let position = store.computeTarget() ?? 0
    Task { await store.sendReaction(emoji: emoji, position: position) }
  }
}

// MARK: - Roster strip

private struct WatchRosterStrip: View {
  @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 32
  let participants: [WatchParticipant]
  let hostID: String?
  let bufferingUserIDs: Set<String>
  let members: [String: ChatGroupMember]
  let myUserID: String?
  let localBehind: Bool
  let onTap: () -> Void

  private static let maxVisible = 5

  /// Host first, then server order.
  private var ordered: [WatchParticipant] {
    participants.sorted { a, b in
      if a.userId == hostID { return true }
      if b.userId == hostID { return false }
      return false
    }
  }

  var body: some View {
    Button(action: onTap) {
      MaxFloatingSurface(horizontalPadding: MaxSpace.sm, verticalPadding: MaxSpace.xs) {
        HStack(spacing: MaxSpace.xs) {
          ForEach(ordered.prefix(Self.maxVisible)) { participant in
            avatar(for: participant)
          }
          if ordered.count > Self.maxVisible {
            Text(verbatim: "+\(ordered.count - Self.maxVisible)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: avatarSize, height: avatarSize)
              .background(Color.white.opacity(0.18), in: Circle())
          }
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("watch.roster.title"))
    .accessibilityValue(Text(verbatim: "\(participants.count)"))
    .accessibilityIdentifier("ui_watch_roster")
  }

  private func avatar(for participant: WatchParticipant) -> some View {
    let member = members[participant.userId]
    let name = member?.displayName ?? participant.userId
    let isBuffering = bufferingUserIDs.contains(participant.userId)
    let isMe = participant.userId == myUserID
    return MaxAvatar(name: name, imageURL: member?.avatarUrl, size: avatarSize)
      .overlay(alignment: .topTrailing) {
        if participant.userId == hostID {
          Image(systemName: "crown.fill")
            .font(.system(size: avatarSize * 0.30, weight: .bold))
            .foregroundStyle(.yellow)
            .shadow(radius: 1)
            .offset(x: 2, y: -3)
            .accessibilityLabel(Text("watch.roster.host"))
        }
      }
      .overlay(alignment: .bottomTrailing) {
        // Orange = buffering (shared set); red = this device running behind.
        if isBuffering {
          statusDot(.orange, label: "watch.roster.buffering")
        } else if isMe, localBehind {
          statusDot(.red, label: "watch.roster.behind")
        }
      }
  }

  private func statusDot(_ color: Color, label: LocalizedStringKey) -> some View {
    Circle()
      .fill(color)
      .frame(width: avatarSize * 0.28, height: avatarSize * 0.28)
      .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
      .accessibilityLabel(Text(label))
  }
}

// MARK: - Roster sheet (participant management)

private struct WatchRosterSheet: View {
  @Environment(\.dismiss) private var dismiss
  let store: WatchRoomStore
  let members: [String: ChatGroupMember]

  /// Kick and host transfer are consequential enough to confirm; role changes
  /// are instantly reversible and stay one-tap.
  @State private var confirmKickUserID: String?
  @State private var confirmHostUserID: String?

  var body: some View {
    NavigationStack {
      List(store.participants) { participant in
        row(for: participant)
      }
      .navigationTitle(Text("watch.roster.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done") { dismiss() }
        }
      }
      .confirmationDialog(
        "watch.kick",
        isPresented: kickConfirmBinding,
        titleVisibility: .visible
      ) {
        Button("watch.kick", role: .destructive) {
          guard let userID = confirmKickUserID else { return }
          Task { await store.kick(userID: userID) }
        }
        Button("common.cancel", role: .cancel) {}
      }
      .confirmationDialog(
        "watch.transfer_host",
        isPresented: hostConfirmBinding,
        titleVisibility: .visible
      ) {
        Button("watch.transfer_host") {
          guard let userID = confirmHostUserID else { return }
          Task { await store.transferHost(to: userID) }
        }
        Button("common.cancel", role: .cancel) {}
      }
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_watch_roster_sheet")
  }

  private var kickConfirmBinding: Binding<Bool> {
    Binding(
      get: { confirmKickUserID != nil },
      set: { if !$0 { confirmKickUserID = nil } }
    )
  }

  private var hostConfirmBinding: Binding<Bool> {
    Binding(
      get: { confirmHostUserID != nil },
      set: { if !$0 { confirmHostUserID = nil } }
    )
  }

  private func row(for participant: WatchParticipant) -> some View {
    let member = members[participant.userId]
    let name = member?.displayName ?? participant.userId
    let isHostRow = participant.userId == store.hostID
    let isMe = participant.userId == store.myUserID
    return HStack(spacing: MaxSpace.sm) {
      MaxAvatar(name: name, imageURL: member?.avatarUrl, size: 38)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: name)
          .font(.subheadline.weight(.semibold))
        Text(roleLabel(for: participant, isHostRow: isHostRow))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if store.isHost, !isHostRow, !isMe {
        Menu {
          if participant.role == "controller" {
            Button {
              Task { await store.setParticipantRole(userID: participant.userId, role: "viewer") }
            } label: {
              Label("watch.make_viewer", systemImage: "eye")
            }
          } else {
            Button {
              Task { await store.setParticipantRole(userID: participant.userId, role: "controller") }
            } label: {
              Label("watch.make_controller", systemImage: "slider.horizontal.3")
            }
          }
          Button {
            confirmHostUserID = participant.userId
          } label: {
            Label("watch.transfer_host", systemImage: "crown")
          }
          Divider()
          Button(role: .destructive) {
            confirmKickUserID = participant.userId
          } label: {
            Label("watch.kick", systemImage: "person.fill.xmark")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .foregroundStyle(MaxColor.accent)
        }
        .accessibilityIdentifier("ui_watch_roster_manage")
      }
    }
  }

  private func roleLabel(for participant: WatchParticipant, isHostRow: Bool) -> LocalizedStringKey {
    if isHostRow { return "watch.roster.host" }
    return participant.role == "controller" ? "watch.roster.controller" : "watch.roster.viewer"
  }
}

// MARK: - Sync pill

/// The one glass capsule that says how in-step this device is. Every state is
/// pure state math (spec §11) — reconnecting, 3-2-1 start countdown, break
/// countdown, waiting-for-X (+ host Skip), follow-host after 10 s adrift,
/// catching-up while nudging, syncing before the first state — and hidden
/// entirely when in sync.
private struct WatchSyncPill: View {
  let store: WatchRoomStore
  let watchUI: WatchPlayerUIState
  let waitingForName: String?
  let onFollowHost: () -> Void
  let onSkipWait: () -> Void

  private enum Phase: Equatable {
    case hidden
    case reconnecting
    case startCountdown(Int)
    case breakCountdown(Double)
    case waiting
    case followHost
    case catchingUp
    case syncing
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
      content(for: phase())
    }
  }

  private func phase() -> Phase {
    if !store.isRealtimeConnected { return .reconnecting }
    if let remaining = store.startCountdownRemaining {
      return .startCountdown(max(Int(remaining.rounded(.up)), 1))
    }
    if let remaining = store.breakRemaining { return .breakCountdown(remaining) }
    if store.isWaitingForBuffering { return .waiting }
    guard store.state != nil else { return .syncing }
    if let sinceMs = watchUI.outOfSyncSinceMs {
      let adrift = Date().timeIntervalSince1970 * 1000 - sinceMs
      if adrift > 10_000 { return .followHost }
      if adrift > 500 { return .catchingUp }
    }
    return .hidden
  }

  @ViewBuilder
  private func content(for phase: Phase) -> some View {
    switch phase {
    case .hidden:
      EmptyView()

    case .reconnecting:
      HStack(spacing: MaxSpace.xs) {
        pill(
          text: Text("watch.sync.reconnecting"),
          systemImage: "wifi.exclamationmark"
        )
        // Manual rejoin: an immediate full-doc resync while the socket loop
        // backs off on its own schedule.
        Button("watch.rejoin") {
          Task { await store.resync() }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.glass)
        .accessibilityIdentifier("ui_watch_rejoin")
      }

    case .startCountdown(let seconds):
      pill(
        text: Text(
          verbatim: String(
            format: String(localized: "watch.sync.start_countdown"),
            "\(seconds)"
          )
        ),
        systemImage: "timer"
      )

    case .breakCountdown(let remaining):
      pill(
        text: Text(
          verbatim: String(
            format: String(localized: "watch.sync.break_countdown"),
            remaining.watchClockString
          )
        ),
        systemImage: "cup.and.saucer.fill"
      )

    case .waiting:
      HStack(spacing: MaxSpace.xs) {
        pill(
          text: Text(
            verbatim: String(
              format: String(localized: "watch.sync.waiting_for"),
              waitingForName ?? "…"
            )
          ),
          systemImage: "hourglass"
        )
        if store.isHost {
          Button("watch.sync.skip", action: onSkipWait)
            .font(.caption.weight(.semibold))
            .buttonStyle(.glass)
            .accessibilityIdentifier("ui_watch_skip_wait")
        }
      }

    case .followHost:
      Button("watch.sync.follow_host", systemImage: "person.wave.2.fill", action: onFollowHost)
        .font(.caption.weight(.semibold))
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("ui_watch_follow_host")

    case .catchingUp:
      pill(text: Text("watch.sync.catching_up"), systemImage: "arrow.triangle.2.circlepath")

    case .syncing:
      pill(text: Text("watch.sync.syncing"), systemImage: "arrow.triangle.2.circlepath")
    }
  }

  private func pill(text: Text, systemImage: String) -> some View {
    HStack(spacing: MaxSpace.xxs) {
      Image(systemName: systemImage)
        .font(.caption.weight(.semibold))
        .accessibilityHidden(true)
      text
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
    .glassEffect(.regular, in: .capsule)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("ui_watch_sync_pill")
  }
}

// MARK: - Host control-request capsules

/// The 15 s allow/deny capsule the host sees after a viewer's ask-to-control.
/// Deny is client-side only (spec §5); expiry is client-side too.
private struct WatchControlRequestCapsules: View {
  let requests: [WatchRoomStore.ControlRequest]
  let nameFor: (String) -> String
  let onAllow: (String) -> Void
  let onDeny: (String) -> Void

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let live = requests.filter { context.date.timeIntervalSince($0.receivedAt) < 15 }
      VStack(spacing: MaxSpace.xs) {
        ForEach(live) { request in
          HStack(spacing: MaxSpace.sm) {
            Text(
              verbatim: String(
                format: String(localized: "watch.control.request_capsule"),
                nameFor(request.userId)
              )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)

            Button("watch.control.allow") { onAllow(request.userId) }
              .font(.caption.weight(.semibold))
              .buttonStyle(.glassProminent)
              .accessibilityIdentifier("ui_watch_allow_control")

            Button("watch.control.deny") { onDeny(request.userId) }
              .font(.caption.weight(.semibold))
              .buttonStyle(.glass)
              .accessibilityIdentifier("ui_watch_deny_control")
          }
          .padding(.horizontal, MaxSpace.sm)
          .padding(.vertical, MaxSpace.xs)
          .glassEffect(.regular, in: .capsule)
        }
      }
      .accessibilityIdentifier("ui_watch_control_capsule")
    }
  }
}

// MARK: - Event ticker

/// A short client-side line per watch.* event (joins, host changes, settings,
/// nudges). VoiceOver already hears these through MaxAccessibilityAnnouncer,
/// so the ticker is visual-only.
private struct WatchEventTicker: View {
  let events: [WatchTickerEvent]

  var body: some View {
    VStack(spacing: 2) {
      ForEach(events) { event in
        Text(verbatim: event.text)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.white.opacity(0.9))
          .padding(.horizontal, MaxSpace.sm)
          .padding(.vertical, 3)
          .background(Color.black.opacity(0.45), in: Capsule())
          .transition(.opacity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .accessibilityIdentifier("ui_watch_ticker")
  }
}

// MARK: - Flying reactions

/// The untouchable reaction layer: pieces rise and fade near the trailing
/// edge, capped at 20 on screen, with rapid repeats of the same emoji
/// coalesced into one counted piece. Reduce Motion swaps the rise for a fade.
private struct WatchFlyingReactionsLayer: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let reactions: [WatchRoomStore.FlyingReaction]

  struct Piece: Identifiable {
    let id: UUID
    let emoji: String
    var count: Int
    let xFraction: CGFloat
    let spawnedAt: Date
  }

  @State private var pieces: [Piece] = []

  var body: some View {
    GeometryReader { geo in
      ForEach(pieces) { piece in
        WatchFlyingEmoji(piece: piece, containerHeight: geo.size.height, reduceMotion: reduceMotion)
          .position(
            x: geo.size.width * piece.xFraction,
            y: geo.size.height * 0.78
          )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    // Keyed on the newest id, not the count — the store trims its buffer to a
    // fixed size, so the count plateaus under a flood while ids keep moving.
    .onChange(of: reactions.last?.id) { _, _ in
      guard let latest = reactions.last else { return }
      append(latest)
    }
  }

  private func append(_ reaction: WatchRoomStore.FlyingReaction) {
    // Coalesce: the same emoji inside 0.8 s bumps a counter, not a new piece.
    if let index = pieces.lastIndex(where: {
      $0.emoji == reaction.emoji && Date().timeIntervalSince($0.spawnedAt) < 0.8
    }) {
      pieces[index].count += 1
      return
    }
    guard pieces.count < 20 else { return }
    let piece = Piece(
      id: UUID(),
      emoji: reaction.emoji,
      count: 1,
      xFraction: .random(in: 0.58...0.92),
      spawnedAt: Date()
    )
    pieces.append(piece)
    Task {
      try? await Task.sleep(for: .seconds(2.6))
      pieces.removeAll { $0.id == piece.id }
    }
  }
}

private struct WatchFlyingEmoji: View {
  let piece: WatchFlyingReactionsLayer.Piece
  let containerHeight: CGFloat
  let reduceMotion: Bool

  @State private var launched = false

  var body: some View {
    HStack(spacing: 2) {
      Text(verbatim: piece.emoji)
        .font(.system(size: 30))
      if piece.count > 1 {
        Text(verbatim: "×\(piece.count)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
          .contentTransition(.numericText())
      }
    }
    .offset(y: launched && !reduceMotion ? -containerHeight * 0.45 : 0)
    .opacity(launched ? 0 : 1)
    .onAppear {
      withAnimation(.easeOut(duration: reduceMotion ? 1.8 : 2.2)) {
        launched = true
      }
    }
  }
}

// MARK: - Chat pill

/// The collapsed chat handle. Sits bottom-leading, survives chrome auto-hide
/// (spec §11), carries the newest line and an unread count, and hosts the
/// quick-reaction strip.
private struct WatchChatPill: View {
  let latestMessage: ChatMessage?
  let unreadCount: Int
  let reactionsEnabled: Bool
  let compactHeight: Bool
  let onSendReaction: (String) -> Void
  let onExpand: () -> Void

  private static let quickReactions = ["❤️", "😂", "🔥", "👏", "😮"]

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      if reactionsEnabled {
        HStack(spacing: MaxSpace.xxs) {
          ForEach(Self.quickReactions, id: \.self) { emoji in
            Button {
              onSendReaction(emoji)
            } label: {
              Text(verbatim: emoji)
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("watch.reaction.send"))
            .accessibilityValue(Text(verbatim: emoji))
          }
        }
        .padding(.horizontal, MaxSpace.xs)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .capsule)
        .accessibilityIdentifier("ui_watch_reaction_bar")
      }

      Button(action: onExpand) {
        HStack(spacing: MaxSpace.xs) {
          Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.subheadline.weight(.semibold))
            .accessibilityHidden(true)
          Text(verbatim: latestMessage?.content ?? "")
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: 150, alignment: .leading)
          if unreadCount > 0 {
            Text(verbatim: "\(unreadCount)")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(MaxColor.accent, in: Capsule())
          }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, MaxSpace.xs)
        .glassEffect(.regular, in: .capsule)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("watch.chat.title"))
      .accessibilityValue(unreadCount > 0 ? Text(verbatim: "\(unreadCount)") : Text(verbatim: ""))
      .accessibilityIdentifier("ui_watch_chat_pill")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .padding(.leading, MaxSpace.md)
    // Clear of the chrome's utility row; lower once the chrome hides itself.
    .padding(.bottom, compactHeight ? 120 : 180)
  }
}

// MARK: - Chat panel

/// The expanded overlay chat: the room's conversation through the proven
/// ChatStore (REST history + realtime + idempotent send), rendered with the
/// extracted ChatKit bubbles and a glass composer. 40% height in portrait,
/// a 320 pt trailing column in landscape.
private struct WatchChatPanel: View {
  @Environment(MaxAppModel.self) private var model
  let conversationID: String
  let isLandscape: Bool
  let containerSize: CGSize
  let reduceTransparency: Bool
  let reactionsEnabled: Bool
  let onSendReaction: (String) -> Void
  let onCollapse: () -> Void

  @State private var audioPlayer = ChatKitAudioPlayer()

  private var store: ChatStore { model.chatStore }
  private var messages: [ChatMessage] { store.messagesByChat[conversationID]?.value ?? [] }
  private var myID: String? { model.sessionStore.user?.id }
  private var scrimOpacity: Double { reduceTransparency ? 0.8 : 0.55 }

  var body: some View {
    ZStack(alignment: isLandscape ? .trailing : .bottom) {
      // Tap the uncovered video to collapse — the scrim only darkens the panel.
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture(perform: onCollapse)
        .accessibilityHidden(true)

      panel
        .frame(height: isLandscape ? nil : containerSize.height * 0.4)
        .frame(
          maxWidth: isLandscape ? 320 : .infinity,
          maxHeight: isLandscape ? .infinity : nil
        )
    }
    .task(id: conversationID) {
      store.startRealtime(for: conversationID)
      if store.messagesByChat[conversationID]?.value == nil {
        await store.loadMessages(for: conversationID)
      }
      await store.markRead(conversationID)
    }
  }

  private var panel: some View {
    VStack(spacing: 0) {
      HStack(spacing: MaxSpace.sm) {
        Text("watch.chat.title")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
        Spacer(minLength: 0)
        Button("watch.chat.collapse", systemImage: "chevron.down", action: onCollapse)
          .labelStyle(.iconOnly)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(.white)
          .frame(minWidth: 36, minHeight: 36)
          .accessibilityIdentifier("ui_watch_chat_collapse")
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.top, MaxSpace.sm)

      messageList

      composer
    }
    .background(Color.black.opacity(scrimOpacity))
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: MaxRadius.large,
        bottomLeadingRadius: isLandscape ? MaxRadius.large : 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: isLandscape ? 0 : MaxRadius.large
      )
    )
    .accessibilityIdentifier("ui_watch_chat_panel")
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(messages) { message in
            ChatKitBubble(
              message: message,
              isMine: myID != nil && message.senderId == myID,
              showsSender: message.senderId != myID,
              audioPlayer: audioPlayer
            )
            .padding(.horizontal, MaxSpace.sm)
            .id(message.id)
          }
          Color.clear.frame(height: 1).id(Self.bottomAnchor)
        }
        .padding(.vertical, MaxSpace.xs)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: messages.count) {
        withAnimation(.easeOut(duration: 0.2)) {
          proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
      }
      .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
    }
  }

  private static let bottomAnchor = "watch.chat.bottom"

  private var composer: some View {
    HStack(alignment: .bottom, spacing: MaxSpace.xs) {
      if reactionsEnabled {
        Button {
          onSendReaction("❤️")
        } label: {
          Image(systemName: "heart.fill")
            .font(.system(size: 20))
            .foregroundStyle(MaxColor.accent)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("watch.reaction.send"))
        .accessibilityIdentifier("ui_watch_chat_react")
      }

      TextField("watch.chat.placeholder", text: draftBinding, axis: .vertical)
        .lineLimit(1...3)
        .foregroundStyle(.white)
        .padding(.horizontal, MaxSpace.md)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityIdentifier("ui_watch_chat_input")

      Button(action: send) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 28))
          .foregroundStyle(canSend ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
      }
      .disabled(!canSend)
      .accessibilityLabel(Text("watch.chat.title"))
      .accessibilityIdentifier("ui_watch_chat_send")
    }
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
  }

  private var draftBinding: Binding<String> {
    Binding(
      get: { store.draft(for: conversationID) },
      set: { store.setDraft($0, for: conversationID) }
    )
  }

  private var canSend: Bool {
    !store.draft(for: conversationID)
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !store.isSending(to: conversationID)
  }

  private func send() {
    let text = store.draft(for: conversationID)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    store.setDraft("", for: conversationID)
    Task { _ = await store.sendMessage(to: conversationID, content: text) }
  }
}

// MARK: - Shared formatting

extension Double {
  /// mm:ss (or h:mm:ss) for room countdowns and the screenshot-moment caption.
  var watchClockString: String {
    guard isFinite, self >= 0 else { return "0:00" }
    let totalSeconds = Int(rounded(.down))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
  }
}
