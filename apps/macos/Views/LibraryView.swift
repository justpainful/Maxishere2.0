import SwiftUI

struct LibraryView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    @Bindable var model = model
    let palette = model.palette

    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ForEach(LibrarySection.allCases) { section in
          Button {
            model.selectedLibrarySection = section
          } label: {
            Label(model.copy(section.rawValue), systemImage: section.symbol)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .foregroundStyle(model.selectedLibrarySection == section ? Color.white : palette.textPrimary)
              .background {
                if model.selectedLibrarySection == section {
                  Capsule().fill(palette.accent)
                }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("mac_library_\(section.rawValue)")
        }
        Spacer()
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 18)

      Divider().opacity(0.35)

      ScrollView {
        Group {
          switch model.selectedLibrarySection {
          case .overview:
            libraryOverview(palette: palette)
          case .saved:
            mediaSection(title: model.copy("saved"), items: model.media.filter { $0.isSaved && !$0.isTrashed }, emptyMessage: "Save media from Vault or Chat to see it here.")
          case .ratings:
            ratingsSection(palette: palette)
          case .offline:
            mediaSection(title: model.copy("offline"), items: model.media.filter { $0.isOffline && !$0.isTrashed }, emptyMessage: "Downloaded media is available here without a connection.")
          case .collections:
            collectionsSection(palette: palette)
          case .trash:
            trashSection(palette: palette)
          }
        }
        .padding(28)
      }
    }
    .navigationTitle(model.copy("library"))
    .accessibilityIdentifier("mac_library_screen")
  }

  private func libraryOverview(palette: MaxPalette) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(model.copy("library"))
            .font(.system(size: 38, weight: .bold, design: .rounded))
          Text("Saved media, personal ratings, collections, and offline copies.")
            .foregroundStyle(palette.textSecondary)
        }
        Spacer()
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18)], spacing: 18) {
        libraryDestination(.saved, count: model.media.filter { $0.isSaved && !$0.isTrashed }.count, tint: palette.accent)
        libraryDestination(.ratings, count: model.media.filter { $0.ownRating != nil && !$0.isTrashed }.count, tint: .yellow)
        libraryDestination(.offline, count: model.media.filter { $0.isOffline && !$0.isTrashed }.count, tint: .green)
        libraryDestination(.collections, count: model.collections.count, tint: palette.secondaryAccent)
        libraryDestination(.trash, count: model.media.filter(\.isTrashed).count, tint: .red)
      }

      Text("Recently saved")
        .font(.title2.bold())
      mediaRows(model.media.filter { $0.isSaved && !$0.isTrashed }.prefix(4).map { $0 })
    }
  }

  private func libraryDestination(_ section: LibrarySection, count: Int, tint: Color) -> some View {
    Button {
      model.selectedLibrarySection = section
    } label: {
      GlassCard(tint: tint) {
        HStack(spacing: 16) {
          Image(systemName: section.symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .circle)
          VStack(alignment: .leading, spacing: 4) {
            Text(model.copy(section.rawValue))
              .font(.headline)
            Text("\(count) items")
              .foregroundStyle(model.palette.textSecondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(model.palette.textSecondary)
        }
        .padding(18)
      }
    }
    .buttonStyle(.plain)
  }

  private func mediaSection(title: String, items: [MediaItem], emptyMessage: String) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(title)
        .font(.system(size: 34, weight: .bold, design: .rounded))
      if items.isEmpty {
        EmptyStateView(symbol: "tray", title: "Nothing here yet", message: emptyMessage)
          .frame(minHeight: 400)
      } else {
        mediaRows(items)
      }
    }
  }

  private func mediaRows(_ items: [MediaItem]) -> some View {
    LazyVStack(spacing: 12) {
      ForEach(items) { item in
        Button { model.open(item) } label: {
          HStack(spacing: 14) {
            MediaArtwork(item: item, compact: true)
              .frame(width: 94, height: 64)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
              Text(item.title).font(.headline)
              Text(item.subtitle).font(.caption).foregroundStyle(model.palette.textSecondary)
            }
            Spacer()
            if item.isOffline { Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green) }
            if item.isSaved { Image(systemName: "bookmark.fill").foregroundStyle(model.palette.accent) }
            Image(systemName: "chevron.right").foregroundStyle(model.palette.textSecondary)
          }
          .padding(12)
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac_library_media_\(item.id)")
      }
    }
  }

  private func ratingsSection(palette: MaxPalette) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(model.copy("ratings"))
        .font(.system(size: 34, weight: .bold, design: .rounded))
      Text("Your score and your partner’s score remain separate — Max never averages them.")
        .foregroundStyle(palette.textSecondary)
      LazyVStack(spacing: 12) {
        ForEach(model.media.filter { $0.ownRating != nil && !$0.isTrashed }) { item in
          HStack(spacing: 14) {
            MediaArtwork(item: item, compact: true)
              .frame(width: 90, height: 62)
              .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) {
              Text(item.title).font(.headline)
              Text(item.subtitle).font(.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            RatingBadge(title: "You", value: item.ownRating, tint: palette.accent)
            RatingBadge(title: "Nora", value: item.partnerRating, tint: palette.secondaryAccent)
          }
          .padding(14)
          .glassEffect(.regular, in: .rect(cornerRadius: 17))
        }
      }
    }
  }

  private func collectionsSection(palette: MaxPalette) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(model.copy("collections"))
        .font(.system(size: 34, weight: .bold, design: .rounded))
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
        ForEach(model.collections) { collection in
          GlassCard(tint: Color(hue: collection.hue, saturation: 0.7, brightness: 0.9)) {
            VStack(alignment: .leading, spacing: 16) {
              Image(systemName: collection.symbol)
                .font(.system(size: 34))
                .foregroundStyle(Color(hue: collection.hue, saturation: 0.7, brightness: 0.95))
              Text(collection.name).font(.title3.bold())
              Text(collection.summary).font(.caption).foregroundStyle(palette.textSecondary)
              HStack(spacing: -7) {
                ForEach(collection.itemIDs.prefix(4), id: \.self) { id in
                  Circle()
                    .fill(Color(hue: model.media.first(where: { $0.id == id })?.hue ?? 0.6, saturation: 0.65, brightness: 0.85))
                    .frame(width: 25, height: 25)
                    .overlay(Circle().stroke(palette.solidSurface, lineWidth: 2))
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
          }
        }
      }
    }
  }

  private func trashSection(palette: MaxPalette) -> some View {
    let trashed = model.media.filter(\.isTrashed)
    return VStack(alignment: .leading, spacing: 20) {
      Text(model.copy("trash"))
        .font(.system(size: 34, weight: .bold, design: .rounded))
      Text("Items are removed permanently after 30 days.")
        .foregroundStyle(palette.textSecondary)
      ForEach(trashed) { item in
        HStack(spacing: 14) {
          MediaArtwork(item: item, compact: true)
            .frame(width: 94, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading) {
            Text(item.title).font(.headline)
            Text(item.subtitle).font(.caption).foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Button(model.copy("restore")) { model.restoreFromTrash(item.id) }
            .buttonStyle(.glass)
          Button(model.copy("delete"), role: .destructive) { }
            .buttonStyle(.glass)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 17))
      }
    }
  }
}

struct RatingBadge: View {
  let title: String
  let value: Int?
  let tint: Color

  var body: some View {
    VStack(spacing: 2) {
      Text(value.map(String.init) ?? "—")
        .font(.title3.bold())
      Text(title)
        .font(.caption2)
    }
    .foregroundStyle(tint)
    .frame(width: 52, height: 48)
    .glassEffect(.regular.tint(tint.opacity(0.2)), in: .rect(cornerRadius: 13))
  }
}
