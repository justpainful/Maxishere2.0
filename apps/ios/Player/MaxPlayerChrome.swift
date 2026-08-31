import Foundation
import SwiftUI
import UIKit

struct MaxPlayerChrome: View {
  let item: MaxMediaItem
  let compactHeight: Bool
  let isOfflineReady: Bool
  let isReady: Bool
  let isPlaying: Bool
  let isFinished: Bool
  let isFavorite: Bool
  @Binding var position: Double
  let duration: Double
  let ratingSubjects: [RatingSubject]
  let isRatingLoading: Bool
  let activeDownload: TransferRecord?
  let shareURL: URL?
  let pictureInPictureSupported: Bool
  let pictureInPictureActive: Bool
  let canOpenPrevious: Bool
  let canOpenNext: Bool
  let isSavingToPhotos: Bool
  let didSaveToPhotos: Bool

  let onClose: () -> Void
  let onOpenPrevious: () -> Void
  let onOpenNext: () -> Void
  let onSaveToPhotos: () -> Void
  let onTogglePlayback: () -> Void
  let onSkip: (Double) -> Void
  let onRestart: () -> Void
  let onSeekEditing: (Bool) -> Void
  let onFavorite: () -> Void
  let onDownload: () -> Void
  let onOpenRatings: () -> Void
  let onSendToChat: () -> Void
  let onAddToCollection: () -> Void
  let onTogglePictureInPicture: () -> Void
  let onInteraction: () -> Void
  let onDelete: () -> Void
  let currentSpeed: Float
  let onSetSpeed: (Float) -> Void

  // Clips & markers: scrubber annotations plus the clip bar's callbacks.
  let markers: [MediaMarker]
  let clipRange: PlayerClipRange?
  let clipDraft: PlayerClipDraft
  let onDropMarker: () -> Void
  let onStampClip: () -> Void
  let onStampClipPoint: (PlayerClipPoint) -> Void
  let onSaveClip: (String) -> Void
  let onCancelClip: () -> Void
  let onToggleClipLoop: () -> Void
  let onExitClip: () -> Void
  let onSeekToMarker: (MediaMarker) -> Void
  let onDeleteMarker: (MediaMarker) -> Void
  /// 100 normalised re-watch bins for the scrubber's heat lane. Defaulted LAST
  /// so existing memberwise-init call sites keep compiling unchanged.
  var heatBins: [Double] = []
  /// Hands playback to the floating mini card; nil hides the control.
  /// Defaulted for the same call-site reason as `heatBins`.
  var onMinimize: (() -> Void)? = nil
  /// Watch Together: the room snapshot plus its action sink. nil = solo
  /// playback; defaulted LAST for the same call-site reason as `heatBins`.
  var watch: WatchChromeModel? = nil
  var onWatchAction: ((WatchAction) -> Void)? = nil
  /// Solo playback's "watch.start" entry point; nil hides it (capability off,
  /// demo mode, or already in a room).
  var onStartWatch: (() -> Void)? = nil

  /// The trickplay sprite rides beside the HLS manifest with the same signed
  /// query: master.m3u8 → storyboard.jpg. nil when the item has no stream.
  private var trickplayStoryboardURL: URL? {
    guard let hlsUrl = item.hlsUrl else { return nil }
    let replaced = hlsUrl.absoluteString.replacingOccurrences(
      of: "master.m3u8",
      with: "storyboard.jpg"
    )
    guard replaced != hlsUrl.absoluteString else { return nil }
    return URL(string: replaced)
  }

