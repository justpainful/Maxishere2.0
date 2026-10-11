import Foundation
import SwiftUI

/// A media-first Vault. Every tile owns a fixed grid cell, preserves the whole
/// image, and loads the backend-provided thumbnail rather than video bytes.
struct VaultView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var searchText = ""
  @State private var kind: MaxLibraryKindFilter = .all
  @State private var sort: MaxLibrarySort = .recent
  @State private var shuffleItems: [MaxMediaItem] = []
  @State private var shuffleInitialID: String?
  @State private var showsShuffle = false
  @State private var showsTrash = false
  @State private var smartFilters = SmartFiltersStore()
  @State private var showsFilterBuilder = false
  @State private var shareLinkItem: MaxMediaItem?
  @State private var continueItems: [MaxContinueItem]?
  /// The item a "Watch Together" context-menu tap is starting a room around.
  @State private var watchStartItem: MaxMediaItem?

  private let grid = [
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm, alignment: .top),
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm, alignment: .top),
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.md) {
        browserControls
        continueWatchingRow
        browserContent
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.sm)
    }
    .navigationTitle("tab.vault")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "vault.search"
    )
    .toolbar { vaultToolbar }
    .navigationDestination(isPresented: $showsTrash) { TrashView() }
    .refreshable { await loadVault() }
    .task {
      guard !model.isUITestMode, model.libraryStore.catalogPhase.value == nil else { return }
      await loadVault()
    }
    .task {
      guard !model.isUITestMode, continueItems == nil else { return }
      await loadContinueWatching()
    }
    .fullScreenCover(isPresented: $showsShuffle, onDismiss: clearShuffle) {
      MaxScrollingPlayerView(
        items: shuffleItems,
        initialItemID: shuffleInitialID,
        onClose: { showsShuffle = false },
        watchSource: WatchSource(
          mode: "shuffle",
          kind: kind == .all ? "" : kind.rawValue,
          search: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
          sort: sort.rawValue
        )
      )
    }
    .sheet(item: $watchStartItem) { item in
      WatchInviteSheet(context: WatchStartContext(mediaItem: item))
    }
    .sheet(isPresented: $showsFilterBuilder) {
      SmartFilterBuilderSheet(store: smartFilters)
    }
    .sheet(item: $shareLinkItem) { item in
      ShareLinkSheetView(item: item)
    }
    .maxTabContent()
    .councilLight(.home)
    .accessibilityIdentifier("ui_vault_screen")
  }

  private var browserControls: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MaxSpace.xs) {
        ForEach(MaxLibraryKindFilter.allCases) { option in
          Button {
            withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
              kind = option
            }
          } label: {
            MaxChip(title: option.title, isSelected: kind == option)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_vault_kind_\(option.rawValue)")
        }

        // Saved smart filters ride beside the kind chips: tap toggles, the
        // context menu deletes, and "+" opens the little builder.
        ForEach(smartFilters.filters) { filter in
          Button {
            withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
              smartFilters.toggle(filter.id)
            }
          } label: {
            SmartFilterChipLabel(
              text: filter.name,
              isSelected: smartFilters.activeID == filter.id
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button(role: .destructive) {
              smartFilters.remove(filter.id)
            } label: {
              Label("Delete Filter", systemImage: "trash")
            }
          }
        }

        Button {
          showsFilterBuilder = true
        } label: {
          SmartFilterChipLabel(text: "+", isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("New Smart Filter"))
        .accessibilityIdentifier("ui_vault_smart_filter_add")
      }
      .padding(.vertical, 2)
    }
    .accessibilityIdentifier("ui_vault_kind_filters")
  }

  @ViewBuilder
  private var browserContent: some View {
    if model.libraryStore.catalogPhase.isLoading && model.libraryStore.catalogItems.isEmpty {
      MaxVaultBrowserSkeleton(grid: grid)
    } else if let error = model.libraryStore.catalogPhase.errorMessage,
              model.libraryStore.catalogItems.isEmpty {
      MaxLoadFailureView(message: error) {
        Task { await loadVault() }
      }
    } else if visibleItems.isEmpty {
      MaxEmptyState(
        title: searchText.isEmpty ? "vault.personal.empty" : "search.empty.title",
        subtitle: searchText.isEmpty
          ? "vault.personal.empty.subtitle"
          : "search.empty.subtitle",
        symbol: searchText.isEmpty ? "film.stack" : "magnifyingglass"
      )
    } else {
      // Masonry rather than a fixed grid: a library mixing portrait and landscape
      // video cannot share one cell height without cropping one of them, which is
      // what made portrait clips look zoomed in and the spacing look irregular.
      MaxMediaMasonry(
        items: visibleItems,
        columnCount: 2,
        spacing: MaxSpace.md,
        aspectRatio: { $0.aspectRatio }
      ) { item in
        Button {
          model.openCatalogPlayer(
            for: item,
            kind: kind,
            search: searchText,
            sort: sort
          )
        } label: {
          MaxVaultReliableTile(
            item: item,
            isOffline: model.transferStore.localURL(for: item) != nil,
            transferProgress: model.transferStore.progress[item.id]
          )
        }
        .buttonStyle(.plain)
        .contextMenu { mediaContextMenu(for: item) }
        .onAppear { loadNextPageIfNeeded(after: item) }
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("ui_vault_media_\(item.id)")
      }
      .frame(maxWidth: .infinity)

      paginationFooter
    }
  }

  @ViewBuilder
  private var paginationFooter: some View {
    if model.libraryStore.catalogPageState.isLoading {
      ProgressView("vault.loading")
        .frame(maxWidth: .infinity)
        .padding(.vertical, MaxSpace.md)
        .accessibilityIdentifier("ui_vault_loading_more")
    } else if let error = model.libraryStore.catalogPageState.errorMessage {
      Button {
        Task { await model.libraryStore.loadMoreCatalog() }
      } label: {
        Label {
          Text(verbatim: error).lineLimit(2)
        } icon: {
          Image(systemName: "arrow.clockwise")
        }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("ui_vault_retry_page")
    }
  }

  @ToolbarContentBuilder
  private var vaultToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        Task { await presentShuffle() }
      } label: {
        Label("vault.shuffle", systemImage: "shuffle")
      }
      .disabled(shuffleCandidates.isEmpty)
      .accessibilityIdentifier("ui_vault_shuffle")
    }

    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button {
          model.openUpload(destination: .personal)
        } label: {
          Label("upload.title", systemImage: "square.and.arrow.up")
        }

        Picker("library.sort.title", selection: $sort) {
          ForEach(MaxLibrarySort.allCases) { option in
            Text(option.title).tag(option)
          }
        }

        Button {
          model.selectedTab = .library
        } label: {
          Label("tab.library", systemImage: "rectangle.grid.2x2")
        }

        Divider()

        // Deleting happens here, in the tile context menu, so recovering has to
        // be reachable from here too. Buried three taps away in another tab, the
        // Trash may as well not exist.
        Button {
          showsTrash = true
        } label: {
          Label("library.trash", systemImage: "trash")
        }
        .accessibilityIdentifier("ui_vault_open_trash")
      } label: {
        Label("common.more", systemImage: "ellipsis.circle")
      }
      .accessibilityIdentifier("ui_vault_more")
    }
  }

  private var visibleItems: [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let activeSmartFilter = smartFilters.activeFilter
    return sort.apply(to: model.libraryStore.catalogItems.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
        || (item.uploader.name?.localizedCaseInsensitiveContains(query) ?? false)
        || (item.workspace?.name?.localizedCaseInsensitiveContains(query) ?? false)
      let matchesSmart = activeSmartFilter?.matches(item) ?? true
      return matchesSearch && kind.includes(item) && matchesSmart
    })
  }

  private var shuffleCandidates: [MaxMediaItem] {
    model.libraryStore.catalogItems.filter {
      let mediaKind = $0.kind.lowercased()
      return mediaKind == "video" || mediaKind == "image"
    }
  }

  private func loadVault() async {
    await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
    await loadContinueWatching()
  }

  /// Loads the Continue Watching shelf; a failure simply leaves it hidden.
  private func loadContinueWatching() async {
    continueItems = (try? await model.apiClient.continueWatching()) ?? []
  }

  /// Up to three videos left partway through, above the grid — tap resumes.
  @ViewBuilder
  private var continueWatchingRow: some View {
    if searchText.isEmpty, let items = continueItems, !items.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: "Continue Watching")
        HStack(alignment: .top, spacing: MaxSpace.sm) {
          ForEach(items.prefix(3)) { item in
            Button {
              openContinueItem(item)
            } label: {
              ContinueWatchingCard(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_vault_continue_\(item.mediaId)")
          }
        }
      }
    }
  }

  /// The shelf only carries a media id, so the item is resolved first; the
  /// player then resumes from the saved position on its own.
  private func openContinueItem(_ item: MaxContinueItem) {
    Task {
      guard let media = await model.resolveMediaItem(id: item.mediaId) else { return }
      model.openPlayer(for: media)
    }
  }

  private func loadNextPageIfNeeded(after item: MaxMediaItem) {
    let threshold = visibleItems.suffix(8).contains { $0.id == item.id }
    guard threshold else { return }
    Task { await model.libraryStore.loadMoreCatalog() }
  }

  private func presentShuffle() async {
    await model.libraryStore.loadRemainingCatalogPages()
    let candidates = model.libraryStore.catalogItems.filter {
      let mediaKind = $0.kind.lowercased()
      return mediaKind == "video" || mediaKind == "image"
    }
    guard !candidates.isEmpty else { return }
    shuffleItems = candidates.shuffled()
    shuffleInitialID = shuffleItems.first?.id
    showsShuffle = true
  }

  private func clearShuffle() {
    shuffleItems = []
    shuffleInitialID = nil
  }

  @ViewBuilder
  private func mediaContextMenu(for item: MaxMediaItem) -> some View {
    Button("action.play", systemImage: "play.fill") {
      model.openCatalogPlayer(for: item, kind: kind, search: searchText, sort: sort)
    }
    if item.kind.lowercased() == "video" {
      Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
        model.queuePlayNext(item)
      }
    }
    if model.watchPartiesEnabled {
      Button("watch.start", systemImage: "play.tv") {
        watchStartItem = item
      }
    }
    Button("action.rate", systemImage: "star") {
      model.openRating(for: item)
    }
    Button(
      item.isFavorite || item.isSaved ? "action.unsave" : "action.favorite",
      systemImage: item.isFavorite || item.isSaved ? "heart.slash" : "heart"
    ) {
      Task { await model.toggleFavorite(item) }
    }
    if item.downloadable, model.transferStore.localURL(for: item) == nil {
      Button("action.download", systemImage: "arrow.down.circle") {
        Task { await model.transferStore.download(item) }
      }
    }
    Button {
      shareLinkItem = item
    } label: {
      Label("Share Link…", systemImage: "link")
    }
    if item.kind.lowercased() == "image" || item.kind.lowercased() == "video" {
      Button {
        Task { _ = try? await model.apiClient.postStory(mediaID: item.id, caption: "") }
      } label: {
        Label("Add to Story", systemImage: "plus.circle.dashed")
      }
    }
    Divider()
    Button(role: .destructive) {
      Task { await model.libraryStore.trash(item) }
    } label: {
      Label("action.move_to_trash", systemImage: "trash")
    }
  }
}

