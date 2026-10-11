@preconcurrency import AVFoundation
import SwiftUI

struct MaxPlayerView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let playerBinding = Binding<MaxMediaItem?>(
      get: { model.activePlayer },
      set: { model.activePlayer = $0 }
    )

    TabView(selection: playerBinding) {
      ForEach(model.currentPlayerQueue) { queueItem in
        MaxPlayerSingleView(
          item: queueItem,
          isActive: model.activePlayer?.id == queueItem.id,
          onClose: dismiss.callAsFunction
        )
        .tag(queueItem as MaxMediaItem?)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .background(Color.black.ignoresSafeArea())
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
  }
}

struct MaxPlayerSingleView: View {
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.scenePhase) var scenePhase
  @Environment(MaxAppModel.self) var model

  let item: MaxMediaItem
  let isActive: Bool
  let onClose: () -> Void

  @State var player = AVPlayer()
  @State var pictureInPicture = MaxPictureInPictureController()
  @State var playbackState: PlaybackState = .idle
  @State var position = 0.0
  @State var duration = 0.0
  @State var isPlaying = false
  @State var isSeeking = false
  @State var isFinished = false
  @State var controlsVisible = true
  @State var isFavorite: Bool
  @State var activeSheet: PlayerSheet?
  @State var actionError: ProductError?
  @State var timeObserver: Any?
  @State var hideControlsTask: Task<Void, Never>?
  @State var demoPlaybackTask: Task<Void, Never>?
  @State var lastPersistedPosition = 0.0
  @State var isSavingToPhotos = false
  @State var didSaveToPhotos = false
  @State var playbackSpeed: Float = 1.0
  /// A freshly signed replacement for `item.mediaUrl`, obtained after the
  /// original signature expired. Changing it changes `playerTaskID`, which is
  /// what restarts playback on the new URL.
  @State var refreshedMediaURL: URL?
  @State var didRefreshMediaURL = false
  /// Playback bounds while a saved clip plays: seek to start, stop (or loop) at end.
  @State var clipRange: PlayerClipRange?
  /// In-progress clip creation: the A/B points the user is setting.
  @State var clipDraft = PlayerClipDraft()
  /// Counts 0.5 s progress ticks so a re-watch heat sample fires every ~6 s.
  @State var heatTickCount = 0
  /// Flow Mode: the moment the next item auto-plays, or nil when not armed.
  @State var upNextAt: Date?
  @State var upNextTask: Task<Void, Never>?
  /// Watch Together: the room's per-open UI scratch (drift corrector state,
  /// overlay toggles). The room itself lives in `model.watchRoomStore`.
  @State var watchUI = WatchPlayerUIState()

  init(item: MaxMediaItem, isActive: Bool, onClose: @escaping () -> Void) {
    self.item = item
    self.isActive = isActive
    self.onClose = onClose
    _isFavorite = State(initialValue: item.isFavorite)
  }

  var isVideo: Bool { item.kind.lowercased() == "video" }

  var localPlaybackURL: URL? {
    model.transferStore.localURL(for: item)
  }

  var playbackURL: URL? {
    if let localPlaybackURL { return localPlaybackURL }
    guard !model.isDemoMode, model.networkMonitor.isOnline else { return nil }
    // Adaptive stream first: AVPlayer speaks HLS natively, starts in a beat at
    // the right quality for the connection, and the manifest URL carries its
    // own fresh token — no presign expiry to chase. The progressive original
    // remains the fallback (and the download path).
    if let hlsUrl = item.hlsUrl { return hlsUrl }
    guard let mediaUrl = refreshedMediaURL ?? item.mediaUrl else { return nil }
    if mediaUrl.scheme == nil || mediaUrl.host == nil {
      let baseURL = MaxConfiguration.fromBundle().baseURL
      return URL(string: mediaUrl.absoluteString, relativeTo: baseURL)?.absoluteURL
    }
    return mediaUrl
  }

  var playerTaskID: String {
    if model.isDemoMode { return "demo-\(item.id)" }
    return "live-\(item.id)-\(playbackURL?.absoluteString ?? "offline")"
  }

  var ratingSubjects: [RatingSubject] {
    Array(model.ratingStore.subjects(for: item.id).prefix(2))
  }

  var activeDownload: TransferRecord? {
    model.transferStore.activeRecords.last {
      $0.kind == .download && $0.sourceID == item.id
    }
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.ignoresSafeArea()
        mediaContent
        mediaTapTarget
        playbackStateOverlay

        if controlsVisible {
          MaxPlayerChrome(
            item: item,
            compactHeight: proxy.size.height < 500,
            isOfflineReady: localPlaybackURL != nil,
            isReady: playbackState == .ready,
            isPlaying: isPlaying,
            isFinished: isFinished,
            isFavorite: isFavorite,
            position: $position,
            duration: duration,
            ratingSubjects: ratingSubjects,
            isRatingLoading: model.ratingStore.loadingFileIDs.contains(item.id),
            activeDownload: activeDownload,
            shareURL: model.isDemoMode ? nil : (localPlaybackURL ?? item.mediaUrl),
            pictureInPictureSupported: isVideo
              && !model.isDemoMode
              && playbackURL != nil
              && pictureInPicture.isSupported,
            pictureInPictureActive: pictureInPicture.isActive,
            canOpenPrevious: model.canOpenPreviousPlayer,
            canOpenNext: model.canOpenNextPlayer,
            isSavingToPhotos: isSavingToPhotos,
            didSaveToPhotos: didSaveToPhotos,
            onClose: onClose,
            onOpenPrevious: { openAdjacent(offset: -1) },
            onOpenNext: { openAdjacent(offset: 1) },
            onSaveToPhotos: startPhotoExport,
            onTogglePlayback: togglePlayback,
            onSkip: { skip(by: $0) },
            onRestart: restartPlayback,
            onSeekEditing: handleSeekEditing,
            onFavorite: toggleFavorite,
            onDownload: startDownload,
            onOpenRatings: { activeSheet = .ratings },
            onSendToChat: { activeSheet = .sendToChat },
            onAddToCollection: { activeSheet = .collections },
            onTogglePictureInPicture: togglePictureInPicture,
            onInteraction: { showControls() },
            onDelete: deleteCurrent,
            currentSpeed: playbackSpeed,
            onSetSpeed: setPlaybackSpeed,
            markers: model.clipsStore.markers(for: item.id),
            clipRange: clipRange,
            clipDraft: clipDraft,
            onDropMarker: dropMarker,
            onStampClip: stampNextClipPoint,
            onStampClipPoint: { stampClipPoint($0) },
            onSaveClip: { saveClip(named: $0) },
            onCancelClip: cancelClipDraft,
            onToggleClipLoop: toggleClipLoop,
            onExitClip: exitClipRange,
            onSeekToMarker: { seekToMarker($0) },
            onDeleteMarker: { deleteMarker($0) },
            heatBins: model.clipsStore.heatmap(for: item.id),
            onMinimize: (isVideo && !model.isDemoMode) ? { minimizeToMini() } : nil,
            watch: watchChromeModel,
            onWatchAction: { handleWatchAction($0) },
            onStartWatch: model.watchPartiesEnabled && !model.watchRoomStore.isInRoom
              ? { activeSheet = .watchStart }
              : nil
          )
            .transition(.opacity)
        }

        // Mounted while the room is live (media match or not) so the overlay
        // survives a `media` signal and can follow it into the next item.
        if !model.isDemoMode, model.watchRoomStore.isInRoom {
          watchRoomLayers(
            compactHeight: proxy.size.height < 500,
            containerSize: proxy.size
          )
        }

        // Terminal room states (ended with stats / kicked): an opaque card the
        // person must dismiss — playback itself continues solo underneath.
        if !model.isDemoMode, isActive,
           model.watchRoomStore.endedEvent != nil || model.watchRoomStore.wasKicked {
          WatchTerminalCard(
            endedEvent: model.watchRoomStore.endedEvent,
            onDismiss: { model.watchRoomStore.acknowledgeTerminalState() },
            onClose: {
              model.watchRoomStore.acknowledgeTerminalState()
              onClose()
            }
          )
          .transition(.opacity)
        }

        if upNextAt != nil {
          upNextOverlay
        }

        if let actionError {
          actionErrorOverlay(actionError)
        }
      }
    }
    .preferredColorScheme(.dark)
    .statusBarHidden()
    .persistentSystemOverlays(.hidden)
    .task(id: playerTaskID) {
      guard isActive else { return }
      await preparePlayback()
    }
    .task(id: item.id) { await model.ratingStore.load(fileID: item.id) }
    .task(id: item.id) {
      // Clips & markers ride the player: fetched once per item, drawn on the
      // scrubber, edited from the clip bar.
      guard isVideo else { return }
      await model.clipsStore.load(mediaID: item.id)
    }
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .ratings:
        RatingSheetView(item: item)
      case .sendToChat:
        PlayerSendToChatSheet(item: item)
      case .collections:
        PlayerCollectionPickerSheet(item: item)
      case .watchStart:
        WatchInviteSheet(context: WatchStartContext(mediaItem: item))
      case .watchSettings:
        WatchSettingsSheet()
      case .watchInvite:
        WatchInviteSheet(context: WatchStartContext())
      case .watchQueue:
        WatchQueueSheet()
      case .watchVote:
        WatchVoteSheet()
      }
    }
    .onChange(of: isActive) { _, active in
      if active {
        Task { await preparePlayback() }
      } else {
        pausePlayback()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase != .active else { return }
      persistCurrentPosition()
      // Transient inactivity (app switcher, control centre) must not stop
      // playback; a real backgrounding must, unless Picture in Picture has
      // genuinely taken over. `isSupported` is true on every iPhone, so testing
      // it meant the player never paused and playback died silently instead.
      guard phase == .background else { return }
      // A watch room keeps audio + sync in the background (spec §11), exactly
      // like Picture in Picture does.
      if isInWatchRoom { return }
      if model.isDemoMode || !pictureInPicture.isActive {
        pausePlayback()
      }
    }
    .onDisappear(perform: tearDown)
    .accessibilityIdentifier("ui_player_screen")
  }

  // MARK: - Media

  @ViewBuilder
  private var mediaContent: some View {
    if model.isDemoMode {
      DemoPlayerSurface(item: item, position: position, isPlaying: isPlaying)
    } else if isVideo, playbackURL != nil {
      MaxPlayerSurface(player: player, pictureInPicture: pictureInPicture)
        .ignoresSafeArea()
        .accessibilityLabel(Text(verbatim: item.title))
    } else if let playbackURL {
      MaxAsyncImage(url: playbackURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
            .accessibilityLabel(Text(verbatim: item.title))
        case .failure(let error):
          PlayerFailureCard(
            error: ProductError.from(error, area: .player),
            retry: nil,
            dismiss: nil
          )
        case .empty:
          ProgressView("loading.media")
            .tint(.white)
            .foregroundStyle(.white)
        @unknown default:
          PlayerFailureCard(
            error: ProductError.from(MaxPlayerError.notPlayable, area: .player),
            retry: nil,
            dismiss: nil
          )
        }
      }
      .padding(.vertical, MaxSpace.xl)
    } else {
      ContentUnavailableView {
        Label("player.unavailable.title", systemImage: "wifi.slash")
      } description: {
        Text(LocalizedStringKey(
          localPlaybackURL == nil && !model.networkMonitor.isOnline
            ? "player.offline_unavailable"
            : "player.unavailable.subtitle"
        ))
      }
      .foregroundStyle(.white)
      .padding(MaxSpace.lg)
      .accessibilityIdentifier("ui_player_unavailable")
    }
  }

  private var mediaTapTarget: some View {
    Color.clear
      .contentShape(Rectangle())
      .onTapGesture(perform: toggleControls)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var playbackStateOverlay: some View {
    switch playbackState {
    case .loading:
      ProgressView("loading.video")
        .tint(.white)
        .foregroundStyle(.white)
        .padding(MaxSpace.md)
        .glassEffect(.regular, in: .capsule)
        .allowsHitTesting(false)
        .accessibilityIdentifier("ui_player_loading")
    case .failed(let error):
      PlayerFailureCard(
        error: error,
        retry: retryPlayback,
        dismiss: dismissPlaybackError
      )
    case .idle, .ready:
      EmptyView()
    }
  }

  // MARK: - Flow Mode

  /// The queue item that would play next, when it is already loaded. Flow Mode
  /// can still advance past the end of a page — `openAdjacentPlayer` fetches
  /// more — the card then simply shows no title.
  private var nextQueueItem: MaxMediaItem? {
    let queue = model.currentPlayerQueue
    guard let index = queue.firstIndex(where: { $0.id == item.id }),
          index + 1 < queue.count else { return nil }
    return queue[index + 1]
  }

  /// Flow Mode's hand-off card: "Up next in Ns", cancellable, skippable.
  private var upNextOverlay: some View {
    VStack(spacing: MaxSpace.sm) {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = max(0, Int(((upNextAt ?? context.date).timeIntervalSince(context.date)).rounded(.up)))
        Text(verbatim: "Up next in \(remaining)s")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.8))
      }
      if let next = nextQueueItem {
        Text(verbatim: next.displayTitle)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      HStack(spacing: MaxSpace.sm) {
        Button("common.cancel") { cancelUpNext() }
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_player_upnext_cancel")
        Button("Play Now", systemImage: "play.fill") { playUpNextNow() }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("ui_player_upnext_now")
      }
    }
    .padding(MaxSpace.md)
    .frame(maxWidth: 340)
    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: MaxRadius.large))
    .transition(.opacity)
    .accessibilityIdentifier("ui_player_upnext")
  }

  // MARK: - Errors

  private func actionErrorOverlay(_ error: ProductError) -> some View {
    VStack(spacing: MaxSpace.md) {
      PlayerActionErrorView(error: error)
      Button("common.dismiss") {
        actionError = nil
        showControls()
      }
      .buttonStyle(.glassProminent)
      .accessibilityIdentifier("ui_player_error_dismiss")
    }
    .padding(MaxSpace.md)
    .frame(maxWidth: 360)
    .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: MaxRadius.large))
    .accessibilityIdentifier("ui_player_action_error")
  }
}

