import AVKit
import SwiftUI

/// Tuned in — the channel playing.
///
/// The player follows the ARITHMETIC, not the other way round: every second
/// this view asks "what should be on now", and if the answer is a different
/// clip it swaps the item and seeks to how far in the channel already is. It
/// does not wait for the clip to end, because a channel does not stop when a
/// clip does, and a client that trusted the end would drift a little further
/// behind on every item until the two of you were watching different things
/// with no way to tell.
///
/// OFF AIR is the deliberate exception. Skipping is yours alone — the owner's
/// decision — so moving at all forks you off the shared timeline. Rather than
/// pretend otherwise, that fork is a named state with its own cursor, its own
/// transport, and one way back.
///
/// See docs/design/channels/LOGIC.md.
struct ChannelLiveView: View {
  let channelID: String

  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette

  @State private var player = AVPlayer()
  /// Which clip the player is currently loaded with.
  @State private var loadedMediaID: String?
  /// Where OUR cursor is once we have left the shared timeline. Nil means we
  /// are still on it.
  @State private var cursor: Int?
  @State private var tick = Date()

  private let heartbeat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  /// How far out of step with the channel we tolerate before correcting.
  ///
  /// Too tight and a decode hiccup makes the picture stutter as we seek it
  /// back; too loose and "the same moment" stops being true. Two seconds is
  /// under the threshold where two people notice they are out of step.
  private let driftToleranceSeconds: Double = 2