/// One Continue Watching card: poster, name, and how far in the viewer was.
private struct ContinueWatchingCard: View {
  let item: MaxContinueItem

  private var progress: Double {
    guard let duration = item.durationSeconds, duration > 0 else { return 0 }
    return min(max(item.positionSeconds / duration, 0), 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      ZStack(alignment: .bottom) {
        ZStack {
          RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
            .fill(MaxColor.surfaceStrong)
          if let posterUrl = item.posterUrl {
            MaxAsyncImage(url: posterUrl) { phase in
              if case .success(let image) = phase {
                image.resizable().scaledToFill()
              } else {
                Color.clear
              }
            }
          } else {
            Image(systemName: "film")
              .foregroundStyle(MaxColor.textTertiary)
          }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))

        if progress > 0 {
          ProgressView(value: progress)
            .tint(MaxColor.accent)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
      }

      Text(verbatim: item.name.asMediaDisplayName)
        .font(.caption.weight(.semibold))
        .foregroundStyle(MaxColor.textPrimary)
        .lineLimit(1)

      Text(verbatim: "You were at \(item.positionSeconds.minuteString)")
        .font(.caption2)
        .foregroundStyle(MaxColor.textSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.name.asMediaDisplayName))
  }
}

private struct MaxVaultReliableTile: View {
  let item: MaxMediaItem
  let isOffline: Bool
  let transferProgress: Double?