  var body: some View {
    VStack(spacing: compactHeight ? MaxSpace.xs : MaxSpace.md) {
      PlayerTopControls(
        canOpenPrevious: canOpenPrevious,
        canOpenNext: canOpenNext,
        onMinimize: onMinimize,
        onClose: onClose,
        onOpenPrevious: onOpenPrevious,
        onOpenNext: onOpenNext
      )
      .accessibilitySortPriority(100)

      Spacer(minLength: compactHeight ? MaxSpace.xs : MaxSpace.md)

      if item.kind.lowercased() == "video" {
        PlayerTransportControls(
          compactHeight: compactHeight,
          isReady: isReady,
          isPlaying: isPlaying,
          isFinished: isFinished,
          position: position,
          onTogglePlayback: onTogglePlayback,
          onSkip: onSkip,
          watchLocked: watch.map { !$0.canControl } ?? false
        )
        .accessibilitySortPriority(95)
      }

      Spacer(minLength: compactHeight ? MaxSpace.xs : MaxSpace.md)

      VStack(spacing: compactHeight ? MaxSpace.xs : MaxSpace.sm) {
        if item.kind.lowercased() == "video", clipRange != nil || clipDraft.isActive {
          PlayerClipBar(
            clipRange: clipRange,
            clipDraft: clipDraft,
            position: position,
            onStampPoint: onStampClipPoint,
            onSave: onSaveClip,
            onCancel: onCancelClip,
            onToggleLoop: onToggleClipLoop,
            onExit: onExitClip
          )
        }

        if item.kind.lowercased() == "video" {
          PlayerTimelineControls(
            position: $position,
            duration: duration,
            isReady: isReady,
            markers: markers,
            clipRange: clipRange,
            clipDraft: clipDraft,
            onSeekEditing: onSeekEditing,
            onRestart: onRestart,
            onSeekToMarker: onSeekToMarker,
            onDeleteMarker: onDeleteMarker,
            heatBins: heatBins,
            storyboardURL: trickplayStoryboardURL,
            watchSyncDriven: watch.map { !$0.canControl } ?? false
          )
          .accessibilitySortPriority(90)
        }

        PlayerRatingControls(
          subjects: ratingSubjects,
          isLoading: isRatingLoading,
          action: onOpenRatings
        )

        PlayerUtilityControls(
          item: item,
          isFavorite: isFavorite,
          isOfflineReady: isOfflineReady,
          activeDownload: activeDownload,
          shareURL: shareURL,
          pictureInPictureSupported: pictureInPictureSupported,
          pictureInPictureActive: pictureInPictureActive,
          isSavingToPhotos: isSavingToPhotos,
          didSaveToPhotos: didSaveToPhotos,
          onFavorite: onFavorite,
          onDownload: onDownload,
          onSendToChat: onSendToChat,
          onAddToCollection: onAddToCollection,
          onSaveToPhotos: onSaveToPhotos,
          onTogglePictureInPicture: onTogglePictureInPicture,
          onInteraction: onInteraction,
          onDelete: onDelete,
          currentSpeed: currentSpeed,
          onSetSpeed: onSetSpeed,
          isClipDraftActive: clipDraft.isActive,
          onDropMarker: onDropMarker,
          onStampClip: onStampClip,
          watch: watch,
          onWatchAction: onWatchAction,
          onStartWatch: onStartWatch
        )
        .accessibilitySortPriority(60)
      }
    }
    .padding(.horizontal, compactHeight ? MaxSpace.sm : MaxSpace.md)
    .padding(.vertical, compactHeight ? MaxSpace.xs : MaxSpace.md)
  }
}

private struct PlayerTopControls: View {
  let canOpenPrevious: Bool
  let canOpenNext: Bool
  let onMinimize: (() -> Void)?
  let onClose: () -> Void
  let onOpenPrevious: () -> Void
  let onOpenNext: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Button("action.close", systemImage: "xmark", action: onClose)
        .labelStyle(.iconOnly)
        .font(.system(size: 19, weight: .bold))
        .buttonStyle(.glass)
        .frame(minWidth: 52, minHeight: 52)
        .accessibilityIdentifier("ui_player_close")

      if let onMinimize {
        Button("Minimize", systemImage: "arrow.down.right.and.arrow.up.left", action: onMinimize)
          .labelStyle(.iconOnly)
          .font(.system(size: 19, weight: .bold))
          .buttonStyle(.glass)
          .frame(minWidth: 52, minHeight: 52)
          .accessibilityIdentifier("ui_player_minimize")
      }

      Spacer(minLength: 0)

      Button("player.previous", systemImage: "chevron.backward", action: onOpenPrevious)
        .labelStyle(.iconOnly)
        .font(.system(size: 19, weight: .bold))
        .buttonStyle(.glass)
        .frame(minWidth: 52, minHeight: 52)
        .disabled(!canOpenPrevious)
        .accessibilityIdentifier("ui_player_previous")

      Button("player.next", systemImage: "chevron.forward", action: onOpenNext)
        .labelStyle(.iconOnly)
        .font(.system(size: 19, weight: .bold))
        .buttonStyle(.glass)
        .frame(minWidth: 52, minHeight: 52)
        .disabled(!canOpenNext)
        .accessibilityIdentifier("ui_player_next")
    }
  }
}

