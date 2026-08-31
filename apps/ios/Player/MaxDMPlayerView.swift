import SwiftUI
import AVFoundation

@MainActor
struct MaxDMPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MaxAppModel.self) private var model

  let items: [MaxMediaItem]
  @State private var selectedIndex: Int
  @State private var verticalOffset: CGFloat = 0

  init(items: [MaxMediaItem], selectedIndex: Int) {
    self.items = items
    _selectedIndex = State(initialValue: selectedIndex)
  }

  var body: some View {
    ZStack {
      Color.black
        .opacity(max(0.2, 0.98 - Double(abs(verticalOffset) / 500.0)))
        .ignoresSafeArea()

      TabView(selection: $selectedIndex) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          MaxDMPlayerPage(item: item, isActive: selectedIndex == index)
            .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))

      // Top control overlay
      VStack {
        HStack {
          Button("common.close", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .accessibilityIdentifier("ui_chat_dm_close")

          Spacer()

          if let currentItem = items[safe: selectedIndex] {
            if currentItem.kind.lowercased() == "video" {
              Menu {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in
                  Button {
                    NotificationCenter.default.post(
                      name: .maxDMPlayerSpeedChanged,
                      object: nil,
                      userInfo: ["speed": speed, "itemId": currentItem.id]
                    )
                  } label: {
                    Text("\(speed.formatted())x")
                  }
                }
              } label: {
                Image(systemName: "gearshape.fill")
                  .font(.system(size: 20))
                  .foregroundStyle(.white)
                  .padding(10)
                  .background(Color.black.opacity(0.4), in: Circle())
              }
              .accessibilityIdentifier("ui_chat_dm_settings")
            }

            if let url = currentItem.mediaUrl {
              ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
              }
              .buttonStyle(.glass)
              .accessibilityIdentifier("ui_chat_dm_share")
            }
          }
        }
        .padding()
        Spacer()

        if items.count > 1 {
          Text("\(selectedIndex + 1) / \(items.count)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.48), in: Capsule())
            .padding(.bottom, 20)
            .accessibilityIdentifier("ui_chat_dm_page_indicator")
        }
      }
    }
    .offset(y: max(0, verticalOffset))
    .simultaneousGesture(
      DragGesture(minimumDistance: 18)
        .onChanged { value in
          if abs(value.translation.height) > abs(value.translation.width),
             value.translation.height > 0 {
            verticalOffset = value.translation.height
          }
        }
        .onEnded { value in
          if verticalOffset > 110 || value.predictedEndTranslation.height > 180 {
            dismiss()
          } else {
            withAnimation(.snappy) { verticalOffset = 0 }
          }
        }
    )
    .preferredColorScheme(.dark)
    .statusBarHidden()
    .accessibilityIdentifier("ui_chat_dm_viewer")
  }
}

@MainActor
private struct MaxDMPlayerPage: View {
  @Environment(MaxAppModel.self) private var model
  let item: MaxMediaItem
  let isActive: Bool

  @State private var scale: CGFloat = 1
  @State private var player = AVPlayer()
  @State private var pictureInPicture = MaxPictureInPictureController()
  @State private var isPlaying = false
  @State private var position = 0.0
  @State private var duration = 0.0
  @State private var timeObserver: Any?
  @State private var playbackError: String?
  @State private var playbackRate: Float = 1.0

  private var isVideo: Bool { item.kind.lowercased() == "video" }

  private var localURL: URL? {
    model.transferStore.localURL(for: item)
  }

  /// The URL AVFoundation is actually given: an offline copy when there is one,
  /// otherwise the remote URL mapped back onto the origin this device can reach.
  /// Skipping that rewrite is why chat videos tried to stream from the phone's
  /// own loopback interface.
  private var playbackURL: URL? {
    if let localURL { return localURL }
    guard let mediaUrl = item.mediaUrl else { return nil }
    return mediaUrl.resolved(against: MaxConfiguration.fromBundle().baseURL)
  }

  var body: some View {
    ZStack {
      if isVideo {
        videoBody
      } else {
        imageBody
      }
    }
    .onAppear {
      // Honour the default speed the user set in Settings; without this the
      // preference persisted a value nothing ever read.
      playbackRate = model.preferencesStore.playbackRate
      if isActive && isVideo {
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
      }
    }
    .onChange(of: isActive) { _, active in
      if isVideo {
        if active {
          player.playImmediately(atRate: playbackRate)
          isPlaying = true
        } else {
          player.pause()
          isPlaying = false
        }
      } else {
        withAnimation(.snappy) {
          scale = 1.0
        }
      }
    }
    .onDisappear {
      if isVideo {
        tearDown()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .maxDMPlayerSpeedChanged)) { notification in
      guard let userInfo = notification.userInfo,
            let targetId = userInfo["itemId"] as? String,
            targetId == item.id,
            let speed = userInfo["speed"] as? Double else { return }
      playbackRate = Float(speed)
      model.preferencesStore.playbackRate = playbackRate
      if isPlaying {
        player.rate = playbackRate
      }
    }
  }