  private var isVideo: Bool { item.kind.lowercased() == "video" }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
        .fill(Color.black.opacity(0.08))

      // Use the same poster pipeline as every other media surface. In
      // particular, video rows fall back to AVFoundation frame extraction
      // when the API has no thumbnail or an old signed thumbnail has expired.
      //
      // The masonry column already sized this tile from the item's own
      // dimensions, so the poster must not impose a second ratio on top.
      MaxMediaPoster(item: item, compact: true, showsMetadata: false, usesContainerShape: true)
        .padding(2)

      if isVideo {
        Image(systemName: "play.fill")
          .font(.headline)
          .foregroundStyle(.white)
          .padding(11)
          .background(.black.opacity(0.62), in: Circle())
      }

      VStack {
        HStack {
          if isOffline {
            Image(systemName: "arrow.down.circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(6)
              .background(.black.opacity(0.58), in: Circle())
          }
          Spacer()
          if let duration = item.duration, isVideo {
            Text(Self.durationText(duration))
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 4)
              .background(.black.opacity(0.68), in: Capsule())
          }
        }
        Spacer()
        if let progress = transferProgress {
          ProgressView(value: progress)
            .tint(.white)
            .padding(8)
            .background(.black.opacity(0.45))
        }
      }
      .padding(8)
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
    .clipped()
    .overlay {
      RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
  }