private struct PlayerTransportControls: View {
  let compactHeight: Bool
  let isReady: Bool
  let isPlaying: Bool
  let isFinished: Bool
  let position: Double
  let onTogglePlayback: () -> Void
  let onSkip: (Double) -> Void
  /// Watch Together viewer: the buttons stay tappable (the tap becomes the
  /// ask-to-control flow, handled player-side) but wear a lock glyph.
  var watchLocked = false

  private var playPauseLabel: LocalizedStringKey {
    if isFinished { return "player.restart" }
    if isPlaying { return "action.pause" }
    return position > 0 ? "player.resume" : "action.play"
  }

  private var playPauseSymbol: String {
    if isFinished { return "arrow.counterclockwise" }
    return isPlaying ? "pause.fill" : "play.fill"
  }

  var body: some View {
    GlassEffectContainer(spacing: MaxSpace.sm) {
      HStack(spacing: MaxSpace.sm) {
        Button("player.rewind", systemImage: "gobackward.15") { onSkip(-15) }
          .labelStyle(.iconOnly)
          .font(.system(size: compactHeight ? 24 : 30, weight: .semibold))
          .buttonStyle(.glass)
          .frame(minWidth: compactHeight ? 72 : 84, minHeight: compactHeight ? 72 : 84)
          .disabled(!isReady)
          .accessibilityIdentifier("ui_player_skip_back")

        Button(playPauseLabel, systemImage: playPauseSymbol, action: onTogglePlayback)
          .labelStyle(.iconOnly)
          .font(.system(size: compactHeight ? 32 : 44, weight: .semibold))
          .buttonStyle(.glassProminent)
          .frame(minWidth: compactHeight ? 88 : 108, minHeight: compactHeight ? 88 : 108)
          .disabled(!isReady)
          .overlay(alignment: .bottomTrailing) {
            if watchLocked {
              Image(systemName: "lock.fill")
                .font(.system(size: compactHeight ? 13 : 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(compactHeight ? 8 : 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .accessibilityIdentifier("ui_watch_play_locked")
            }
          }
          .accessibilityHint(watchLocked ? Text("watch.transport.locked") : Text(verbatim: ""))
          .accessibilityIdentifier("ui_player_play_pause")

        Button("player.forward", systemImage: "goforward.15") { onSkip(15) }
          .labelStyle(.iconOnly)
          .font(.system(size: compactHeight ? 24 : 30, weight: .semibold))
          .buttonStyle(.glass)
          .frame(minWidth: compactHeight ? 72 : 84, minHeight: compactHeight ? 72 : 84)
          .disabled(!isReady)
          .accessibilityIdentifier("ui_player_skip_forward")
      }
    }
  }
}

private struct PlayerTimelineControls: View {
  @Binding var position: Double
  let duration: Double
  let isReady: Bool
  let markers: [MediaMarker]
  let clipRange: PlayerClipRange?
  let clipDraft: PlayerClipDraft
  let onSeekEditing: (Bool) -> Void
  let onRestart: () -> Void
  let onSeekToMarker: (MediaMarker) -> Void
  let onDeleteMarker: (MediaMarker) -> Void
  var heatBins: [Double] = []
  /// The 10×10 trickplay sprite's address; nil when the item has no HLS stream.
  var storyboardURL: URL? = nil
  /// Watch Together viewer: the timeline is sync-driven, so the slider locks.
  var watchSyncDriven = false

  @State private var isScrubbing = false
  @State private var storyboard: UIImage?

  private var timelineBinding: Binding<Double> {
    Binding(
      get: { position },
      set: { position = min(max($0, 0), max(duration, 0)) }
    )
  }

  private var showsAnnotations: Bool {
    duration > 0 && (
      clipRange != nil
        || clipDraft.isActive
        || !markers.isEmpty
        || heatBins.contains(where: { $0 > 0 })
    )
  }

  var body: some View {
    MaxControlCluster(padding: MaxSpace.sm) {
      VStack(spacing: MaxSpace.xxs) {
        // Trickplay: the frame under the thumb, cropped from the storyboard
        // sprite, shown only while the user is actively scrubbing.
        if isScrubbing, duration > 0, let storyboard {
          GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = min(max(position / max(duration, 1), 0), 1)
            let x = min(max(CGFloat(fraction) * width, 64), max(width - 64, 64))
            PlayerTrickplayCell(storyboard: storyboard, fraction: fraction, time: position)
              .position(x: x, y: 46)
          }
          .frame(height: 92)
        }

        if showsAnnotations {
          PlayerScrubberAnnotations(
            duration: duration,
            markers: markers,
            clipRange: clipRange,
            clipDraft: clipDraft,
            onSeekToMarker: onSeekToMarker,
            onDeleteMarker: onDeleteMarker,
            heatBins: heatBins
          )
        }

        Slider(
          value: timelineBinding,
          in: 0...max(duration, 1),
          onEditingChanged: { editing in
            isScrubbing = editing
            if editing { loadStoryboardIfNeeded() }
            onSeekEditing(editing)
          }
        )
        .tint(.white)
        .disabled(!isReady || duration <= 0 || watchSyncDriven)
        .accessibilityLabel(Text("player.position"))
        .accessibilityHint(watchSyncDriven ? Text("watch.transport.locked") : Text(verbatim: ""))
        .accessibilityIdentifier("ui_player_seek")

        HStack(spacing: MaxSpace.sm) {
          Text(verbatim: position.playerTimeString)
            .accessibilityLabel(Text("player.current_position"))
          Text(verbatim: "/")
            .accessibilityHidden(true)
          Text(verbatim: duration.playerTimeString)
            .accessibilityLabel(Text("player.duration"))
          Spacer(minLength: 0)
          Button("player.restart", systemImage: "arrow.counterclockwise", action: onRestart)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .disabled(!isReady)
            .accessibilityIdentifier("ui_player_restart")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.82))
      }
    }
  }

  /// Fetches the sprite once per item, on the first scrub. The session cache
  /// hands back raw bytes (Sendable); decoding happens here on the main actor.
  private func loadStoryboardIfNeeded() {
    guard storyboard == nil, let storyboardURL else { return }
    Task {
      guard let data = await MaxStoryboardCache.shared.data(for: storyboardURL) else { return }
      storyboard = UIImage(data: data)
    }
  }
}

/// One trickplay frame: cell i (0–99) of the 10×10 sprite is i% of the
/// duration, cropped without copying pixels, with the target time underneath.
private struct PlayerTrickplayCell: View {
  let storyboard: UIImage
  let fraction: Double
  let time: Double

