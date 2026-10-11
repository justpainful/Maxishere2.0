import SwiftUI

struct LibraryView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette
  @State private var searchText = ""
  @State private var sort: MaxLibrarySort = .recent
  @State private var kind: MaxLibraryKindFilter = .all
  @State private var showsVerticalFeed = false
  @State private var initialScrollingPlayerItem: MaxMediaItem? = nil

  private let destinationGrid = [
    GridItem(.flexible(), spacing: MaxSpace.md),
    GridItem(.flexible(), spacing: MaxSpace.md),
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.xl) {
        destinations
        PluginExtensionPointView(pointId: "library:summary")
        activeDownloadsPreview
        recentSavedPreview
        recentRatedPreview
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.lg)
    }
    .navigationTitle("tab.library")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "vault.search"
    )
    .toolbar { filterToolbar }
    .fullScreenCover(isPresented: $showsVerticalFeed) {
      MaxScrollingPlayerView(
        items: verticalFeedItems,
        initialItemID: initialScrollingPlayerItem?.id,
        onClose: {
          showsVerticalFeed = false
          initialScrollingPlayerItem = nil
        },
        watchSource: WatchSource(
          mode: "shuffle",
          kind: kind == .all ? "" : kind.rawValue,
          search: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
          sort: sort.rawValue
        )
      )
    }
    .refreshable { await refreshLibrary() }
    .task {
      guard !model.isUITestMode, model.libraryStore.phase.value == nil else { return }
      await refreshLibrary()
    }
    .maxTabContent()
    .councilLight(.vault)
    .accessibilityIdentifier("ui_library_screen")
  }

  private var destinations: some View {
    LazyVGrid(columns: destinationGrid, spacing: MaxSpace.md) {
      NavigationLink {
        SavedLibraryView()
      } label: {
        MaxLibraryDestinationCard(
          title: "library.saved",
          subtitle: "library.saved.subtitle",
          systemImage: "heart.fill",
          accent: MaxColor.coral,
          count: savedItems.count
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_library_saved")

      NavigationLink {
        RatingsLibraryView()
      } label: {
        MaxLibraryDestinationCard(
          title: "library.ratings",
          subtitle: "library.ratings.subtitle",
          systemImage: "star.fill",
          accent: MaxColor.amber,
          count: ratedItems.count
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_library_ratings")

      NavigationLink {
        OfflineLibraryView()
      } label: {
        MaxLibraryDestinationCard(
          title: "storage.offline.title",
          subtitle: "library.downloads.subtitle",
          systemImage: "arrow.down.circle.fill",
          accent: MaxColor.sky,
          count: model.transferStore.items.count
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_library_offline")

      NavigationLink {
        TrashView()
      } label: {
        MaxLibraryDestinationCard(
          title: "library.trash",
          subtitle: "library.trash.subtitle",
          systemImage: "trash.fill",
          accent: MaxColor.rose,
          count: model.libraryStore.trashedItems.isEmpty
            ? nil
            : model.libraryStore.trashedItems.count
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_library_trash")

      NavigationLink {
        ClipsLibraryView()
      } label: {
        MaxLibraryDestinationCard(
          title: "Clips",
          subtitle: "Saved ranges from the player",
          systemImage: "scissors",
          accent: MaxColor.lavender,
          count: model.clipsStore.shelf?.isEmpty == false
            ? model.clipsStore.shelf?.count
            : nil
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_library_clips")

      if model.isMemoriesEnabled {
        Button {
          model.openMemories()
        } label: {
          MaxLibraryDestinationCard(
            title: "memories.library.title",
            subtitle: "memories.library.subtitle",
            systemImage: "sparkles.rectangle.stack.fill",
            accent: MaxColor.periwinkle,
            count: nil
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_library_memories")
      }
    }
  }

  @ViewBuilder
  private var activeDownloadsPreview: some View {
    if !activeDownloads.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(
          title: "transfers.active",
          actionTitle: "transfers.view_all",
          action: { model.openTransfers() }
        )

        ForEach(Array(activeDownloads.prefix(2))) { record in
          Button {
            model.openTransfers()
          } label: {
            MaxLibraryTransferRow(record: record)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var recentSavedPreview: some View {
    if !visibleSavedItems.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: "library.recent_saved")

        ForEach(Array(visibleSavedItems.prefix(3))) { item in
          Button {
            model.openPlayer(for: item)
          } label: {
            MaxLibraryMediaRow(
              item: item,
              showsSavedState: true,
              isOffline: model.transferStore.localURL(for: item) != nil
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var recentRatedPreview: some View {
    if !visibleRatedItems.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: "library.recent_rated")

        ForEach(Array(visibleRatedItems.prefix(3))) { item in
          Button {
            model.openPlayer(for: item)
          } label: {
            MaxLibraryMediaRow(
              item: item,
              showsSavedState: false,
              isOffline: model.transferStore.localURL(for: item) != nil
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            if item.kind.lowercased() == "video" {
              Button {
                initialScrollingPlayerItem = item
                showsVerticalFeed = true
              } label: {
                Label("player.play_vertical", systemImage: "rectangle.stack.fill")
              }
            }
          }
        }
      }
    }
  }

  @ToolbarContentBuilder
  private var filterToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        showsVerticalFeed = true
      } label: {
        Label("player.vertical_feed", systemImage: "rectangle.stack.fill")
      }
      .disabled(verticalFeedItems.isEmpty)
      .accessibilityIdentifier("ui_library_vertical_feed")
    }

    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Picker("library.sort.title", selection: $sort) {
          ForEach(MaxLibrarySort.allCases) { option in
            Text(option.title).tag(option)
          }
        }

        Picker("home.filter.kind", selection: $kind) {
          ForEach(MaxLibraryKindFilter.allCases) { option in
            Text(option.title).tag(option)
          }
        }
      } label: {
        Label("home.filters", systemImage: "arrow.up.arrow.down.circle")
      }
      .accessibilityIdentifier("ui_library_filters")
    }
  }

  private var savedItems: [MaxMediaItem] {
    model.libraryStore.phase.value?.saved ?? []
  }

  private var ratedItems: [MaxMediaItem] {
    model.libraryStore.catalogItems.filter { $0.rating != nil }
  }

  private var visibleSavedItems: [MaxMediaItem] {
    filter(savedItems)
  }

  private var visibleRatedItems: [MaxMediaItem] {
    filter(ratedItems)
  }

  private var activeDownloads: [TransferRecord] {
    model.transferStore.activeRecords.filter { $0.kind == .download }
  }

  private var verticalFeedItems: [MaxMediaItem] {
    var seen = Set<String>()
    let merged = savedItems + model.libraryStore.catalogItems
    let videos = merged.filter { item in
      item.kind.lowercased() == "video" && seen.insert(item.id).inserted
    }
    return sort.apply(to: videos)
  }

  private func filter(_ items: [MaxMediaItem]) -> [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = items.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
        || (item.uploader.name?.localizedCaseInsensitiveContains(query) ?? false)
        || (item.workspace?.name?.localizedCaseInsensitiveContains(query) ?? false)
      return matchesSearch && kind.includes(item)
    }
    return sort.apply(to: filtered)
  }

  private func refreshLibrary() async {
    await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
    // Warmed alongside the library so the Clips card can show its count.
    await model.clipsStore.loadShelf()
  }
}

private struct SavedLibraryView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var searchText = ""
  @State private var sort: MaxLibrarySort = .recent
  @State private var kind: MaxLibraryKindFilter = .all
  /// The item a "Watch Together" context-menu tap is starting a room around.
  @State private var watchStartItem: MaxMediaItem?

  var body: some View {
    ScrollView {
      LazyVStack(spacing: MaxSpace.sm) {
        if model.libraryStore.phase.isLoading && items.isEmpty {
          LibraryRowSkeleton()
        } else if let error = model.libraryStore.phase.errorMessage, items.isEmpty {
          MaxLoadFailureView(message: error) {
            Task { await refresh() }
          }
        } else if items.isEmpty {
          MaxEmptyState(
            title: searchText.isEmpty ? "library.saved.empty" : "search.empty.title",
            subtitle: searchText.isEmpty
              ? "library.saved.empty.subtitle"
              : "search.empty.subtitle",
            symbol: searchText.isEmpty ? "heart" : "magnifyingglass"
          )
        } else {
          ForEach(items) { item in
            Button {
              model.openPlayer(for: item)
            } label: {
              MaxLibraryMediaRow(
                item: item,
                showsSavedState: true,
                isOffline: model.transferStore.localURL(for: item) != nil
              )
            }
            .buttonStyle(.plain)
            .contextMenu { savedContextMenu(for: item) }
            .accessibilityIdentifier("ui_saved_media_\(item.id)")
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(MaxSpace.md)
    }
    .navigationTitle("library.saved")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "vault.search")
    .toolbar { mediaFilterToolbar(sort: $sort, kind: $kind) }
    .refreshable { await refresh() }
    .task {
      guard !model.isUITestMode, model.libraryStore.phase.value == nil else { return }
      await refresh()
    }
    .sheet(item: $watchStartItem) { item in
      WatchInviteSheet(context: WatchStartContext(mediaItem: item))
    }
    .maxScreenBackground()
    .accessibilityIdentifier("ui_saved_screen")
  }

  private var items: [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let saved = model.libraryStore.phase.value?.saved ?? []
    return sort.apply(to: saved.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
        || (item.uploader.name?.localizedCaseInsensitiveContains(query) ?? false)
      return matchesSearch && kind.includes(item)
    })
  }

  private func refresh() async {
    await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
  }

  @ViewBuilder
  private func savedContextMenu(for item: MaxMediaItem) -> some View {
    Button("action.play", systemImage: "play.fill") {
      model.openPlayer(for: item)
    }
    if model.watchPartiesEnabled {
      Button("watch.start", systemImage: "play.tv") {
        watchStartItem = item
      }
    }
    Button("action.rate", systemImage: "star") {
      model.openRating(for: item)
    }
    Button("action.unsave", systemImage: "heart.slash") {
      Task { await model.toggleFavorite(item) }
    }
    if let collections = model.libraryStore.phase.value?.collections,
       !collections.isEmpty {
      Menu("collection.add", systemImage: "rectangle.stack.badge.plus") {
        ForEach(collections) { collection in
          Button {
            Task {
              _ = await model.libraryStore.add(
                fileID: item.id,
                toCollectionID: collection.id
              )
            }
          } label: {
            Text(verbatim: collection.name ?? String(localized: "common.collection"))
          }
        }
      }
    }
    if item.downloadable, model.transferStore.localURL(for: item) == nil {
      Button("action.download", systemImage: "arrow.down.circle") {
        Task { await model.transferStore.download(item) }
      }
    }
    Divider()
    Button(role: .destructive) {
      Task {
        if await model.libraryStore.trash(item) { await refresh() }
      }
    } label: {
      Label("action.move_to_trash", systemImage: "trash")
    }
  }
}

private struct RatingsLibraryView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var searchText = ""
  @State private var sort: MaxLibrarySort = .recent
  @State private var kind: MaxLibraryKindFilter = .all

  var body: some View {
    ScrollView {
      LazyVStack(spacing: MaxSpace.sm) {
        if model.libraryStore.catalogPhase.isLoading && items.isEmpty {
          LibraryRowSkeleton()
        } else if let error = model.libraryStore.catalogPhase.errorMessage, items.isEmpty {
          MaxLoadFailureView(message: error) {
            Task { await refresh() }
          }
        } else if items.isEmpty {
          MaxEmptyState(
            title: searchText.isEmpty ? "library.ratings.empty" : "search.empty.title",
            subtitle: searchText.isEmpty
              ? "library.ratings.empty.subtitle"
              : "search.empty.subtitle",
            symbol: searchText.isEmpty ? "star" : "magnifyingglass"
          )
        } else {
          ForEach(items) { item in
            Button {
              model.openPlayer(for: item)
            } label: {
              VStack(alignment: .leading, spacing: MaxSpace.xs) {
                MaxLibraryMediaRow(
                  item: item,
                  showsSavedState: false,
                  isOffline: model.transferStore.localURL(for: item) != nil
                )
                RatingPairSummary(subjects: model.ratingStore.subjects(for: item.id))
                  .padding(.horizontal, MaxSpace.sm)
                  .padding(.bottom, MaxSpace.xs)
              }
            }
            .buttonStyle(.plain)
            .contextMenu { ratingContextMenu(for: item) }
            .accessibilityIdentifier("ui_ratings_media_\(item.id)")
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(MaxSpace.md)
    }
    .navigationTitle("library.ratings")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "vault.search")
    .toolbar { mediaFilterToolbar(sort: $sort, kind: $kind) }
    .refreshable { await refresh() }
    .task {
      if model.libraryStore.catalogPhase.value == nil {
        await refresh()
      }
      await model.ratingStore.loadLibrary()
    }
    .maxScreenBackground()
    .accessibilityIdentifier("ui_ratings_screen")
  }

  private var items: [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let loaded = model.ratingStore.ratedEntries.map(\.media)
    let rated = loaded.isEmpty
      ? model.libraryStore.catalogItems.filter { $0.rating != nil }
      : loaded
    return sort.apply(to: rated.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
        || (item.uploader.name?.localizedCaseInsensitiveContains(query) ?? false)
      return matchesSearch && kind.includes(item)
    })
  }

  private func refresh() async {
    await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
  }

  @ViewBuilder
  private func ratingContextMenu(for item: MaxMediaItem) -> some View {
    Button("action.play", systemImage: "play.fill") {
      model.openPlayer(for: item)
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
  }
}

private struct RatingPairSummary: View {
  let subjects: [RatingSubject]

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      ForEach(subjects.prefix(2)) { subject in
        HStack(spacing: MaxSpace.xxs) {
          MaxAvatar(name: subject.user.displayName, imageURL: subject.user.avatarUrl, size: 22)
          Text(verbatim: subject.user.displayName)
            .lineLimit(1)
          Text(verbatim: subject.score.map { "\($0) / 10" } ?? "— / 10")
            .fontWeight(.semibold)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.caption)
    .foregroundStyle(MaxColor.textSecondary)
    .accessibilityElement(children: .combine)
  }
}

private struct OfflineLibraryView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var searchText = ""
  @State private var removalCandidate: LocalDownload?
  @State private var confirmsRemoveAll = false

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.xl) {
        storageSummary
        activeSection
        downloadsSection
      }
      .padding(MaxSpace.md)
    }
    .navigationTitle("storage.offline.title")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "vault.search")
    .toolbar { offlineToolbar }
    .confirmationDialog(
      "action.remove_download",
      isPresented: removalDialogBinding,
      titleVisibility: .visible
    ) {
      if let removalCandidate {
        Button("action.remove_download", role: .destructive) {
          model.transferStore.remove(removalCandidate)
          self.removalCandidate = nil
        }
      }
      Button("common.cancel", role: .cancel) {
        removalCandidate = nil
      }
    }
    .confirmationDialog(
      "storage.offline.remove_all.confirm.title",
      isPresented: $confirmsRemoveAll,
      titleVisibility: .visible
    ) {
      Button("storage.offline.remove_all", role: .destructive) {
        model.transferStore.removeAllDownloads()
      }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("storage.offline.remove_all.confirm.message")
    }
    .maxScreenBackground()
    .accessibilityIdentifier("ui_offline_screen")
  }

  private var storageSummary: some View {
    MaxContentSurface {
      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())],
        alignment: .leading,
        spacing: MaxSpace.lg
      ) {
        summaryMetric(
          value: model.transferStore.usedBytes.byteString,
          label: "storage.offline.used",
          symbol: "internaldrive"
        )

        summaryMetric(
          value: model.transferStore.items.count.formatted(),
          label: "storage.offline.items",
          symbol: "arrow.down.circle"
        )

        if !activeDownloads.isEmpty {
          summaryMetric(
            value: activeDownloads.count.formatted(),
            label: "transfers.active",
            symbol: "waveform.path"
          )
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var activeSection: some View {
    if !activeDownloads.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(
          title: "transfers.active",
          actionTitle: "transfers.view_all",
          action: { model.openTransfers() }
        )

        ForEach(activeDownloads) { record in
          MaxLibraryTransferRow(record: record)
            .contextMenu {
              if record.state.canCancel {
                Button("transfer.cancel", systemImage: "xmark.circle") {
                  model.transferStore.cancel(record.id)
                }
              }
            }
        }
      }
    }
  }

  @ViewBuilder
  private var downloadsSection: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "storage.offline.files")

      if visibleDownloads.isEmpty {
        MaxEmptyState(
          title: searchText.isEmpty ? "storage.offline.empty" : "search.empty.title",
          subtitle: searchText.isEmpty
            ? "storage.offline.empty.subtitle"
            : "search.empty.subtitle",
          symbol: searchText.isEmpty ? "arrow.down.circle" : "magnifyingglass"
        )
      } else {
        ForEach(visibleDownloads) { download in
          HStack(spacing: MaxSpace.xs) {
            Button {
              open(download)
            } label: {
              OfflineDownloadRow(download: download)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_offline_open_\(download.id)")

            Menu {
              Button("action.play", systemImage: "play.fill") {
                open(download)
              }
              Button("action.remove_download", systemImage: "trash", role: .destructive) {
                removalCandidate = download
              }
            } label: {
              Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("common.media"))
          }
        }
      }
    }
  }

  @ToolbarContentBuilder
  private var offlineToolbar: some ToolbarContent {
    if !model.transferStore.items.isEmpty {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("storage.offline.remove_all", systemImage: "trash", role: .destructive) {
            confirmsRemoveAll = true
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("storage.offline.remove_all"))
      }
    }
  }

  private var activeDownloads: [TransferRecord] {
    model.transferStore.activeRecords.filter { $0.kind == .download }
  }

  private var visibleDownloads: [LocalDownload] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return model.transferStore.items
      .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
      .sorted { $0.downloadedAt > $1.downloadedAt }
  }

  private var removalDialogBinding: Binding<Bool> {
    Binding(
      get: { removalCandidate != nil },
      set: { isPresented in
        if !isPresented { removalCandidate = nil }
      }
    )
  }

  private func open(_ download: LocalDownload) {
    if let existing = model.libraryStore.catalogItems.first(where: { $0.id == download.id }) {
      model.openPlayer(for: existing)
      return
    }

    let localItem = MaxMediaItem(
      id: download.id,
      title: download.title,
      kind: download.kind,
      sizeBytes: download.sizeBytes,
      duration: nil,
      mediaUrl: download.localURL,
      thumbnailUrl: nil,
      videoThumbnailUrl: nil,
      uploader: .init(id: nil, name: nil, avatarUrl: nil),
      workspace: nil,
      uploadedAt: nil,
      rating: nil,
      isFavorite: false,
      isSaved: false,
      lastPosition: 0,
      lastViewedAt: nil,
      isPrivate: true,
      downloadable: false
    )
    model.openPlayer(for: localItem)
  }

  private func summaryMetric(
    value: String,
    label: LocalizedStringKey,
    symbol: String
  ) -> some View {
    VStack(alignment: .leading, spacing: MaxSpace.xxs) {
      Image(systemName: symbol)
        .foregroundStyle(MaxColor.accent)
      Text(verbatim: value)
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)
      Text(label)
        .font(.caption)
        .foregroundStyle(MaxColor.textSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct MaxCollectionDetailView: View {
  @Environment(MaxAppModel.self) private var model
  let collection: CollectionSummary

  @State private var phase: LoadState<[MaxMediaItem]> = .idle
  @State private var searchText = ""
  @State private var sort: MaxLibrarySort = .recent
  @State private var kind: MaxLibraryKindFilter = .all

  private let grid = [
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm),
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm),
  ]

  var body: some View {
    ScrollView {
      Group {
        if let loaded = phase.value {
          let visible = filtered(loaded)
          if visible.isEmpty {
            MaxEmptyState(
              title: searchText.isEmpty ? "collection.empty" : "search.empty.title",
              subtitle: searchText.isEmpty
                ? "collection.empty.subtitle"
                : "search.empty.subtitle",
              symbol: searchText.isEmpty ? "rectangle.stack" : "magnifyingglass"
            )
          } else {
            LazyVGrid(columns: grid, spacing: MaxSpace.sm) {
              ForEach(visible) { item in
                Button {
                  model.openPlayer(for: item)
                } label: {
                  MaxVaultMediaCard(
                    item: item,
                    isOffline: model.transferStore.localURL(for: item) != nil,
                    transferProgress: model.transferStore.progress[item.id]
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
        } else if phase.isLoading {
          ProgressView("vault.loading")
            .frame(maxWidth: .infinity)
            .padding(.vertical, MaxSpace.xl)
        } else if let error = phase.errorMessage {
          MaxLoadFailureView(message: error) {
            Task { await load() }
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(MaxSpace.md)
    }
    .navigationTitle(collection.name ?? String(localized: "common.collection"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "vault.search")
    .toolbar { mediaFilterToolbar(sort: $sort, kind: $kind) }
    .refreshable { await load() }
    .task { await load() }
    .maxScreenBackground()
  }

  private func load() async {
    guard !model.isUITestMode else { return }
    phase = .loading
    var query = MediaQuery()
    query.mode = "browse"
    query.collectionId = collection.id
    query.limit = 100
    do {
      phase = .loaded(try await model.apiClient.media(query: query).items)
    } catch {
      phase = .failed(ProductError.from(error, area: .ratings).reason)
    }
  }

  private func filtered(_ items: [MaxMediaItem]) -> [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = items.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
      return matchesSearch && kind.includes(item)
    }
    return sort.apply(to: filtered)
  }
}

@ToolbarContentBuilder
private func mediaFilterToolbar(
  sort: Binding<MaxLibrarySort>,
  kind: Binding<MaxLibraryKindFilter>
) -> some ToolbarContent {
  ToolbarItem(placement: .topBarTrailing) {
    Menu {
      Picker("library.sort.title", selection: sort) {
        ForEach(MaxLibrarySort.allCases) { option in
          Text(option.title).tag(option)
        }
      }
      Picker("home.filter.kind", selection: kind) {
        ForEach(MaxLibraryKindFilter.allCases) { option in
          Text(option.title).tag(option)
        }
      }
    } label: {
      Label("home.filters", systemImage: "arrow.up.arrow.down.circle")
    }
  }
}

private struct OfflineDownloadRow: View {
  let download: LocalDownload

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: download.kind == "video" ? "play.rectangle.fill" : "photo.fill")
        .font(.title2)
        .foregroundStyle(MaxColor.accent)
        .frame(width: 54, height: 54)
        .background(MaxColor.surfaceSoft, in: RoundedRectangle(
          cornerRadius: MaxRadius.small,
          style: .continuous
        ))

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: download.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .lineLimit(2)
        HStack(spacing: MaxSpace.xs) {
          Text(verbatim: download.sizeBytes.byteString)
          Text(verbatim: download.downloadedAt.formatted(date: .abbreviated, time: .omitted))
        }
        .font(.caption)
        .foregroundStyle(MaxColor.textSecondary)
      }

      Spacer(minLength: 0)

      Image(systemName: "play.circle.fill")
        .font(.title3)
        .foregroundStyle(MaxColor.accent)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryRowSkeleton: View {
  var body: some View {
    ForEach(0..<4, id: \.self) { _ in
      HStack(spacing: MaxSpace.md) {
        RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
          .fill(MaxColor.surfaceStrong)
          .frame(width: 78, height: 78)
        VStack(alignment: .leading, spacing: MaxSpace.xs) {
          RoundedRectangle(cornerRadius: 4)
            .fill(MaxColor.surfaceStrong)
            .frame(height: 16)
          RoundedRectangle(cornerRadius: 4)
            .fill(MaxColor.surfaceStrong)
            .frame(width: 132, height: 12)
        }
        Spacer(minLength: 0)
      }
      .padding(MaxSpace.sm)
      .background(
        MaxColor.surface,
        in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
      )
      .redacted(reason: .placeholder)
    }
  }
}