  private static func durationText(_ duration: Double) -> String {
    let total = max(0, Int(duration.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
    return String(format: "%d:%02d", minutes, seconds)
  }
}

/// A user-named chip, so the label is verbatim text rather than a
/// localization key — which is the only reason MaxChip is not reused.
private struct SmartFilterChipLabel: View {
  let text: String
  let isSelected: Bool

  var body: some View {
    Text(verbatim: text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
      .padding(.horizontal, MaxSpace.sm)
      .padding(.vertical, MaxSpace.xs)
      .background(
        isSelected ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.regularMaterial),
        in: Capsule(style: .continuous)
      )
  }
}

/// The little builder: name, kind, minimum minutes, and the two toggles.
/// Everything is client-side, so saving is instant.
private struct SmartFilterBuilderSheet: View {
  @Environment(\.dismiss) private var dismiss
  let store: SmartFiltersStore

  @State private var name = ""
  @State private var kind = "video"
  @State private var minMinutes = ""
  @State private var unrated = false
  @State private var favoritesOnly = false

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        Picker("Kind", selection: $kind) {
          Text("All").tag("all")
          Text("Video").tag("video")
          Text("Image").tag("image")
          Text("Audio").tag("audio")
        }
        TextField("Minimum minutes", text: $minMinutes)
          .keyboardType(.numberPad)
        Toggle("Unrated only", isOn: $unrated)
        Toggle("Favorites only", isOn: $favoritesOnly)
      }
      .navigationTitle("New Smart Filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            store.save(
              name: trimmedName,
              kind: kind,
              minMinutes: Int(minMinutes.trimmingCharacters(in: .whitespaces)) ?? 0,
              unrated: unrated,
              favoritesOnly: favoritesOnly
            )
            dismiss()
          }
          .disabled(trimmedName.isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
    .accessibilityIdentifier("ui_vault_smart_filter_builder")
  }
}

private struct MaxVaultBrowserSkeleton: View {
  let grid: [GridItem]

  var body: some View {
    LazyVGrid(columns: grid, spacing: MaxSpace.md) {
      ForEach(0..<8, id: \.self) { _ in
        RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
          .fill(MaxColor.surfaceStrong)
          .aspectRatio(1, contentMode: .fit)
          .redacted(reason: .placeholder)
      }
    }
    .accessibilityLabel(Text("loading.media"))
  }
}
