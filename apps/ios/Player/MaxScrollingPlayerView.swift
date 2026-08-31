@preconcurrency import AVFoundation
import SwiftUI

/// A vertically paged, TikTok-style playback surface.
///
/// The view owns no navigation state. A feature can present it with any ordered
/// media collection and keep the existing `MaxPlayerView` as the primary player.

@MainActor
struct MaxScrollingPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MaxAppModel.self) private var model

  let items: [MaxMediaItem]
  let initialItemID: String?
  let onClose: (() -> Void)?
  /// Watch Together: the presenting catalog's shuffle context. Non-nil shows
  /// the feed's "watch together" entry, which starts a room in shuffle mode
  /// with exactly this kind/search/sort (spec §11).
  let watchSource: WatchSource?

  @State private var selection: String?
  @State private var prefetcher = ScrollingPlayerPrefetcher()
  /// The item whose rating sheet is up, presented over the feed.
  @State private var ratingItem: MaxMediaItem?
  /// TikTok-style hold: true while a long-press keeps every overlay hidden.
  @State private var overlaysHidden = false
  /// The Watch Together start sheet's context, set by the feed entry button.
  @State private var watchStartContext: WatchStartContext?

  init(
    items: [MaxMediaItem],
    initialItemID: String? = nil,
    onClose: (() -> Void)? = nil,
    watchSource: WatchSource? = nil
  ) {
    let resolvedInitialID = initialItemID.flatMap { candidate in
      items.contains(where: { $0.id == candidate }) ? candidate : nil
    } ?? items.first?.id
    self.items = items
    self.initialItemID = resolvedInitialID
    self.onClose = onClose
    self.watchSource = watchSource
    _selection = State(initialValue: resolvedInitialID)
  }

  var body: some View {
    GeometryReader { viewport in
      ZStack(alignment: .topLeading) {
        Color.black.ignoresSafeArea()

        ScrollView(.vertical) {
          LazyVStack(spacing: 0) {
            ForEach(items) { item in
              MaxScrollingPlayerPage(
                item: item,
                isActive: selection == item.id,
                prefetcher: prefetcher,
                onRate: { ratingItem = $0 },
                onHoldChanged: { hidden in
                  withAnimation(.easeOut(duration: 0.15)) { overlaysHidden = hidden }
                }
              )
              .frame(width: viewport.size.width, height: viewport.size.height)
              .id(item.id)
            }
          }
          .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(false)
        .contentMargins(.zero, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $selection)
        .accessibilityIdentifier("ui_scrolling_player_pager")

        HStack(spacing: MaxSpace.sm) {
          Button("action.close", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .font(.system(size: 19, weight: .bold))
            .buttonStyle(.glass)
            .frame(width: 52, height: 52)
            .accessibilityIdentifier("ui_scrolling_player_close")

          if model.watchPartiesEnabled, let watchSource {
            Button("watch.start", systemImage: "play.tv") {
              watchStartContext = WatchStartContext(
                mediaItem: items.first { $0.id == selection },
                source: watchSource
              )
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 19, weight: .bold))
            .buttonStyle(.glass)
            .frame(width: 52, height: 52)
            .accessibilityIdentifier("ui_watch_start_feed")
          }
        }
        .safeAreaPadding(.top, MaxSpace.sm)
        .padding(.leading, MaxSpace.md)
        .opacity(overlaysHidden ? 0 : 1)
      }
    }
    .ignoresSafeArea()
    .background(Color.black)
    .preferredColorScheme(.dark)
    .statusBarHidden()
    .persistentSystemOverlays(.hidden)
    .sheet(item: $ratingItem) { item in
      RatingSheetView(item: item)
    }
    .sheet(item: $watchStartContext) { context in
      WatchInviteSheet(context: context)
    }
    .onAppear {
      guard selection == nil else { return }
      selection = initialItemID ?? items.first?.id
    }
    // A room started from the feed lives in the modal player; the feed's own
    // cover has to leave so the root can present it (one cover at a time).
    .onChange(of: model.watchRoomStore.isInRoom) { _, inRoom in
      guard inRoom, watchSource != nil else { return }
      close()
    }
    .task(id: selection) {
      await prefetchAroundSelection()
    }
    .accessibilityIdentifier("ui_scrolling_player")
  }

  private func close() {
    if let onClose {
      onClose()
    } else {
      dismiss()
    }
  }

  private func prefetchAroundSelection() async {
    guard let selection,
          let selectedIndex = items.firstIndex(where: { $0.id == selection }) else { return }

    // Honour the pre-cache settings instead of a hardcoded window. They used to
    // drive a separate downloader that nothing read; this is the prefetch the
    // player actually benefits from.
    guard model.preferencesStore.enableVideoPreCache else {
      await prefetcher.prefetch(urls: [])
      return
    }
    let lead = max(1, model.preferencesStore.videoPrefetchAdjacentCount)
    let lowerBound = max(items.startIndex, selectedIndex - 1)
    let upperBound = min(items.endIndex, selectedIndex + lead + 1)
    let urls = items[lowerBound..<upperBound].compactMap(resolvedPlaybackURL(for:))
    await prefetcher.prefetch(urls: urls)
  }

  private func resolvedPlaybackURL(for item: MaxMediaItem) -> URL? {
    if let localURL = model.transferStore.localURL(for: item) { return localURL }
    guard !model.isDemoMode, model.networkMonitor.isOnline,
          let mediaURL = item.mediaUrl else { return nil }
    // The backend can hand out a URL on its own internal origin. Only
    // `resolved(against:)` maps it back onto the origin this device can reach;
    // without it a physical device dials its own loopback interface.
    return mediaURL.resolved(against: MaxConfiguration.fromBundle().baseURL)
  }
}