private struct PlayerFailureCard: View {
  let error: ProductError
  let retry: (() -> Void)?
  let dismiss: (() -> Void)?

  var body: some View {
    VStack(spacing: MaxSpace.md) {
      PlayerActionErrorView(error: error)
      if let retry {
        Button("common.retry", action: retry)
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("ui_player_retry")
      }
      if let dismiss {
        Button("common.dismiss", action: dismiss)
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_player_failure_dismiss")
      }
    }
    .padding(MaxSpace.md)
    .frame(maxWidth: 360)
    .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: MaxRadius.large))
    .accessibilityIdentifier("ui_player_failure")
  }
}

enum PlaybackState: Equatable {
  case idle
  case loading
  case ready
  case failed(ProductError)
}

/// Playback bounds for a saved clip: seek to start, stop (or loop) at end.
struct PlayerClipRange: Equatable {
  let clipID: String
  let title: String
  let start: Double
  let end: Double
  var loop = false
}

/// In-progress clip creation: the A/B points the user is setting.
/// Either order works; save normalises.
struct PlayerClipDraft: Equatable {
  var a: Double?
  var b: Double?

  var isActive: Bool { a != nil || b != nil }
}

enum PlayerClipPoint {
  case a
  case b
}

enum PlayerSheet: String, Identifiable {
  case ratings
  case sendToChat
  case collections
  case watchStart
  case watchSettings
  case watchInvite
  case watchQueue
  case watchVote

  var id: String { rawValue }
}

enum MaxPlayerError: LocalizedError {
  case notPlayable

  var errorDescription: String? {
    String(localized: "player.error.not_playable")
  }
}