  var body: some View {
    VStack(spacing: 4) {
      if let cell = croppedCell {
        Image(uiImage: cell)
          .resizable()
          .scaledToFill()
          .frame(width: 120, height: 68)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(.white.opacity(0.35), lineWidth: 1)
          }
      }
      Text(verbatim: time.playerTimeString)
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.6), in: Capsule())
    }
    .shadow(radius: 6)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var croppedCell: UIImage? {
    guard let cgImage = storyboard.cgImage else { return nil }
    let index = min(99, max(0, Int(fraction * 100)))
    let cellWidth = cgImage.width / 10
    let cellHeight = cgImage.height / 10
    guard cellWidth > 0, cellHeight > 0 else { return nil }
    let rect = CGRect(
      x: (index % 10) * cellWidth,
      y: (index / 10) * cellHeight,
      width: cellWidth,
      height: cellHeight
    )
    guard let cropped = cgImage.cropping(to: rect) else { return nil }
    return UIImage(cgImage: cropped)
  }
}

/// One storyboard sprite per URL, fetched once and kept for the session. Data
/// (not UIImage) crosses the actor boundary so the payload stays Sendable; a
/// failed fetch is remembered so scrubbing never re-downloads a missing sprite.
private actor MaxStoryboardCache {
  static let shared = MaxStoryboardCache()

  private var dataByURL: [URL: Data] = [:]
  private var failedURLs: Set<URL> = []

  func data(for url: URL) async -> Data? {
    if let cached = dataByURL[url] { return cached }
    if failedURLs.contains(url) { return nil }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            !data.isEmpty else {
        failedURLs.insert(url)
        return nil
      }
      dataByURL[url] = data
      return data
    } catch {
      failedURLs.insert(url)
      return nil
    }
  }
}

