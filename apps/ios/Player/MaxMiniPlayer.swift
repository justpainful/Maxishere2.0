@preconcurrency import AVFoundation
import Observation
import SwiftUI

/// The floating mini-player: playback that survives browsing.
///
/// Minimising the full player hands {item, position, playing} here; the card
/// owns its OWN AVPlayer, so none of the full player's state machines run
/// underneath. Expanding re-opens the modal player at the card's live position.
/// Mirrors the desktop's MiniPlayer, minus the context acrobatics.
@MainActor
@Observable
final class MiniPlayerStore {
  private(set) var item: MaxMediaItem?
  private(set) var startAt: Double = 0
  private(set) var playing = false

  /// Hand the CURRENT playback over to the mini card.
  func open(item: MaxMediaItem, startAt: Double, playing: Bool) {
    self.item = item
    self.startAt = max(startAt, 0)
    self.playing = playing
  }

  func close() {
    item = nil
    startAt = 0
    playing = false
  }
}

/// Positions the card bottom-trailing over the whole shell, clear of the tab
/// bar. Renders nothing while no playback has been minimised.
struct MaxMiniPlayerHost: View {
  @Environment(MaxAppModel.self) private var model

  var body: some View {
    if let item = model.miniPlayerStore.item {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        HStack(spacing: 0) {
          Spacer(minLength: 0)
          MaxMiniPlayerCard(item: item)
        }
      }
      .padding(.trailing, MaxSpace.md)
      .padding(.bottom, 96)
    }
  }
}

/// The card itself: a ~160 pt video surface, a title bar with expand and close.
/// Tap anywhere on the video to expand back into the full player.
struct MaxMiniPlayerCard: View {
  @Environment(MaxAppModel.self) private var model
  let item: MaxMediaItem

  @State private var player = AVPlayer()

  var body: some View {
    VStack(spacing: 0) {
      MaxInlinePlayerSurface(player: player, videoGravity: .resizeAspectFill)
        .frame(width: 160, height: 90)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)

      HStack(spacing: MaxSpace.xs) {
        Text(verbatim: item.displayTitle)
          .font(.caption2.weight(.semibold))
          .lineLimit(1)
          .foregroundStyle(.white)

        Spacer(minLength: 0)

        Button(action: expand) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Expand player"))
        .accessibilityIdentifier("ui_mini_player_expand")

        Button(action: close) {
          Image(systemName: "xmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close mini player"))
        .accessibilityIdentifier("ui_mini_player_close")
      }
      .padding(.horizontal, MaxSpace.xs)
      .padding(.vertical, 5)
      .background(Color.black.opacity(0.88))
    }
    .frame(width: 160)
    .background(Color.black)
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    .task(id: item.id) { await startPlayback() }
    .onDisappear {
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
    .accessibilityIdentifier("ui_mini_player")
  }

  private func startPlayback() async {
    // Adaptive stream first, same preference order as the full player.
    guard let url = item.hlsUrl ?? item.mediaUrl else { return }
    player.replaceCurrentItem(with: AVPlayerItem(url: url))
    let startAt = model.miniPlayerStore.startAt
    if startAt > 0.5 {
      await player.seek(
        to: CMTime(seconds: startAt, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
    if model.miniPlayerStore.playing {
      player.play()
    }
  }

  /// Carry the card's live position back into the full player: the item copy's
  /// `lastPosition` is what playback preparation resumes from.
  private func expand() {
    let live = player.currentTime().seconds
    let resumeAt = live.isFinite && live > 0 ? live : model.miniPlayerStore.startAt
    player.pause()
    model.miniPlayerStore.close()
    model.openPlayer(for: item.withLastPosition(resumeAt))
  }

  private func close() {
    player.pause()
    model.miniPlayerStore.close()
  }
}
