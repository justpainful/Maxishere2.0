import Foundation
import SwiftUI

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

  var body: some View {
    VStack(spacing: compactHeight ? MaxSpace.xs : MaxSpace.md) {
      PlayerTopControls(
        canOpenPrevious: canOpenPrevious,
        canOpenNext: canOpenNext,
        onClose: onClose,
        onOpenPrevious: onOpenPrevious,
        onOpenNext: onOpenNext
      )

      Spacer(minLength: compactHeight ? MaxSpace.xs : MaxSpace.md)

      if item.kind.lowercased() == "video" {
        PlayerTransportControls(
          compactHeight: compactHeight,
          isReady: isReady,
          isPlaying: isPlaying,
          isFinished: isFinished,
          position: position,
          onTogglePlayback: onTogglePlayback,
          onSkip: onSkip
        )
      }

      Spacer(minLength: compactHeight ? MaxSpace.xs : MaxSpace.md)

      VStack(spacing: compactHeight ? MaxSpace.xs : MaxSpace.sm) {
        if item.kind.lowercased() == "video" {
          PlayerTimelineControls(
            position: $position,
            duration: duration,
            isReady: isReady,
            onSeekEditing: onSeekEditing,
            onRestart: onRestart
          )
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
          onSetSpeed: onSetSpeed
        )
      }
    }
    .padding(.horizontal, compactHeight ? MaxSpace.sm : MaxSpace.md)
    .padding(.vertical, compactHeight ? MaxSpace.xs : MaxSpace.md)
  }
}

private struct PlayerTopControls: View {
  let canOpenPrevious: Bool
  let canOpenNext: Bool
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
  let onSeekEditing: (Bool) -> Void
  let onRestart: () -> Void

  private var timelineBinding: Binding<Double> {
    Binding(
      get: { position },
      set: { position = min(max($0, 0), max(duration, 0)) }
    )
  }

  var body: some View {
    MaxControlCluster(padding: MaxSpace.sm) {
      VStack(spacing: MaxSpace.xxs) {
        Slider(
          value: timelineBinding,
          in: 0...max(duration, 1),
          onEditingChanged: onSeekEditing
        )
        .tint(.white)
        .disabled(!isReady || duration <= 0)
        .accessibilityLabel(Text("player.position"))
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

  private static let speedChoices: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

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

          PlayerUtilityButton(
            title: "action.move_to_trash",
            systemImage: "trash",
            accessibilityIdentifier: "ui_player_trash",
            action: onDelete
          )
        }
      }
      .padding(.vertical, 2)
    }
    .accessibilityIdentifier("ui_player_actions")
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
