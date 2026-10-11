@preconcurrency import AVFoundation
import Combine
import Photos
import PhotosUI
import SwiftUI

struct MemoryThumbnailView: View {
  let store: MemoriesStore
  let candidate: MemoryCandidate
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          // Preserve the whole frame; memories should never crop the subject.
          .scaledToFit()
          .transition(.opacity)
      } else {
        Rectangle()
          .fill(MaxColor.surfaceStrong)
          .overlay {
            ProgressView()
              .tint(MaxColor.accent)
              .accessibilityLabel(Text("memories.loading.thumbnail"))
          }
      }
    }
    .task(id: candidate.id) {
      image = nil
      let thumbnail = await store.thumbnail(localIdentifier: candidate.localIdentifier)
      guard !Task.isCancelled else { return }
      // The `.transition(.opacity)` above only fires inside a transaction.
      withAnimation(
        MaxMotion.animation(
          .easeOut(duration: 0.2),
          enabled: motionEnabled && !store.calmMotionEnabled
        )
      ) {
        image = thumbnail
      }
    }
    .overlay(alignment: .topTrailing) {
      if candidate.kind == .video {
        Image(systemName: "play.fill")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(Color.black.opacity(0.45), in: Circle())
          .padding(MaxSpace.xs)
          .accessibilityLabel(Text("media.kind.video"))
      } else if candidate.kind == .livePhoto {
        Image(systemName: "livephoto")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(Color.black.opacity(0.45), in: Circle())
          .padding(MaxSpace.xs)
          .accessibilityLabel(Text("memories.media.live_photo"))
      }
    }
    .clipped()
  }
}

struct MemoryStageView: View {
  let store: MemoriesStore
  let candidate: MemoryCandidate
  let isActive: Bool

  var body: some View {
    Group {
      switch candidate.kind {
      case .photo:
        DeviceMemoryPhotoView(
          store: store,
          localIdentifier: candidate.localIdentifier
        )
      case .livePhoto:
        DeviceMemoryLivePhotoView(
          store: store,
          localIdentifier: candidate.localIdentifier
        )
      case .video:
        DeviceMemoryVideoView(
          store: store,
          localIdentifier: candidate.localIdentifier,
          muted: store.muted,
          isActive: isActive
        )
      }
    }
    .background(Color.black)
  }
}

private struct DeviceMemoryPhotoView: View {
  let store: MemoriesStore
  let localIdentifier: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.displayScale) private var displayScale
  @State private var image: UIImage?
  @State private var didFail = false
  @State private var retryID = 0
  @State private var zoom: CGFloat = 1

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(zoom)
            .clipped()
            .transition(.opacity)
            .gesture(magnificationGesture)
            .onTapGesture(count: 2, perform: toggleZoom)
        } else if didFail {
          MemoryAssetUnavailableView(retry: retry)
        } else {
          ProgressView()
            .tint(.white)
            .accessibilityLabel(Text("memories.loading.original"))
        }
      }
      .task(id: "\(localIdentifier)-\(retryID)") {
        image = nil
        didFail = false
        let scale = displayScale
        let target = CGSize(
          width: min(proxy.size.width * scale, 2000),
          height: min(proxy.size.height * scale, 2400)
        )
        let loadedImage = await store.image(
          localIdentifier: localIdentifier,
          targetSize: target
        )
        guard !Task.isCancelled else { return }
        withAnimation(photoMotion(.easeOut(duration: 0.2))) {
          image = loadedImage
        }
        didFail = loadedImage == nil
      }
    }
  }

  private var magnificationGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        zoom = min(max(value.magnification, 1), 4)
      }
      .onEnded { _ in
        // Snapping back without a transaction made a sub-threshold pinch jump
        // while double-tap zoom sprang smoothly.
        if zoom < 1.08 {
          withAnimation(photoMotion(.spring(response: 0.28, dampingFraction: 0.84))) {
            zoom = 1
          }
        }
      }
  }

  private func toggleZoom() {
    withAnimation(photoMotion(.spring(response: 0.28, dampingFraction: 0.84))) {
      zoom = zoom > 1.2 ? 1 : 2
    }
  }

  private func photoMotion(_ animation: Animation) -> Animation? {
    MaxMotion.animation(
      animation,
      enabled: motionEnabled && !reduceMotion && !store.calmMotionEnabled
    )
  }

  private func retry() {
    retryID += 1
  }
}

private struct DeviceMemoryLivePhotoView: View {
  let store: MemoriesStore
  let localIdentifier: String
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var livePhoto: PHLivePhoto?
  @State private var didFail = false
  @State private var retryID = 0

  var body: some View {
    ZStack {
      Color.black
      if let livePhoto {
        LivePhotoView(livePhoto: livePhoto)
          .transition(.opacity)
      } else if didFail {
        MemoryAssetUnavailableView(retry: retry)
      } else {
        ProgressView()
          .tint(.white)
          .accessibilityLabel(Text("memories.loading.original"))
      }
    }
    .task(id: "\(localIdentifier)-\(retryID)") {
      livePhoto = nil
      didFail = false
      let loadedLivePhoto = await store.livePhoto(localIdentifier: localIdentifier)
      guard !Task.isCancelled else { return }
      withAnimation(
        MaxMotion.animation(
          .easeOut(duration: 0.2),
          enabled: motionEnabled && !store.calmMotionEnabled
        )
      ) {
        livePhoto = loadedLivePhoto
      }
      didFail = loadedLivePhoto == nil
    }
  }

