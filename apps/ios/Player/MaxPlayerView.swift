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
            onSetSpeed: setPlaybackSpeed
          )
            .transition(.opacity)
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
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .ratings:
        RatingSheetView(item: item)
      case .sendToChat:
        PlayerSendToChatSheet(item: item)
      case .collections:
        PlayerCollectionPickerSheet(item: item)
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

enum PlayerSheet: String, Identifiable {
  case ratings
  case sendToChat
  case collections

  var id: String { rawValue }
}

enum MaxPlayerError: LocalizedError {
  case notPlayable

  var errorDescription: String? {
    String(localized: "player.error.not_playable")
  }
}