  @ViewBuilder
  private var imageBody: some View {
    MaxAsyncImage(url: playbackURL ?? item.posterURL) { phase in
      if let image = phase.image {
        image
          .resizable()
          .scaledToFit()
          .scaleEffect(scale)
          .gesture(
            MagnifyGesture()
              .onChanged { scale = min(max($0.magnification, 0.5), 5) }
              .onEnded { if $0.magnification < 1.05 { withAnimation(.snappy) { scale = 1 } } }
          )
      } else if phase.error != nil {
        ContentUnavailableView("player.unavailable.title", systemImage: "photo.badge.exclamationmark")
          .foregroundStyle(.white)
      } else {
        ProgressView().tint(.white)
      }
    }
    .padding(.vertical, 52)
  }

  @ViewBuilder
  private var videoBody: some View {
    ZStack {
      MaxPlayerSurface(player: player, pictureInPicture: pictureInPicture)
        .ignoresSafeArea()
        .scaleEffect(scale)
        .simultaneousGesture(
          MagnifyGesture()
            .onChanged { scale = min(max($0.magnification, 0.5), 5) }
            .onEnded { value in
              if value.magnification < 1.05 {
                withAnimation(.snappy) { scale = 1 }
              }
            }
        )

      HStack(spacing: 0) {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture(count: 2) { seek(by: -10) }
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture(count: 2) { seek(by: 10) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack {
        Spacer()
        VStack(spacing: 10) {
          Slider(
            value: Binding(
              get: { position },
              set: {
                position = $0
                player.seek(to: CMTime(seconds: $0, preferredTimescale: 600))
              }
            ),
            in: 0...max(duration, 0.1)
          )
          .tint(.white)

          HStack(spacing: 18) {
            Button { stepFrame(-1) } label: { Image(systemName: "backward.frame.fill") }
            Button { seek(by: -10) } label: { Image(systemName: "gobackward.10") }
            Button { togglePlayback() } label: {
              Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
            }
            Button { seek(by: 10) } label: { Image(systemName: "goforward.10") }
            Button { stepFrame(1) } label: { Image(systemName: "forward.frame.fill") }
            Spacer(minLength: 0)
            
            Text("\(format(position)) / \(format(duration))")
              .font(.caption.monospacedDigit())
          }
          .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.bottom, 64)
      }

      if let playbackError {
        ContentUnavailableView {
          Label("player.unavailable.title", systemImage: "exclamationmark.triangle")
        } description: {
          Text(verbatim: playbackError)
        }
        .foregroundStyle(.white)
      }
    }
    .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
      guard player.currentItem != nil else { return }
      player.rate = pressing ? 2 : (isPlaying ? playbackRate : 0)
    }, perform: {})
    .task(id: item.id) { await prepare() }
  }

  private func prepare() async {
    guard let url = playbackURL else {
      playbackError = String(localized: "player.unavailable.title")
      return
    }
    do {
      // A local download is a file URL, not an HTTP response; sending it through
      // the API preflight fails before AVPlayer ever sees the valid offline file.
      if !model.isDemoMode, !url.isFileURL {
        try await model.apiClient.preflightMediaStream(url: url)
      }
      MaxPlaybackSession.activateForPlayback()
      playbackError = nil
      player.replaceCurrentItem(with: AVPlayerItem(url: url))
      timeObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
        queue: .main
      ) { time in
        Task { @MainActor in
          position = max(0, time.seconds.isFinite ? time.seconds : 0)
          let value = player.currentItem?.duration.seconds ?? 0
          duration = value.isFinite ? max(0, value) : 0
        }
      }
      if isActive {
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
      }
    } catch {
      playbackError = ProductError.from(error, area: .player).reason
    }
  }

  private func togglePlayback() {
    if isPlaying {
      player.pause()
    } else {
      player.playImmediately(atRate: playbackRate)
    }
    isPlaying.toggle()
  }

  private func seek(by seconds: Double) {
    let target = min(max(position + seconds, 0), max(duration, 0))
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
  }

  private func stepFrame(_ direction: Double) {
    player.pause()
    isPlaying = false
    seek(by: direction / 30)
  }

  private func format(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
  }

  private func tearDown() {
    player.pause()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    player.replaceCurrentItem(with: nil)
  }
}

extension Notification.Name {
  static let maxDMPlayerSpeedChanged = Notification.Name("maxDMPlayerSpeedChanged")
}

private extension RandomAccessCollection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