private struct PlayerRatingControls: View {
  let subjects: [RatingSubject]
  let isLoading: Bool
  let action: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.xs) {
      if subjects.isEmpty {
        if isLoading {
          CompactRatingLoadingChip(action: action)
        } else {
          CompactRatingEmptyChip(action: action)
        }
      } else {
        ForEach(subjects) { subject in
          CompactRatingChip(subject: subject, action: action)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityIdentifier("ui_player_dual_ratings")
  }
}

private struct PlayerUtilityControls: View {
  let item: MaxMediaItem
  let isFavorite: Bool
  let isOfflineReady: Bool
  let activeDownload: TransferRecord?
  let shareURL: URL?
  let pictureInPictureSupported: Bool
  let pictureInPictureActive: Bool
  let isSavingToPhotos: Bool
  let didSaveToPhotos: Bool
  let onFavorite: () -> Void
  let onDownload: () -> Void
  let onSendToChat: () -> Void
  let onAddToCollection: () -> Void
  let onSaveToPhotos: () -> Void
  let onTogglePictureInPicture: () -> Void
  let onInteraction: () -> Void
  let onDelete: () -> Void
  let currentSpeed: Float
  let onSetSpeed: (Float) -> Void
  let isClipDraftActive: Bool
  let onDropMarker: () -> Void
  let onStampClip: () -> Void
  /// Watch Together: adds the room's quality/break/screenshot controls and
  /// hides trash (a shared session must not delete media under everyone).
  var watch: WatchChromeModel? = nil
  var onWatchAction: ((WatchAction) -> Void)? = nil
  /// Solo playback's "watch.start" entry point; nil hides it.
  var onStartWatch: (() -> Void)? = nil

  private static let speedChoices: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
  private static let breakMinuteChoices = [5, 10, 15]

  private func speedLabel(_ value: Float) -> String { String(format: "%g", Double(value)) }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      GlassEffectContainer(spacing: MaxSpace.xs) {
        HStack(spacing: MaxSpace.xs) {
          if item.kind.lowercased() == "video" {
            Menu {
              ForEach(Self.speedChoices, id: \.self) { speed in
                Button {
                  onSetSpeed(speed)
                } label: {
                  if abs(currentSpeed - speed) < 0.001 {
                    Label("\(speedLabel(speed))×", systemImage: "checkmark")
                  } else {
                    Text(verbatim: "\(speedLabel(speed))×")
                  }
                }
              }
            } label: {
              Text(verbatim: "\(speedLabel(currentSpeed))×")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: .circle)
            }
            .accessibilityIdentifier("ui_player_speed")

            PlayerUtilityButton(
              title: "Add marker",
              systemImage: "bookmark",
              accessibilityIdentifier: "ui_player_add_marker",
              action: onDropMarker
            )

            PlayerUtilityButton(
              title: isClipDraftActive ? "Stamp clip point" : "New clip",
              systemImage: "scissors",
              accessibilityIdentifier: "ui_player_clip",
              isSelected: isClipDraftActive,
              action: onStampClip
            )
          }

          if let watch {
            watchControls(watch)
          } else if let onStartWatch {
            PlayerUtilityButton(
              title: "watch.start",
              systemImage: "play.tv",
              accessibilityIdentifier: "ui_watch_start",
              action: onStartWatch
            )
          }

          PlayerUtilityButton(
            title: isFavorite ? "action.unsave" : "action.favorite",
            systemImage: isFavorite ? "heart.fill" : "heart",
            accessibilityIdentifier: "ui_player_favorite",
            isSelected: isFavorite,
            action: onFavorite
          )

          downloadControl

          if item.kind.lowercased() == "video" || item.kind.lowercased() == "image" {
            photoSaveControl
          }

          PlayerUtilityButton(
            title: "player.send_to_chat",
            systemImage: "paperplane.fill",
            accessibilityIdentifier: "ui_player_send_to_chat",
            action: onSendToChat
          )

          PlayerUtilityButton(
            title: "player.add_to_collection",
            systemImage: "rectangle.stack.badge.plus",
            accessibilityIdentifier: "ui_player_add_to_collection",
            action: onAddToCollection
          )

          shareControl

          if pictureInPictureSupported {
            PlayerUtilityButton(
              title: "player.picture_in_picture",
              systemImage: pictureInPictureActive ? "pip.exit" : "pip.enter",
              accessibilityIdentifier: "ui_player_pip",
              isSelected: pictureInPictureActive,
              action: onTogglePictureInPicture
            )
          }

          if watch == nil {
            PlayerUtilityButton(
              title: "action.move_to_trash",
              systemImage: "trash",
              accessibilityIdentifier: "ui_player_trash",
              action: onDelete
            )
          }
        }
      }
      .padding(.vertical, 2)
    }
    .accessibilityIdentifier("ui_player_actions")
  }

  /// The room's utility trio: local quality caps, the shared break (controller
  /// permission), and the screenshot-moment capture into the room's chat.
  @ViewBuilder
  private func watchControls(_ watch: WatchChromeModel) -> some View {
    Menu {
      ForEach(WatchQualityLevel.allCases) { level in
        Button {
          onWatchAction?(.setQuality(level))
        } label: {
          if watch.quality == level {
            Label(level.labelText, systemImage: "checkmark")
          } else {
            Text(verbatim: level.labelText)
          }
        }
      }
    } label: {
      Image(systemName: "gauge.with.dots.needle.67percent")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .glassEffect(.regular, in: .circle)
    }
    .accessibilityLabel(Text("watch.quality.title"))
    .accessibilityIdentifier("ui_watch_quality")

    if watch.canControl {
      Menu {
        ForEach(Self.breakMinuteChoices, id: \.self) { minutes in
          Button {
            onWatchAction?(.startBreak(minutes * 60))
          } label: {
            Text(verbatim: String(
              format: String(localized: "watch.break.minutes"),
              minutes
            ))
          }
        }
      } label: {
        Image(systemName: "cup.and.saucer.fill")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 52, height: 52)
          .glassEffect(.regular, in: .circle)
      }
      .accessibilityLabel(Text("watch.break.start"))
      .accessibilityIdentifier("ui_watch_break")
    }

    PlayerUtilityButton(
      title: "watch.screenshot_moment",
      systemImage: "camera.viewfinder",
      accessibilityIdentifier: "ui_watch_screenshot",
      action: { onWatchAction?(.screenshotMoment) }
    )

    PlayerUtilityButton(
      title: "watch.invite.title",
      systemImage: "person.badge.plus",
      accessibilityIdentifier: "ui_watch_invite",
      action: { onWatchAction?(.openInvite) }
    )

    PlayerUtilityButton(
      title: "watch.queue.title",
      systemImage: "list.bullet",
      accessibilityIdentifier: "ui_watch_queue",
      action: { onWatchAction?(.openQueue) }
    )

    PlayerUtilityButton(
      title: "watch.vote.title",
      systemImage: "checklist",
      accessibilityIdentifier: "ui_watch_vote",
      action: { onWatchAction?(.openVote) }
    )

    PlayerUtilityButton(
      title: "watch.settings.title",
      systemImage: "gearshape.fill",
      accessibilityIdentifier: "ui_watch_settings",
      action: { onWatchAction?(.openSettings) }
    )
  }

  @ViewBuilder
  private var photoSaveControl: some View {
    if isSavingToPhotos {
      ProgressView()
        .tint(.white)
        .frame(width: 52, height: 52)
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel(Text("photos.saving"))
        .accessibilityIdentifier("ui_player_save_photos_progress")
    } else {
      PlayerUtilityButton(
        title: didSaveToPhotos ? "photos.saved" : "action.save_to_photos",
        systemImage: didSaveToPhotos ? "checkmark.circle.fill" : "photo.badge.arrow.down",
        accessibilityIdentifier: "ui_player_save_to_photos",
        isSelected: didSaveToPhotos,
        isEnabled: !didSaveToPhotos,
        action: onSaveToPhotos
      )
    }
  }

  @ViewBuilder
  private var downloadControl: some View {
    if let activeDownload {
      Button(action: onInteraction) {
        ZStack {
          Image(systemName: "arrow.down.circle")
          if let progress = activeDownload.progress {
            ProgressView(value: progress)
              .progressViewStyle(.circular)
              .tint(.white)
          }
        }
        .frame(width: 52, height: 52)
      }
      .buttonStyle(.glass)
      .accessibilityLabel(Text("transfers.title"))
      .accessibilityValue(
        Text(verbatim: activeDownload.progress?.formatted(.percent) ?? "")
      )
      .accessibilityIdentifier("ui_player_download_progress")
    } else {
      PlayerUtilityButton(
        title: isOfflineReady ? "player.offline_ready" : "action.download",
        systemImage: isOfflineReady ? "checkmark.circle.fill" : "arrow.down.circle",
        accessibilityIdentifier: "ui_player_download",
        isSelected: isOfflineReady,
        isEnabled: item.downloadable && !isOfflineReady,
        action: onDownload
      )
    }
  }

  @ViewBuilder
  private var shareControl: some View {
    if let shareURL {
      ShareLink(item: shareURL) { shareIcon }
        .buttonStyle(.glass)
        .accessibilityLabel(Text("player.system_share"))
        .accessibilityIdentifier("ui_player_share")
    } else {
      ShareLink(item: item.title) { shareIcon }
        .buttonStyle(.glass)
        .accessibilityLabel(Text("player.system_share"))
        .accessibilityIdentifier("ui_player_share")
    }
  }

  private var shareIcon: some View {
    Image(systemName: "square.and.arrow.up")
      .font(.system(size: 20, weight: .semibold))
      .frame(width: 52, height: 52)
      .contentShape(Circle())
  }
}

