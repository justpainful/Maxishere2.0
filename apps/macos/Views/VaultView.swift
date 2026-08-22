import SwiftUI

struct VaultView: View {
  @Environment(MaxDesktopModel.self) private var model
  @State private var query = ""
  @State private var kind: MediaKind = .all
  @State private var sortNewestFirst = true

  private var visibleMedia: [MediaItem] {
    model.media
      .filter { !$0.isTrashed }
      .filter { kind == .all || $0.kind == kind }
      .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
      .sorted { sortNewestFirst ? $0.uploadedAt > $1.uploadedAt : $0.title < $1.title }
  }

  var body: some View {
    let palette = model.palette

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        header(palette: palette)

        HStack(spacing: 14) {
          Picker("Kind", selection: $kind) {
            ForEach(MediaKind.allCases) { option in
              Text(model.copy(option.rawValue)).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 420)
          .accessibilityIdentifier("mac_vault_kind")

          Spacer()

          Menu {
            Button("Newest first") { sortNewestFirst = true }
            Button("Title") { sortNewestFirst = false }
          } label: {
            Label(sortNewestFirst ? "Newest" : "Title", systemImage: "arrow.up.arrow.down")
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .accessibilityIdentifier("mac_vault_sort")
        }

        if visibleMedia.isEmpty {
          EmptyStateView(symbol: "magnifyingglass", title: "No results", message: "Try another search or media filter.")
            .frame(minHeight: 420)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 215, maximum: 330), spacing: 18)], spacing: 18) {
            ForEach(visibleMedia) { item in
              MediaTile(item: item)
                .environment(model)
            }
          }
        }
      }
      .padding(28)
    }
    .searchable(text: $query, placement: .toolbar, prompt: model.copy("search"))
    .navigationTitle(model.copy("vault"))
    .accessibilityIdentifier("mac_vault_screen")
  }

  private func header(palette: MaxPalette) -> some View {
    GlassCard(tint: palette.accent) {
      HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 9) {
          Text(model.copy("vault"))
            .font(.system(size: 38, weight: .bold, design: .rounded))
          Text("Everything you keep, in one private place.")
            .font(.title3)
            .foregroundStyle(palette.textSecondary)
        }
        Spacer()
        stat(value: "\(model.media.filter { !$0.isTrashed }.count)", label: "Items", symbol: "square.stack.3d.up.fill", palette: palette)
        stat(value: "18.7 GB", label: "Storage", symbol: "internaldrive.fill", palette: palette)
        stat(value: "\(model.media.filter(\.isOffline).count)", label: model.copy("offline"), symbol: "arrow.down.circle.fill", palette: palette)
      }
      .padding(24)
    }
  }

  private func stat(value: String, label: String, symbol: String, palette: MaxPalette) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(value, systemImage: symbol)
        .font(.title3.bold())
        .foregroundStyle(palette.accent)
      Text(label)
        .font(.caption)
        .foregroundStyle(palette.textSecondary)
    }
    .frame(minWidth: 90, alignment: .leading)
  }
}

struct MediaTile: View {
  @Environment(MaxDesktopModel.self) private var model
  let item: MediaItem

  var body: some View {
    let palette = model.palette

    Button {
      model.open(item)
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        MediaArtwork(item: item)
          .frame(height: 150)
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 7) {
              if item.isOffline {
                Image(systemName: "arrow.down.circle.fill")
              }
              if item.isSaved {
                Image(systemName: "bookmark.fill")
              }
            }
            .foregroundStyle(.white)
            .padding(10)
          }

        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .firstTextBaseline) {
            Text(item.title)
              .font(.headline)
              .lineLimit(1)
            Spacer()
            if let rating = item.ownRating {
              Label("\(rating)", systemImage: "star.fill")
                .font(.caption.bold())
                .foregroundStyle(.yellow)
            }
          }
          Text(item.subtitle)
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
          HStack {
            Label(item.kind == .video ? "Video" : "Image", systemImage: item.kind == .video ? "play.fill" : "photo.fill")
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
          }
          .font(.caption2)
          .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    .contextMenu {
      Button(item.isSaved ? "Remove from Saved" : "Save") { model.toggleSaved(item.id) }
      Button(item.isOffline ? "Remove Download" : "Download") { model.toggleOffline(item.id) }
      Divider()
      Button("Move to Trash", role: .destructive) { model.moveToTrash(item.id) }
    }
    .accessibilityIdentifier("mac_media_\(item.id)")
  }
}