  private func retry() {
    retryID += 1
  }
}

private struct DeviceMemoryVideoView: View {
  let store: MemoriesStore
  let localIdentifier: String
  let muted: Bool
  let isActive: Bool
  @Environment(\.scenePhase) private var scenePhase
  @State private var player: AVPlayer?
  @State private var loadState: MemoryVideoLoadState = .loading
  @State private var isPlaying = false
  @State private var retryID = 0

  var body: some View {
    ZStack {
      Color.black
      if loadState == .ready, let player {
        MaxInlinePlayerSurface(player: player)
          .contentShape(Rectangle())
          .onTapGesture(perform: togglePlayback)

        if !isPlaying, isActive {
          Image(systemName: "play.fill")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background(Color.black.opacity(0.46), in: Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      } else if loadState == .failed {
        memoryVideoFailure
      } else {
        ProgressView()
          .tint(.white)
          .accessibilityLabel(Text("memories.loading.original"))
      }
    }
    .task(id: "\(localIdentifier)-\(retryID)-\(isActive)") {
      guard isActive else {
        tearDown()
        loadState = .loading
        return
      }
      await loadPlayer()
    }
    .onDisappear(perform: tearDown)
    .onChange(of: isActive) { _, _ in updatePlayback() }
    .onChange(of: muted) { _, _ in updatePlayback() }
    .onChange(of: scenePhase) { _, _ in updatePlayback() }
    .onReceive(
      NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
    ) { notification in
      guard let failedItem = notification.object as? AVPlayerItem,
            failedItem === player?.currentItem else { return }
      failPlayback()
    }
  }

  private var memoryVideoFailure: some View {
    ContentUnavailableView {
      Label("player.failed.title", systemImage: "exclamationmark.triangle.fill")
    } description: {
      Text("player.failed.subtitle")
    } actions: {
      Button("common.retry") { retryID += 1 }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("memories.video.retry")
    }
    .foregroundStyle(.white)
    .padding(MaxSpace.lg)
    .accessibilityIdentifier("memories.video.error")
  }

  private func loadPlayer() async {
    tearDown()
    loadState = .loading
    guard let asset = await store.avAsset(localIdentifier: localIdentifier),
          !Task.isCancelled,
          isActive else {
      if !Task.isCancelled { loadState = .failed }
      return
    }

    do {
      guard try await asset.load(.isPlayable) else { throw MaxPlayerError.notPlayable }
      guard !Task.isCancelled, isActive else { return }
      let item = AVPlayerItem(asset: asset)
      let nextPlayer = AVPlayer(playerItem: item)
      nextPlayer.isMuted = muted
      player = nextPlayer
      loadState = .ready
      updatePlayback()
    } catch is CancellationError {
      return
    } catch {
      loadState = .failed
    }
  }

  private func updatePlayback() {
    guard let player else { return }
    player.isMuted = muted
    if loadState == .ready, isActive, scenePhase == .active {
      player.play()
      isPlaying = true
    } else {
      player.pause()
      isPlaying = false
    }
  }

  private func togglePlayback() {
    guard loadState == .ready, isActive else { return }
    if isPlaying {
      player?.pause()
      isPlaying = false
    } else {
      player?.play()
      isPlaying = true
    }
  }

  private func failPlayback() {
    player?.pause()
    player = nil
    isPlaying = false
    loadState = .failed
  }

  private func tearDown() {
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    isPlaying = false
  }
}

private struct MemoryAssetUnavailableView: View {
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("player.failed.title", systemImage: "photo.badge.exclamationmark")
    } description: {
      Text("player.failed.subtitle")
    } actions: {
      Button("common.retry", action: retry)
        .buttonStyle(.glassProminent)
    }
    .foregroundStyle(.white)
    .padding(MaxSpace.lg)
    .accessibilityIdentifier("memories.asset.error")
  }
}

private enum MemoryVideoLoadState: Equatable {
  case loading
  case ready
  case failed
}

struct LivePhotoView: UIViewRepresentable {
  let livePhoto: PHLivePhoto

  func makeUIView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView()
    view.contentMode = .scaleAspectFit
    view.clipsToBounds = true
    let gesture = UILongPressGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handlePress(_:))
    )
    view.addGestureRecognizer(gesture)
    context.coordinator.view = view
    return view
  }

  func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
    uiView.livePhoto = livePhoto
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  @MainActor
  final class Coordinator: NSObject {
    weak var view: PHLivePhotoView?

    @objc
    func handlePress(_ gesture: UILongPressGestureRecognizer) {
      guard let view else { return }
      switch gesture.state {
      case .began:
        view.startPlayback(with: .full)
      case .ended, .cancelled, .failed:
        view.stopPlayback()
      default:
        break
      }
    }
  }
}