private struct PlayerUtilityButton: View {
  let title: LocalizedStringKey
  let systemImage: String
  let accessibilityIdentifier: String
  var isSelected = false
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(title, systemImage: systemImage, action: action)
      .labelStyle(.iconOnly)
      .font(.system(size: 20, weight: .semibold))
      .buttonStyle(.glass)
      .frame(minWidth: 52, minHeight: 52)
      .tint(isSelected ? MaxColor.accent : nil)
      .disabled(!isEnabled)
      .accessibilityIdentifier(accessibilityIdentifier)
  }
}

/// The clip bar: sits above the bottom controls while a clip is playing (name,
/// range, loop, exit) or while one is being MADE (the A/B points, a name field,
/// save, cancel). Mirrors the desktop's PlayerClipBar.
private struct PlayerClipBar: View {
  let clipRange: PlayerClipRange?
  let clipDraft: PlayerClipDraft
  let position: Double
  let onStampPoint: (PlayerClipPoint) -> Void
  let onSave: (String) -> Void
  let onCancel: () -> Void
  let onToggleLoop: () -> Void
  let onExit: () -> Void

  @State private var title = ""

  private var canSave: Bool {
    guard let a = clipDraft.a, let b = clipDraft.b else { return false }
    return abs(b - a) >= 1
  }