  var body: some View {
    ZStack {
      palette.canvas.ignoresSafeArea()

      if let doc, !doc.empty, !doc.programme.items.isEmpty {
        content(doc)
      } else if doc == nil {
        blank(title: "channels.gone", message: "channels.gone.hint")
      } else {
        blank(title: "channels.empty.title", message: "channels.empty.rule_hint")
      }
    }
    .task {
      await model.channelStore.tune(id: channelID)
    }
    .onDisappear {
      player.pause()
      Task { await model.channelStore.leave() }
    }
    .onReceive(heartbeat) { instant in
      tick = instant
      align()
    }
    // Off air has no shared clock to follow, so here — and only here — the end
    // of a clip is what moves us on. On air the arithmetic has already moved
    // us before a clip can reach its end.
    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
      guard offAir, let doc else { return }
      step(1, in: doc)
    }
    .accessibilityIdentifier("ui_channel_live_screen")
  }

  private var store: ChannelStore { model.channelStore }
  private var doc: ChannelDoc? { store.channel(id: channelID) }

  private var offAir: Bool {
    store.isOffAir(channelID: channelID, userID: model.sessionStore.user?.id)
  }

  /// Where playback should be: the channel's position when live, our own
  /// cursor when off air.
  private func target(_ doc: ChannelDoc) -> (index: Int, item: ChannelProgrammeItem, into: Double)? {
    let items = doc.programme.items
    guard !items.isEmpty else { return nil }
    let live = doc.position(atMs: store.nowMs)
    guard offAir, let cursor else {
      guard let live else { return nil }
      return (live.index, live.item, live.into)
    }
    let index = ((cursor % items.count) + items.count) % items.count
    return (index, items[index], 0)
  }

  @ViewBuilder
  private func content(_ doc: ChannelDoc) -> some View {
    let slot = target(doc)

    VStack(spacing: MaxSpace.sm) {
      ZStack(alignment: .top) {
        VideoPlayer(player: player)
          .aspectRatio(16 / 9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        HStack(spacing: MaxSpace.xs) {
          Button { dismiss() } label: {
            Image(systemName: "chevron.down")
              .font(.headline)
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel(Text("action.close"))

          HStack(spacing: 6) {
            Circle()
              .fill(offAir ? palette.warning : palette.destructive)
              .frame(width: 7, height: 7)
            Text(offAir ? "channels.badge.off_air" : "channels.badge.live")
              .font(.caption2.weight(.semibold))
          }
          .padding(.horizontal, 9)
          .frame(height: 22)
          .background(palette.scrim, in: Capsule(style: .continuous))

          Spacer()

          if let slot {
            Text("channels.position \(slot.index + 1) \(doc.programme.items.count)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.white)
          }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, MaxSpace.sm)
        .padding(.top, MaxSpace.xs)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(doc.ref(for: slot?.item.mediaId)?.name ?? String(localized: "channels.now.untitled"))
          .font(.headline)
          .lineLimit(1)
        Text(offAir
             ? "channels.off_air.explain"
             : "channels.live.explain \(ChannelRuleText.duration(doc.totalSeconds))")
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      transport(doc)

      upNext(doc, from: slot?.index ?? 0)

      Spacer(minLength: 0)
    }
    .padding(MaxSpace.md)
    .onChange(of: slot?.item.mediaId) { _, _ in align() }
    .onAppear { align() }
  }

  /// Transport. Previous and next are ALWAYS here, live or not — pressing
  /// either is simply what takes you off air, because moving at all is what
  /// forks you off the shared timeline. Hiding them until you were already off
  /// air meant the only way to reach them was a button that also moved you,
  /// and there was no way back by one.
  private func transport(_ doc: ChannelDoc) -> some View {
    HStack(spacing: MaxSpace.md) {
      Button { step(-1, in: doc) } label: {
        Image(systemName: "backward.end.fill")
          .font(.title3)
          .frame(width: 56, height: 44)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel(Text("channels.previous"))

      Button { step(1, in: doc) } label: {
        Image(systemName: "forward.end.fill")
          .font(.title3)
          .frame(width: 56, height: 44)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel(Text("channels.skip"))

      if offAir {
        Button {
          Task {
            await store.setLive(true)
            cursor = nil
            loadedMediaID = nil
            align()
          }
        } label: {
          Label("channels.back_to_live", systemImage: "antenna.radiowaves.left.and.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }

      Spacer(minLength: 0)
    }
  }

  private func upNext(_ doc: ChannelDoc, from index: Int) -> some View {
    // "Up next" follows whichever cursor is driving: the channel's when live,
    // ours when off air. Showing the channel's next while we are somewhere
    // else entirely would list things that are not going to happen to us.
    let next = doc.upcoming(after: index)
    return VStack(alignment: .leading, spacing: MaxSpace.xs) {
      if !next.isEmpty {
        Text("channels.next")
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
        ForEach(next) { item in
          HStack(spacing: MaxSpace.xs) {
            Image(systemName: "play.fill").font(.caption2)
            Text(doc.ref(for: item.mediaId)?.name ?? String(localized: "channels.now.untitled"))
              .lineLimit(1)
            Spacer(minLength: MaxSpace.xs)
            Text(ChannelRuleText.duration(item.seconds))
              .foregroundStyle(palette.tertiaryText)
              .monospacedDigit()
          }
          .font(.caption)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func blank(title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
    VStack(spacing: MaxSpace.sm) {
      Image(systemName: "antenna.radiowaves.left.and.right")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(palette.secondaryText)
      Text(title).font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(palette.secondaryText)
        .multilineTextAlignment(.center)
      Button(String(localized: "action.close")) { dismiss() }
        .buttonStyle(.bordered)
    }
    .padding(MaxSpace.lg)
  }

  /// Move our own cursor. Moving at all means leaving the shared timeline, so
  /// the first press is also what takes us off air.
  private func step(_ delta: Int, in doc: ChannelDoc) {
    let items = doc.programme.items
    guard !items.isEmpty else { return }
    let from = cursor ?? doc.position(atMs: store.nowMs)?.index ?? 0
    cursor = (((from + delta) % items.count) + items.count) % items.count
    loadedMediaID = nil
    if !offAir {
      Task { await store.setLive(false) }
    }
    align()
  }

  /// Load and align. The seek is what keeps a shared moment shared — a clip
  /// that started 40 seconds ago is joined 40 seconds in, not from the top.
  private func align() {
    guard let doc, let slot = target(doc) else { return }

    // A channel ships refs only for what it is about to name. Off air we can
    // be anywhere in the loop, so ask for what we are about to need — the
    // current item and its neighbours in both directions, since either button
    // may be pressed next.
    let items = doc.programme.items
    let around = [-1, 0, 1, 2].map { step in
      items[(((slot.index + step) % items.count) + items.count) % items.count].mediaId
    }
    Task { await store.ensureRefs(channelID: channelID, mediaIDs: around) }

    guard let ref = doc.ref(for: slot.item.mediaId), let url = URL(string: ref.mediaUrl) else { return }

    if loadedMediaID != slot.item.mediaId {
      loadedMediaID = slot.item.mediaId
      player.replaceCurrentItem(with: AVPlayerItem(url: url))
      let start = offAir ? 0 : slot.into
      player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
      player.play()
      return
    }
    guard !offAir else { return }

    // Already on the right clip: correct only if we have actually drifted.
    let current = player.currentTime().seconds
    if current.isFinite, abs(current - slot.into) > driftToleranceSeconds {
      player.seek(to: CMTime(seconds: slot.into, preferredTimescale: 600))
    }
  }
}
