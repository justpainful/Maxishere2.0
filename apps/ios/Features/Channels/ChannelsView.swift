import SwiftUI

// Channels — always-running broadcasts built from a vault rule.
//
// The list shows what each channel is playing RIGHT NOW, which it works out
// itself: the store holds the frozen programme and the instant it started, and
// a one-second tick re-reads the arithmetic. Nothing here polls the server for
// a position, because the network in the middle of a shared moment is exactly
// what makes two people disagree.
//
// See docs/design/channels/LOGIC.md.

struct ChannelsView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  @State private var builder: BuilderTarget?
  @State private var tick = Date()
  @State private var tuned: ChannelDoc?

  /// The view's own second hand. It moves no state on the server and asks it
  /// nothing; it just makes the arithmetic re-run.
  private let heartbeat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private enum BuilderTarget: Identifiable {
    case new
    case edit(ChannelDoc)

    var id: String {
      switch self {
      case .new: "new"
      case .edit(let doc): doc.id
      }
    }
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.md) {
        header

        if model.channelStore.loaded && model.channelStore.channels.isEmpty {
          emptyState
        } else {
          // The card at the top is the one somebody is already inside — that
          // is the whole promise of the feature, so it is not one tile among
          // several.
          if let hero {
            ChannelHeroCard(doc: hero, nowMs: model.channelStore.nowMs) { tuned = hero } onEdit: { builder = .edit(hero) }
          }
          ForEach(rest) { doc in
            ChannelRowCard(doc: doc, nowMs: model.channelStore.nowMs) { tuned = doc } onEdit: { builder = .edit(doc) }
          }
          newChannelCard
        }
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.bottom, MaxSpace.tabBarClearance)
    }
    .background(palette.canvas.ignoresSafeArea())
    .navigationTitle(Text("channels.title"))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          builder = .new
        } label: {
          Label("channels.new", systemImage: "plus")
        }
        .accessibilityIdentifier("ui_channels_new")
      }
    }
    .task { await model.channelStore.refresh() }
    .refreshable { await model.channelStore.refresh() }
    .onReceive(heartbeat) { tick = $0 }
    .sheet(item: $builder) { target in
      switch target {
      case .new:
        ChannelBuilderView(existing: nil)
      case .edit(let doc):
        ChannelBuilderView(existing: doc)
      }
    }
    .fullScreenCover(item: $tuned) { doc in
      ChannelLiveView(channelID: doc.id)
    }
    .accessibilityIdentifier("ui_channels_screen")
  }

  private var hero: ChannelDoc? {
    model.channelStore.channels.first { doc in doc.listeners.contains(where: \.live) }
      ?? model.channelStore.channels.first { $0.started && !$0.empty }
      ?? model.channelStore.channels.first
  }

  private var rest: [ChannelDoc] {
    guard let hero else { return model.channelStore.channels }
    return model.channelStore.channels.filter { $0.id != hero.id }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xxs) {
      Text("channels.subtitle")
        .font(.subheadline)
        .foregroundStyle(palette.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyState: some View {
    MaxSurfaceCard {
      VStack(spacing: MaxSpace.sm) {
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(palette.secondaryText)
        Text("channels.empty")
          .font(.headline)
        Text("channels.empty.subtitle")
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
          .multilineTextAlignment(.center)
        Button {
          builder = .new
        } label: {
          Label("channels.new", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, MaxSpace.md)
    }
  }

  private var newChannelCard: some View {
    Button {
      builder = .new
    } label: {
      VStack(spacing: MaxSpace.xs) {
        Image(systemName: "plus")
          .font(.system(size: 22, weight: .semibold))
          .frame(width: 44, height: 44)
          .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        Text("channels.new").font(.subheadline.weight(.semibold))
        Text("channels.new.hint")
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(MaxSpace.md)
      .overlay {
        RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
          .stroke(palette.separator, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(palette.primaryText)
  }
}

// MARK: - Cards

/// The state dot. LIVE and OFF AIR must stay different at a glance, because
/// "am I still with the other person" is the only question this screen exists
/// to answer.
private struct ChannelStateBadge: View {
  let doc: ChannelDoc
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(colour).frame(width: 7, height: 7)
      Text(titleKey)
        .font(.caption2.weight(.semibold))
    }
    .padding(.horizontal, 9)
    .frame(height: 22)
    .background(palette.scrim, in: Capsule(style: .continuous))
    .foregroundStyle(.white)
  }

  private var colour: Color {
    if doc.empty { return palette.warning }
    if doc.started { return doc.listeners.contains(where: \.live) ? palette.destructive : palette.success }
    return palette.tertiaryText
  }

  private var titleKey: LocalizedStringKey {
    if doc.empty { return "channels.badge.empty" }
    if !doc.started { return "channels.badge.idle" }
    return doc.listeners.contains(where: \.live) ? "channels.badge.live" : "channels.badge.running"
  }
}

private struct ChannelHeroCard: View {
  let doc: ChannelDoc
  let nowMs: Int
  let onTune: () -> Void
  let onEdit: () -> Void
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    MaxSurfaceCard {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        Button(action: onTune) {
          ChannelFrame(doc: doc, nowMs: nowMs, height: 200)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 4) {
          Text(doc.name).font(.title3.weight(.bold))
          Text(ChannelRuleText.describe(doc.rule))
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
          Text(
            "channels.clips_and_loop \(doc.programme.items.count) \(ChannelRuleText.duration(doc.totalSeconds))"
          )
          .font(.caption)
          .foregroundStyle(palette.tertiaryText)
        }

        ChannelNowNext(doc: doc, nowMs: nowMs)
        ChannelListeners(doc: doc)

        HStack(spacing: MaxSpace.xs) {
          Button(action: onTune) {
            Label("channels.tune_in", systemImage: "play.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          Button(action: onEdit) {
            Label("channels.edit_rule", systemImage: "slider.horizontal.3")
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }
}

private struct ChannelRowCard: View {
  let doc: ChannelDoc
  let nowMs: Int
  let onTune: () -> Void
  let onEdit: () -> Void
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    MaxSurfaceCard {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        Button(action: onTune) {
          ChannelFrame(doc: doc, nowMs: nowMs, height: 132)
        }
        .buttonStyle(.plain)

        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text(doc.name).font(.headline)
            Text(ChannelRuleText.describe(doc.rule))
              .font(.caption)
              .foregroundStyle(palette.secondaryText)
              .lineLimit(2)
          }
          Spacer(minLength: MaxSpace.xs)
          Button(action: onEdit) {
            Image(systemName: "slider.horizontal.3")
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .foregroundStyle(palette.secondaryText)
          .accessibilityLabel(Text("channels.edit_rule"))
        }

        Text(footnote)
          .font(.caption)
          .foregroundStyle(palette.tertiaryText)
          .lineLimit(1)
      }
    }
  }

  private var footnote: LocalizedStringKey {
    if doc.empty { return "channels.empty.hint" }
    if !doc.started { return "channels.idle.hint" }
    let title = doc.ref(for: doc.position(atMs: nowMs)?.item.mediaId)?.name ?? ""
    return "channels.now_playing \(title)"
  }
}

/// The frame: poster, state badge, and — when it is running — how far into the
/// current clip the channel has reached.
private struct ChannelFrame: View {
  let doc: ChannelDoc
  let nowMs: Int
  let height: CGFloat
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    let position = doc.position(atMs: nowMs)
    let poster = doc.ref(for: position?.item.mediaId)?.posterUrl

    ZStack(alignment: .topLeading) {
      if let poster, let url = URL(string: poster) {
        MaxAsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().aspectRatio(contentMode: .fill)
          } else {
            palette.elevatedContentSurface
          }
        }
      } else {
        palette.elevatedContentSurface
      }

      ChannelStateBadge(doc: doc).padding(10)

      if let position {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Text(
              "\(ChannelRuleText.duration(position.into)) / \(ChannelRuleText.duration(position.item.seconds))"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(palette.scrim, in: Capsule(style: .continuous))
            .padding(10)
          }
          GeometryReader { geometry in
            Rectangle()
              .fill(palette.accent)
              .frame(width: geometry.size.width * progress(position), height: 3)
          }
          .frame(height: 3)
        }
      }

      Image(systemName: "play.fill")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(palette.scrim, in: Circle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: height)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
  }

  private func progress(_ position: ChannelPosition) -> CGFloat {
    guard position.item.seconds > 0 else { return 0 }
    return min(1, max(0, CGFloat(position.into / position.item.seconds)))
  }
}

private struct ChannelNowNext: View {
  let doc: ChannelDoc
  let nowMs: Int
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    let position = doc.position(atMs: nowMs)
    let next = position.map { doc.upcoming(after: $0.index) } ?? []

    VStack(alignment: .leading, spacing: 4) {
      row("channels.now", doc.ref(for: position?.item.mediaId)?.name)
      row("channels.next", next.isEmpty ? nil : next.compactMap { doc.ref(for: $0.mediaId)?.name }.joined(separator: " · "))
    }
  }

  private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: MaxSpace.xs) {
      Text(label)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .frame(width: 46, alignment: .leading)
      Text(value ?? String(localized: "channels.next.nothing"))
        .font(.caption)
        .foregroundStyle(value == nil ? palette.tertiaryText : palette.primaryText)
        .lineLimit(1)
    }
  }
}

private struct ChannelListeners: View {
  let doc: ChannelDoc
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    let live = doc.listeners.filter(\.live).count
    let off = doc.listeners.count - live

    HStack(spacing: MaxSpace.xs) {
      ForEach(doc.listeners) { listener in
        Text(String(listener.userId.prefix(1)).uppercased())
          .font(.caption2.weight(.bold))
          .frame(width: 28, height: 28)
          .background(listener.live ? palette.accent : palette.selectedControl, in: Circle())
          .foregroundStyle(listener.live ? Color.white : palette.secondaryText)
      }
      Text(label(live: live, off: off))
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
    }
  }

  private func label(live: Int, off: Int) -> LocalizedStringKey {
    if doc.listeners.isEmpty { return "channels.listeners.nobody" }
    if off > 0 { return "channels.listeners.some_off_air \(live) \(off)" }
    return "channels.listeners.count \(live)"
  }
}