  var body: some View {
    Group {
      if let clipRange {
        playingBar(clipRange)
      } else {
        draftBar
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, MaxSpace.sm)
    .glassEffect(.regular, in: .capsule)
    .accessibilityIdentifier("ui_player_clip_bar")
  }

  private func playingBar(_ range: PlayerClipRange) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "scissors")
        .font(.caption.weight(.semibold))
        .accessibilityHidden(true)

      Text(verbatim: range.title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)

      Text(verbatim: "\(range.start.playerTimeString)–\(range.end.playerTimeString)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.82))

      Spacer(minLength: 0)

      Button("Loop", systemImage: "arrow.counterclockwise", action: onToggleLoop)
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.semibold))
        .tint(range.loop ? MaxColor.accent : .white)
        .accessibilityIdentifier("ui_player_clip_loop")

      Button("Exit clip", systemImage: "xmark", action: onExit)
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.semibold))
        .tint(.white)
        .accessibilityIdentifier("ui_player_clip_exit")
    }
  }

  private var draftBar: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "scissors")
        .font(.caption.weight(.semibold))
        .accessibilityHidden(true)

      Button {
        onStampPoint(.a)
      } label: {
        Text(verbatim: clipDraft.a.map { "A \($0.playerTimeString)" } ?? "Set A")
          .font(.caption.weight(.semibold).monospacedDigit())
      }
      .buttonStyle(.bordered)
      .tint(clipDraft.a != nil ? MaxColor.accent : .white)
      .accessibilityIdentifier("ui_player_clip_set_a")

      Button {
        onStampPoint(.b)
      } label: {
        Text(verbatim: clipDraft.b.map { "B \($0.playerTimeString)" } ?? "Set B")
          .font(.caption.weight(.semibold).monospacedDigit())
      }
      .buttonStyle(.bordered)
      .tint(clipDraft.b != nil ? MaxColor.accent : .white)
      .accessibilityIdentifier("ui_player_clip_set_b")

      TextField("Clip name", text: $title)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.white)
        .submitLabel(.done)
        .onSubmit { if canSave { onSave(title) } }
        .accessibilityIdentifier("ui_player_clip_name")

      Button("Save") {
        onSave(title)
      }
      .buttonStyle(.borderedProminent)
      .font(.caption.weight(.semibold))
      .disabled(!canSave)
      .accessibilityIdentifier("ui_player_clip_save")

      Button("Cancel", systemImage: "xmark", action: onCancel)
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.semibold))
        .tint(.white)
        .accessibilityIdentifier("ui_player_clip_cancel")
    }
  }
}

