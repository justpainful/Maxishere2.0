import SwiftUI

private struct LegacyVaultDashboardView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var selectedSource: String?

  private let grid = [
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm),
    GridItem(.flexible(minimum: 0), spacing: MaxSpace.sm),
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.xl) {
        quickActions
        
        PluginExtensionPointView(pointId: "home:afterHero")
        
        activeTransferSection
        continueWatchingSection
        personalFilesSection
        collectionsSection
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.lg)
    }
    .navigationTitle("tab.vault")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: searchBinding,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "vault.search"
    )
    .searchSuggestions {
      if !model.homeStore.query.search.isEmpty {
        Text("home.search.suggestion")
          .searchCompletion(model.homeStore.query.search)
      }
    }
    .onSubmit(of: .search) { reloadBrowse() }
    .toolbar { vaultToolbar }
    .refreshable { await loadVault(force: true) }
    .task {
      guard !model.isUITestMode else { return }
      let needsHome = model.homeStore.overview.value == nil
      let needsLibrary = model.libraryStore.phase.value == nil
      guard needsHome || needsLibrary else { return }
      await loadVault(force: false)
    }
    .maxTabContent()
    .councilLight(.home)
    .accessibilityIdentifier("ui_vault_screen")
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { model.homeStore.query.search },
      set: { model.homeStore.query.search = $0 }
    )
  }

  private var kindBinding: Binding<String> {
    Binding(
      get: { model.homeStore.query.kind ?? "all" },
      set: { value in
        model.homeStore.query.kind = value == "all" ? nil : value
        reloadBrowse()
      }
    )
  }

  private var quickActions: some View {
    let isCouncil = appTheme == .council
    return VStack(alignment: .leading, spacing: MaxSpace.sm) {
      Text("vault.quick_actions")
        .font(isCouncil ? CouncilTypography.headline : .headline)
        .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.primaryText) : AnyShapeStyle(MaxColor.textPrimary))

      Grid(horizontalSpacing: MaxSpace.xs) {
        GridRow {
          if isCouncil {
            Button {
              model.openUpload(destination: .personal)
            } label: {
              Label("upload.title", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(CouncilColor.primaryText)
                .background(CouncilColor.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(CouncilColor.activeCrimson.opacity(0.40), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_vault_upload")

            Button {
              openShuffledItem()
            } label: {
              Label("vault.shuffle", systemImage: "shuffle")
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(shuffleCandidates.isEmpty ? CouncilColor.disabled : CouncilColor.primaryText)
                .background(CouncilColor.stoneSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(CouncilColor.quietBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(shuffleCandidates.isEmpty)
            .accessibilityIdentifier("ui_vault_shuffle")

            NavigationLink {
              LibraryView()
            } label: {
              Label("tab.library", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(CouncilColor.primaryText)
                .background(CouncilColor.stoneSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(CouncilColor.quietBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_vault_open_library")
          } else {
            Button {
              model.openUpload(destination: .personal)
            } label: {
              Label("upload.title", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("ui_vault_upload")

            Button {
              openShuffledItem()
            } label: {
              Label("vault.shuffle", systemImage: "shuffle")
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glass)
            .disabled(shuffleCandidates.isEmpty)
            .accessibilityIdentifier("ui_vault_shuffle")

            NavigationLink {
              LibraryView()
            } label: {
              Label("tab.library", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("ui_vault_open_library")
          }
        }
      }
      .labelStyle(.titleAndIcon)
      .font(.subheadline.weight(.semibold))
    }
  }

  @ViewBuilder
  private var activeTransferSection: some View {
    if let transfer = model.transferStore.activeRecords.first {
      Button {
        model.openTransfers()
      } label: {
        MaxLibraryTransferRow(record: transfer)
      }
      .buttonStyle(.plain)
      .accessibilityHint(Text("transfers.open_active"))
      .accessibilityIdentifier("ui_vault_active_transfer")
    }
  }

  @ViewBuilder
  private var continueWatchingSection: some View {
    let items = continueWatchingItems
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: "home.section.continue")

        ScrollView(.horizontal) {
          LazyHStack(spacing: MaxSpace.md) {
            ForEach(items) { item in
              Button {
                model.openPlayer(for: item)
              } label: {
                MaxVaultContinueCard(
                  item: item,
                  isOffline: model.transferStore.localURL(for: item) != nil
                )
              }
              .buttonStyle(.plain)
              .contextMenu { mediaContextMenu(for: item) }
              .accessibilityIdentifier("ui_vault_continue_\(item.id)")
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  @ViewBuilder
  private var personalFilesSection: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "vault.personal")
      sourceFilters

      if model.libraryStore.personalPhase.isLoading && personalItems.isEmpty {
        MaxVaultGridSkeleton(grid: grid)
      } else if let error = model.libraryStore.personalPhase.errorMessage,
                personalItems.isEmpty {
        MaxLoadFailureView(message: error) {
          Task { await loadVault(force: true) }
        }
      } else if personalItems.isEmpty {
        if appTheme == .council {
          CouncilEmptyState(
            symbol: model.homeStore.query.search.isEmpty ? "archivebox" : "magnifyingglass",
            title: model.homeStore.query.search.isEmpty ? "vault.personal.empty" : "search.empty.title",
            subtitle: model.homeStore.query.search.isEmpty ? "vault.personal.empty.subtitle" : "search.empty.subtitle",
            actionTitle: "upload.title",
            action: { model.openUpload(destination: .personal) }
          )
        } else {
          VStack(spacing: MaxSpace.md) {
            MaxEmptyState(
              title: model.homeStore.query.search.isEmpty
                ? "vault.personal.empty"
                : "search.empty.title",
              subtitle: model.homeStore.query.search.isEmpty
                ? "vault.personal.empty.subtitle"
                : "search.empty.subtitle",
              symbol: model.homeStore.query.search.isEmpty
                ? "archivebox"
                : "magnifyingglass"
            )

            Button {
              model.openUpload(destination: .personal)
            } label: {
              Label("upload.title", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glassProminent)
          }
        }
      } else {
        // Each tile takes the shape of its own media; a shared cell height would
        // crop every item that is not the grid's assumed orientation.
        MaxMediaMasonry(
          items: personalItems,
          columnCount: 2,
          spacing: MaxSpace.sm,
          aspectRatio: { $0.aspectRatio }
        ) { item in
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
          .contextMenu { mediaContextMenu(for: item) }
          .accessibilityIdentifier("ui_vault_media_\(item.id)")
        }
      }
    }
  }

  @ViewBuilder
  private var sourceFilters: some View {
    if sourceNames.count > 1 {
      ScrollView(.horizontal) {
        HStack(spacing: MaxSpace.xs) {
          Button {
            withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
              selectedSource = nil
            }
          } label: {
            MaxChip(title: "home.filter.all", isSelected: selectedSource == nil)
          }
          .buttonStyle(.plain)

          ForEach(sourceNames, id: \.self) { source in
            Button {
              withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
                selectedSource = selectedSource == source ? nil : source
              }
            } label: {
              Text(verbatim: source)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                  selectedSource == source ? palette.accentForeground : palette.primaryText
                )
                .padding(.horizontal, MaxSpace.sm)
                .padding(.vertical, MaxSpace.xs)
                .background(
                  selectedSource == source ? palette.accent : palette.selectedControl,
                  in: Capsule()
                )
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)
      .accessibilityIdentifier("ui_vault_source_filters")
    }
  }

  @ViewBuilder
  private var collectionsSection: some View {
    if let collections = model.libraryStore.phase.value?.collections,
       !collections.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: "vault.collections")

        ScrollView(.horizontal) {
          LazyHStack(spacing: MaxSpace.md) {
            ForEach(collections) { collection in
              NavigationLink {
                MaxCollectionDetailView(collection: collection)
              } label: {
                MaxVaultCollectionCard(collection: collection)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  @ToolbarContentBuilder
  private var vaultToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Picker("home.filter.kind", selection: kindBinding) {
          Text("home.filter.all")
            .tag("all")
            .accessibilityIdentifier("ui_vault_filter_all")
          Text("media.kind.video")
            .tag("video")
            .accessibilityIdentifier("ui_vault_filter_video")
          Text("media.kind.media")
            .tag("image")
            .accessibilityIdentifier("ui_vault_filter_image")
        }

        Toggle(
          "home.filter.unwatched",
          isOn: Binding(
            get: { model.homeStore.query.unwatched },
            set: { value in
              model.homeStore.query.unwatched = value
              reloadBrowse()
            }
          )
        )
        .accessibilityIdentifier("ui_vault_filter_unwatched")

        Toggle(
          "home.filter.unrated",
          isOn: Binding(
            get: { model.homeStore.query.unrated },
            set: { value in
              model.homeStore.query.unrated = value
              reloadBrowse()
            }
          )
        )
        .accessibilityIdentifier("ui_vault_filter_unrated")
      } label: {
        Label("home.filters", systemImage: "line.3.horizontal.decrease")
      }
      .accessibilityIdentifier("ui_vault_filters")
    }
  }

  private var personalItems: [MaxMediaItem] {
    let hasRemoteQuery = !model.homeStore.query.search.isEmpty
      || model.homeStore.query.kind != nil
      || model.homeStore.query.unwatched
      || model.homeStore.query.unrated

    let candidates: [MaxMediaItem]
    if hasRemoteQuery, let results = model.homeStore.filteredFeed.value {
      candidates = results
    } else {
      candidates = model.libraryStore.personalItems
    }

    let userID = model.sessionStore.user?.id
    let personal = candidates.filter { item in
      guard let userID, !userID.isEmpty else { return true }
      return item.uploader.id == userID
    }

    let search = model.homeStore.query.search
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let locallyFiltered = personal.filter { item in
      let matchesSearch = search.isEmpty
        || item.title.localizedCaseInsensitiveContains(search)
        || (item.workspace?.name?.localizedCaseInsensitiveContains(search) ?? false)
        || (item.uploader.name?.localizedCaseInsensitiveContains(search) ?? false)
      let matchesKind = model.homeStore.query.kind.map { item.kind == $0 } ?? true
      let matchesWatch = !model.homeStore.query.unwatched || !item.hasProgress
      let matchesRating = !model.homeStore.query.unrated || item.rating == nil
      let matchesSource = selectedSource == nil || sourceName(for: item) == selectedSource
      return matchesSearch && matchesKind && matchesWatch && matchesRating && matchesSource
    }

    return MaxLibrarySort.recent.apply(to: locallyFiltered)
  }

  private var continueWatchingItems: [MaxMediaItem] {
    var seen = Set<String>()
    var candidates = model.homeStore.overview.value?.browse ?? []
    candidates += model.homeStore.filteredFeed.value ?? []
    candidates += model.libraryStore.personalItems

    return candidates
      .filter { $0.kind == "video" && $0.hasProgress && seen.insert($0.id).inserted }
      .sorted { ($0.lastViewedAt ?? "") > ($1.lastViewedAt ?? "") }
      .prefix(8)
      .map { $0 }
  }

  private var shuffleCandidates: [MaxMediaItem] {
    let shuffled = model.homeStore.overview.value?.shuffle ?? []
    return shuffled.isEmpty ? personalItems : shuffled
  }

  private var sourceNames: [String] {
    Set(model.libraryStore.personalItems.compactMap { sourceName(for: $0) })
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private func loadVault(force: Bool) async {
    let userID = model.sessionStore.user?.id
    async let home: Void = model.homeStore.loadOverview()
    async let library: Void = model.libraryStore.load(currentUserID: userID)
    _ = await (home, library)

    guard force || model.homeStore.selectedMode != "browse" else { return }
    model.homeStore.selectedMode = "browse"
    await model.homeStore.loadFeed()
  }

  private func reloadBrowse() {
    model.homeStore.selectedMode = "browse"
    Task { await model.homeStore.loadFeed() }
  }

  private func openShuffledItem() {
    guard let item = shuffleCandidates.randomElement() else { return }
    model.openPlayer(for: item)
  }

  private func sourceName(for item: MaxMediaItem) -> String? {
    item.workspace?.name ?? item.uploader.name
  }

  @ViewBuilder
  private func mediaContextMenu(for item: MaxMediaItem) -> some View {
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

struct MaxLoadFailureView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("common.error", systemImage: "exclamationmark.triangle")
    } description: {
      Text(verbatim: message)
    } actions: {
      Button("common.retry", action: retry)
        .buttonStyle(.glassProminent)
    }
  }
}

private struct MaxVaultCollectionCard: View {
  let collection: CollectionSummary

  var body: some View {
    MaxContentSurface(padding: MaxSpace.md) {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        ZStack {
          RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            .fill(
              LinearGradient(
                colors: [MaxColor.sky.opacity(0.68), MaxColor.periwinkle.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          Image(systemName: "rectangle.stack.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(height: 92)

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: collection.name ?? String(localized: "common.collection"))
            .font(.headline)
            .foregroundStyle(MaxColor.textPrimary)
            .lineLimit(2)
          // The API does not send a count yet. Printing "0 items" for every
          // collection reads as "this collection is empty", which is worse than
          // saying nothing until the field exists.
          if let itemCount = collection.itemCount {
            HStack(spacing: MaxSpace.xxs) {
              Text(verbatim: itemCount.formatted())
              Text("common.items")
            }
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
          }
        }
      }
      .frame(width: 190, alignment: .leading)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct MaxVaultGridSkeleton: View {
  let grid: [GridItem]

  var body: some View {
    LazyVGrid(columns: grid, spacing: MaxSpace.sm) {
      ForEach(0..<6, id: \.self) { _ in
        RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
          .fill(MaxColor.surfaceStrong)
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .redacted(reason: .placeholder)
      }
    }
    .accessibilityLabel(Text("loading.media"))
  }
}