@MainActor
private struct MaxScrollingPlayerPage: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(MaxAppModel.self) private var model

  let item: MaxMediaItem
  let isActive: Bool
  let prefetcher: ScrollingPlayerPrefetcher
  /// Opens the shared rating sheet for this page's item.
  let onRate: (MaxMediaItem) -> Void
  /// Reports the TikTok-style hold so the host hides its own chrome too.
  let onHoldChanged: (Bool) -> Void

  @State private var player = AVPlayer()
  @State private var playbackState: ScrollingPlaybackState = .loading
  @State private var isPlaying = false
  @State private var isMuted = false
  @State private var isFavorite: Bool
  @State private var position = 0.0
  @State private var duration = 0.0
  @State private var timeObserver: Any?
  @State private var retryID = 0
  @State private var isErrorDismissed = false
  /// True while a long-press keeps every overlay off the video.
  @State private var isHoldingClearView = false
  /// True while a finger drags the scrubber; the time observer stands back.
  @State private var isScrubbing = false
  /// A freshly signed replacement for `item.mediaUrl` after the original
  /// signature expired. It feeds `taskID`, which is what restarts this page.
  @State private var refreshedMediaURL: URL?
  @State private var didRefreshMediaURL = false

  init(
    item: MaxMediaItem,
    isActive: Bool,
    prefetcher: ScrollingPlayerPrefetcher,
    onRate: @escaping (MaxMediaItem) -> Void,
    onHoldChanged: @escaping (Bool) -> Void
  ) {
    self.item = item
    self.isActive = isActive
    self.prefetcher = prefetcher
    self.onRate = onRate
    self.onHoldChanged = onHoldChanged
    _isFavorite = State(initialValue: item.isFavorite)
  }

  private var isVideo: Bool { item.kind.lowercased() == "video" }

  private var localURL: URL? {
    model.transferStore.localURL(for: item)
  }

  private var playbackURL: URL? {
    if let localURL { return localURL }
    guard !model.isDemoMode, model.networkMonitor.isOnline else { return nil }
    guard let mediaUrl = refreshedMediaURL ?? item.mediaUrl else { return nil }
    // Same rewrite the modal player performs. Skipping it here is why Shuffle
    // pages tried to stream from the phone's own loopback interface.
    return mediaUrl.resolved(against: MaxConfiguration.fromBundle().baseURL)
  }

  private var taskID: String {
    "\(item.id)-\(playbackURL?.absoluteString ?? "offline")-\(retryID)"
  }

  var body: some View {
    ZStack {
      Color.black
      media
      playbackOverlay
        .opacity(isHoldingClearView ? 0 : 1)

      VStack {
        Spacer(minLength: 0)
        HStack(alignment: .bottom, spacing: MaxSpace.md) {
          mediaCaption
          Spacer(minLength: 0)
          actionRail
        }
        .padding(.horizontal, MaxSpace.md)
        .safeAreaPadding(.bottom, MaxSpace.lg)
      }
      .opacity(isHoldingClearView ? 0 : 1)
    }
    .clipped()
    .contentShape(Rectangle())
    .onTapGesture(perform: togglePlayback)
    // TikTok-style hold: past 350 ms every overlay leaves the video alone;
    // letting go restores it. `perform` fires once when the duration is met,
    // `onPressingChanged(false)` fires at release — the tap and double-tap
    // gestures above and inside are untouched.
    .onLongPressGesture(
      minimumDuration: 0.35,
      perform: { setClearView(true) },
      onPressingChanged: { pressing in
        if !pressing { setClearView(false) }
      }
    )
    .task(id: taskID) { await preparePlayback() }
    .onChange(of: isActive) { _, _ in updateActivePlayback() }
    .onChange(of: scenePhase) { _, _ in updateActivePlayback() }
    .onDisappear(perform: tearDown)
    .accessibilityIdentifier("ui_scrolling_player_item_\(item.id.maxAccessibilityToken)")
  }

  @ViewBuilder
  private var media: some View {
    if isVideo {
      if model.isDemoMode {
        DemoPlayerSurface(item: item, position: position, isPlaying: isPlaying)
      } else if playbackState == .ready {
        MaxInlinePlayerSurface(player: player, videoGravity: .resizeAspectFill)
          .ignoresSafeArea()
      } else if let posterURL = item.posterURL {
        MaxAsyncImage(url: posterURL) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Color.black
        }
        .blur(radius: playbackState == .loading ? 3 : 0)
      } else if let posterSource = playbackURL {
        // Videos uploaded before the server generated thumbnails have no poster
        // at all. Without this branch a loading or failed page was an unbroken
        // black rectangle with nothing to tell the two apart.
        MaxVideoPosterView(mediaID: item.id, url: posterSource) {
          scrollingPosterPlaceholder
        }
        .blur(radius: playbackState == .loading ? 3 : 0)
      } else {
        scrollingPosterPlaceholder
      }
    } else if let mediaURL = playbackURL ?? item.posterURL {
      MaxAsyncImage(url: mediaURL) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFit()
        case .failure:
          Color.black
        case .empty:
          ProgressView().tint(.white)
        @unknown default:
          Color.black
        }
      }
    }
  }

  private var scrollingPosterPlaceholder: some View {
    ZStack {
      Color.black
      Image(systemName: "film.stack.fill")
        .font(.largeTitle)
        .foregroundStyle(.white.opacity(0.35))
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var playbackOverlay: some View {
    switch playbackState {
    case .loading:
      if isVideo {
        ProgressView()
          .tint(.white)
          .padding(MaxSpace.md)
          .glassEffect(.regular, in: .circle)
          .allowsHitTesting(false)
      }
    case .ready:
      if isVideo, !isPlaying, isActive {
        Image(systemName: "play.fill")
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 78, height: 78)
          .background(Color.black.opacity(0.42), in: Circle())
          .allowsHitTesting(false)
      }
    case .failed where !isErrorDismissed:
      VStack(spacing: MaxSpace.sm) {
        if !model.networkMonitor.isOnline && localURL == nil {
          // Offline-specific message
          Label("player.offline.title", systemImage: "wifi.slash")
            .font(.headline)
          Text("player.offline.subtitle")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
        } else {
          Label("player.failed.title", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
          Text("player.failed.subtitle")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
          Button("common.retry") {
            // An explicit retry may re-sign again: the previous refresh can have
            // aged out while the failure card was on screen.
            didRefreshMediaURL = false
            retryID += 1
          }
          .buttonStyle(.glassProminent)
        }
        Button("common.dismiss") { isErrorDismissed = true }
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_scrolling_player_error_dismiss")
      }
      .foregroundStyle(.white)
      .padding(MaxSpace.lg)
      .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: MaxRadius.large))
      .padding(MaxSpace.lg)
      .accessibilityIdentifier("ui_scrolling_player_error")
    case .failed:
      EmptyView()
    }
  }

  private var mediaCaption: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      if let uploader = item.uploader.name, !uploader.isEmpty {
        Text(verbatim: uploader)
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
      }

      if isVideo, duration > 0 {
        scrubber
        Text(verbatim: "\(position.minuteString) / \(duration.minuteString)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.white.opacity(0.75))
      }
    }
    .shadow(color: .black.opacity(0.8), radius: 8, y: 2)
  }

  /// A thin, seekable progress bar — the feed's time control. It fattens under
  /// the finger; the drag wins over the page's tap gesture because it sits on
  /// a child view.
  private var scrubber: some View {
    GeometryReader { geo in
      let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.3))
        Capsule()
          .fill(Color.white)
          .frame(width: max(geo.size.width * fraction, 4))
      }
      .frame(height: isScrubbing ? 6 : 3)
      .frame(maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard playbackState == .ready, duration > 0 else { return }
            isScrubbing = true
            let target = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
            position = target * duration
          }
          .onEnded { value in
            guard playbackState == .ready, duration > 0 else { return }
            let target = min(max(value.location.x / max(geo.size.width, 1), 0), 1) * duration
            isScrubbing = false
            commitScrub(to: target)
          }
      )
    }
    .frame(maxWidth: 220)
    .frame(height: 24)
    .accessibilityLabel(Text("player.position"))
  }

  private var actionRail: some View {
    VStack(spacing: MaxSpace.md) {
      ScrollingPlayerButton(
        systemName: isPlaying ? "pause.fill" : "play.fill",
        label: isPlaying ? "action.pause" : "action.play",
        action: togglePlayback
      )

      ScrollingPlayerButton(
        systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
        label: "memories.audio",
        action: toggleMute
      )

      ScrollingPlayerButton(
        systemName: isFavorite ? "heart.fill" : "heart",
        label: isFavorite ? "action.unsave" : "action.favorite",
        isSelected: isFavorite,
        action: toggleFavorite
      )

      ScrollingPlayerButton(
        systemName: "star",
        label: "action.rate",
        action: { onRate(item) }
      )

      if let shareURL = localURL ?? item.mediaUrl {
        ShareLink(item: shareURL) {
          ScrollingPlayerButtonLabel(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("player.system_share"))
      }
    }
    .accessibilityIdentifier("ui_scrolling_player_actions")
  }

  private func preparePlayback() async {
    tearDownPlayerOnly()
    isErrorDismissed = false
    playbackState = .loading
    duration = max(item.duration ?? 0, 0)
    position = min(max(item.lastPosition, 0), max(duration - 1, 0))

    guard isVideo else {
      playbackState = .ready
      return
    }

    if model.isDemoMode {
      duration = max(duration, 30)
      playbackState = .ready
      updateActivePlayback()
      return
    }

    guard let playbackURL else {
      playbackState = .failed
      return
    }

    // Shuffle and chat used to inherit whatever category the last surface left
    // behind, so their audio was silenced by the ringer switch until the modal
    // player had been opened once.
    MaxPlaybackSession.activateForPlayback()

    do {
      // Build the asset immediately — network loading starts in the background.
      let asset = await prefetcher.asset(for: playbackURL)

      if localURL == nil {
        // Run auth-preflight and isPlayable check concurrently to cut startup
        // latency by ~50-70% compared to doing them serially.
        async let preflightTask: Void = model.apiClient.preflightMediaStream(url: playbackURL)
        async let playableTask: Bool = asset.load(.isPlayable)
        let (_, isPlayable) = try await (preflightTask, playableTask)
        guard isPlayable else { throw MaxPlayerError.notPlayable }
      } else {
        guard try await asset.load(.isPlayable) else { throw MaxPlayerError.notPlayable }
      }

      guard !Task.isCancelled else { return }

      let loadedDuration = try? await asset.load(.duration)
      if loadedDuration?.seconds.isFinite == true {
        duration = max(loadedDuration?.seconds ?? 0, 0)
      }
      position = min(max(item.lastPosition, 0), max(duration - 1, 0))
      let playerItem = AVPlayerItem(asset: asset)
      playerItem.preferredForwardBufferDuration = 12
      player.replaceCurrentItem(with: playerItem)
      player.automaticallyWaitsToMinimizeStalling = true
      player.isMuted = isMuted
      if position > 0 {
        await player.seek(
          to: CMTime(seconds: position, preferredTimescale: 600),
          toleranceBefore: .zero,
          toleranceAfter: .zero
        )
      }
      attachTimeObserver()
      playbackState = .ready
      updateActivePlayback()
    } catch is CancellationError {
      return
    } catch {
      // The signature on a presigned URL expires long before a shuffle session
      // does. Re-sign once and let `taskID` restart this page on the new URL
      // before showing the failure card.
      if !didRefreshMediaURL, localURL == nil,
         let refreshed = await refreshedRemoteURL(),
         refreshed != (refreshedMediaURL ?? item.mediaUrl) {
        didRefreshMediaURL = true
        refreshedMediaURL = refreshed
        return
      }
      playbackState = .failed
      isPlaying = false
    }
  }

  private func refreshedRemoteURL() async -> URL? {
    guard !model.isDemoMode, model.networkMonitor.isOnline else { return nil }
    guard let refreshed = await MaxMediaRefresh.refreshedItem(
      for: item,
      api: model.apiClient
    )?.mediaUrl, !refreshed.isFileURL else {
      return nil
    }
    return refreshed
  }

  private func updateActivePlayback() {
    guard playbackState == .ready, isVideo else { return }
    if isActive, scenePhase == .active {
      if model.isDemoMode {
        isPlaying = true
      } else {
        player.play()
        isPlaying = true
      }
    } else {
      player.pause()
      isPlaying = false
    }
  }

  private func togglePlayback() {
    guard playbackState == .ready, isVideo, isActive else { return }
    if isPlaying {
      player.pause()
      isPlaying = false
    } else {
      player.play()
      isPlaying = true
    }
  }

  private func toggleMute() {
    isMuted.toggle()
    player.isMuted = isMuted
  }

  /// Applies (and reports) the hold-to-hide state.
  private func setClearView(_ hidden: Bool) {
    guard isHoldingClearView != hidden else { return }
    withAnimation(.easeOut(duration: 0.15)) { isHoldingClearView = hidden }
    onHoldChanged(hidden)
  }

  /// Lands the scrubbed position on the player once the finger lifts.
  private func commitScrub(to target: Double) {
    position = min(max(target, 0), max(duration, 0))
    guard !model.isDemoMode else { return }
    Task {
      await player.seek(
        to: CMTime(seconds: position, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  private func toggleFavorite() {
    isFavorite.toggle()
    Task { await model.toggleFavorite(item) }
  }

  private func attachTimeObserver() {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { time in
      Task { @MainActor in
        // While a finger owns the scrubber the observer stands back, or every
        // half-second tick would yank the thumb out from under the drag.
        guard time.seconds.isFinite, !isScrubbing else { return }
        position = max(time.seconds, 0)
      }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }

  private func tearDownPlayerOnly() {
    removeTimeObserver()
    player.pause()
    player.replaceCurrentItem(with: nil)
    isPlaying = false
  }

  private func tearDown() {
    tearDownPlayerOnly()
    guard isVideo else { return }
    Task { await model.persistPlayback(for: item, position: position) }
  }
}

@MainActor
private final class ScrollingPlayerPrefetcher {
  private struct LoadedAsset: @unchecked Sendable {
    let value: AVURLAsset
  }

  private var assets: [URL: AVURLAsset] = [:]
  private var loads: [URL: Task<LoadedAsset?, Never>] = [:]

  func prefetch(urls: [URL]) async {
    let desiredURLs = Set(urls)
    let obsoleteURLs = loads.keys.filter { !desiredURLs.contains($0) }
    for url in obsoleteURLs {
      loads[url]?.cancel()
      loads.removeValue(forKey: url)
    }
    assets = assets.filter { desiredURLs.contains($0.key) }

    for url in desiredURLs where assets[url] == nil && loads[url] == nil {
      loads[url] = makeLoad(for: url)
    }
  }

  func asset(for url: URL) async -> AVURLAsset {
    if let asset = assets[url] { return asset }
    let task = loads[url] ?? makeLoad(for: url)
    loads[url] = task
    if let loaded = await task.value {
      assets[url] = loaded.value
      loads[url] = nil
      return loaded.value
    }
    loads[url] = nil
    return AVURLAsset(url: url)
  }

  private func makeLoad(for url: URL) -> Task<LoadedAsset?, Never> {
    Task {
      // Keep the presigned stream URL intact. Rewriting it to a custom scheme
      // makes the loader issue an unsigned HEAD request and is the source of
      // the Shuffle player's black pages.
      let asset = AVURLAsset(url: url)

      do {
        guard try await asset.load(.isPlayable), !Task.isCancelled else { return nil }
        return LoadedAsset(value: asset)
      } catch {
        return nil
      }
    }
  }
}

private enum ScrollingPlaybackState: Equatable {
  case loading
  case ready
  case failed
}

private struct ScrollingPlayerButton: View {
  let systemName: String
  let label: LocalizedStringKey
  var isSelected = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ScrollingPlayerButtonLabel(systemName: systemName, isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(label))
  }
}

private struct ScrollingPlayerButtonLabel: View {
  @Environment(\.maxThemePalette) private var palette

  let systemName: String
  var isSelected = false

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 28, weight: .bold))
      .foregroundStyle(isSelected ? palette.accent : Color.white)
      .frame(width: 64, height: 64)
      .background(Color.black.opacity(0.48), in: Circle())
      .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1.5))
      .contentShape(Circle())
      .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
  }
}