/// The annotation lane: marker ticks plus the active clip range and the A/B
/// draft, drawn in track coordinates just above the scrubber. Everything is a
/// fraction of `duration` — nothing here depends on the playback tick.
private struct PlayerScrubberAnnotations: View {
  let duration: Double
  let markers: [MediaMarker]
  let clipRange: PlayerClipRange?
  let clipDraft: PlayerClipDraft
  let onSeekToMarker: (MediaMarker) -> Void
  let onDeleteMarker: (MediaMarker) -> Void
  /// Re-watch heat: your own history as a soft area under the lane.
  var heatBins: [Double] = []

  private let laneHeight: CGFloat = 18

  private var draftStart: Double? {
    if let a = clipDraft.a, let b = clipDraft.b { return min(a, b) }
    return clipDraft.a ?? clipDraft.b
  }

  private var draftEnd: Double? {
    guard let a = clipDraft.a, let b = clipDraft.b else { return nil }
    return max(a, b)
  }

  private func fraction(_ seconds: Double) -> CGFloat {
    guard duration > 0 else { return 0 }
    return CGFloat(min(max(seconds / duration, 0), 1))
  }

  var body: some View {
    GeometryReader { proxy in
      let width = max(proxy.size.width, 1)
      ZStack(alignment: .topLeading) {
        if heatBins.contains(where: { $0 > 0 }) {
          PlayerHeatArea(bins: heatBins)
            .fill(MaxColor.accent.opacity(0.35))
            .frame(width: width, height: laneHeight)
            .allowsHitTesting(false)
        }

        if let clipRange {
          rangeBand(
            start: fraction(clipRange.start),
            end: fraction(clipRange.end),
            width: width
          )
          .foregroundStyle(MaxColor.accent.opacity(0.5))
        }

        if let draftStart {
          rangeBand(
            start: fraction(draftStart),
            end: draftEnd.map(fraction) ?? fraction(draftStart),
            width: width
          )
          .foregroundStyle(.white.opacity(0.45))
        }

        ForEach(markers) { marker in
          Circle()
            .fill(.white)
            .frame(width: 7, height: 7)
            .frame(width: 24, height: laneHeight)
            .contentShape(Rectangle())
            .onTapGesture { onSeekToMarker(marker) }
            .onLongPressGesture { onDeleteMarker(marker) }
            .offset(x: width * fraction(marker.atSeconds) - 12)
            .accessibilityLabel(Text(verbatim: marker.label.isEmpty
              ? marker.atSeconds.playerTimeString
              : marker.label))
            .accessibilityAddTraits(.isButton)
        }
      }
      .frame(width: width, height: laneHeight, alignment: .topLeading)
    }
    .frame(height: laneHeight)
    .accessibilityIdentifier("ui_player_annotations")
  }

  private func rangeBand(start: CGFloat, end: CGFloat, width: CGFloat) -> some View {
    Capsule()
      .frame(width: max((end - start) * width, 2), height: 5)
      .offset(x: start * width, y: (laneHeight - 5) / 2)
  }
}

/// The heat lane's area path: one point per bin, closed along the baseline.
/// A `Shape` rebuilds only on size change, so the 100-point path is cheap.
private struct PlayerHeatArea: Shape {
  let bins: [Double]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard !bins.isEmpty, rect.width > 0, rect.height > 0 else { return path }
    let count = CGFloat(bins.count)
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    for (index, value) in bins.enumerated() {
      let x = rect.minX + rect.width * (CGFloat(index) + 0.5) / count
      let clamped = CGFloat(min(max(value, 0), 1))
      path.addLine(to: CGPoint(x: x, y: rect.maxY - clamped * rect.height))
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private extension Double {
  var playerTimeString: String {
    guard isFinite, self >= 0 else { return "0:00" }
    let totalSeconds = Int(self.rounded(.down))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
  }
}
