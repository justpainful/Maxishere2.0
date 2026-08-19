import Foundation
import SwiftUI

private enum SharedTopSection: String, CaseIterable, Identifiable {
  case collections
  case spaces

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .collections: "shared.segment.collections"
    case .spaces: "shared.segment.spaces"
    }
  }
}

private enum SharedFileFilter: String, CaseIterable, Identifiable {
  case all
  case received
  case sent

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .all: "shared.filter.all"
    case .received: "shared.filter.received"
    case .sent: "shared.filter.sent"
    }
  }
}

struct SharedView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette

  @State private var selectedSection: SharedTopSection = .collections
  @State private var fileFilter: SharedFileFilter = .all
  @State private var searchText = ""
  @State private var shareToChatItem: MaxMediaItem?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.lg) {
        SharedOverviewHeader(
          selection: $selectedSection,
          collectionCount: sharedCollectionCount,
          spaceCount: sharedSpaceCount
        )

        // Scoped to the switched content only: applied above `.maxTabContent()`
        // it also animated the atmosphere layer and the sheet presentation host.
        Group {
          switch selectedSection {
          case .collections:
            sharedCollectionsContent
          case .spaces:
            sharedSpacesContent
          }
        }
        .maxAnimation(MaxMotion.quick, value: selectedSection)
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.lg)
    }
    .navigationTitle("tab.shared")
    .navigationBarTitleDisplayMode(.large)
    .searchable(text: $searchText, prompt: Text(searchPrompt))
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        MaxAccessRequestsToolbarButton()
        Button("transfers.title", systemImage: "arrow.up.arrow.down") {
          model.openTransfers()
        }
        .accessibilityIdentifier("ui_shared_transfers")
      }
    }
    .refreshable { await refresh() }
    .task {
      guard !model.isUITestMode else { return }
      if model.libraryStore.phase.value == nil
          || model.libraryStore.catalogPhase.value == nil {
        await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
      }
      if model.chatStore.accessRequests.value == nil {
        await model.chatStore.loadAccessRequests()
      }
    }
    .sheet(item: $shareToChatItem) { item in
      ShareFileToChatSheet(item: item)
    }
    .maxTabContent()
    .councilLight(.shared)
    .accessibilityIdentifier("ui_shared_screen")
  }

  private var searchPrompt: LocalizedStringKey {
    switch selectedSection {
    case .collections: "shared.search.files"
    case .spaces: "shared.search"
    }
  }

  /// Number of collections, from the complete collections list.
  ///
  /// This chip used to count shared *files* while being labelled "Collections",
  /// and it counted them by filtering the one page of the catalogue the app had
  /// loaded — so it reported the page size, 100, however large the library was.
  /// Collections and spaces both arrive as complete lists, so counting them is
  /// both correct and honest.
  private var sharedCollectionCount: Int {
    model.libraryStore.phase.value?.collections.count ?? 0
  }

  private var sharedSpaceCount: Int {
    model.libraryStore.phase.value?.workspaces.count ?? 0
  }



  private func refresh() async {
    await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
    await model.chatStore.loadAccessRequests()
  }

  @ViewBuilder
  private var sharedCollectionsContent: some View {
    if let items = model.libraryStore.catalogPhase.value {
      Picker("shared.files.filter", selection: $fileFilter) {
        ForEach(SharedFileFilter.allCases) { filter in
          Text(filter.title)
            .tag(filter)
            .accessibilityIdentifier("ui_shared_filter_\(filter.rawValue)")
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("ui_shared_file_filter")

      let visible = filteredFiles(items)
      if visible.isEmpty {
        MaxEmptyState(
          title: searchText.isEmpty ? "shared.files.empty" : "search.empty.title",
          subtitle: searchText.isEmpty
            ? "shared.files.empty.subtitle"
            : "search.empty.subtitle",
          symbol: searchText.isEmpty ? "square.and.arrow.up.on.square" : "magnifyingglass"
        )
      } else {
        LazyVStack(spacing: MaxSpace.sm) {
          ForEach(visible) { item in
            SharedFileRow(
              item: item,
              currentUserID: model.sessionStore.user?.id,
              onSendToChat: { shareToChatItem = item }
            )
          }
        }
      }
    } else if model.libraryStore.catalogPhase.isLoading {
      ProgressView("shared.loading")
        .frame(maxWidth: .infinity)
        .padding(.vertical, MaxSpace.xl)
    } else if let error = model.libraryStore.catalogPhase.errorMessage {
      MaxLoadFailureView(message: error) {
        Task { await model.libraryStore.load(currentUserID: model.sessionStore.user?.id) }
      }
    } else {
      MaxEmptyState(
        title: "shared.files.empty",
        subtitle: "shared.files.empty.subtitle",
        symbol: "square.and.arrow.up.on.square"
      )
    }
  }

  @ViewBuilder
  private var sharedSpacesContent: some View {
    if let library = model.libraryStore.phase.value {
      let owned = filteredSpaces(library.workspaces.filter { workspace in
        workspace.ownerId == model.sessionStore.user?.id
      })
      let joined = filteredSpaces(library.workspaces.filter { workspace in
        workspace.ownerId != model.sessionStore.user?.id
      })

      if owned.isEmpty && joined.isEmpty {
        MaxEmptyState(
          title: searchText.isEmpty ? "shared.empty" : "search.empty.title",
          subtitle: searchText.isEmpty ? "shared.empty.subtitle" : "search.empty.subtitle",
          symbol: searchText.isEmpty ? "folder.fill" : "magnifyingglass"
        )
      } else {
        workspaceGroup(
          title: "shared.owned",
          subtitle: "shared.owned.subtitle",
          workspaces: owned
        )
        workspaceGroup(
          title: "shared.joined",
          subtitle: "shared.joined.subtitle",
          workspaces: joined
        )
      }
    } else if model.libraryStore.phase.isLoading {
      ProgressView("shared.loading")
        .frame(maxWidth: .infinity)
        .padding(.vertical, MaxSpace.xl)
    } else if let error = model.libraryStore.phase.errorMessage {
      MaxLoadFailureView(message: error) {
        Task { await model.libraryStore.load(currentUserID: model.sessionStore.user?.id) }
      }
    } else {
      MaxEmptyState(
        title: "shared.empty",
        subtitle: "shared.empty.subtitle",
        symbol: "folder.fill"
      )
    }
  }



  @ViewBuilder
  private func workspaceGroup(
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey,
    workspaces: [WorkspaceSummary]
  ) -> some View {
    if !workspaces.isEmpty {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        MaxSectionHeader(title: title, subtitle: subtitle)
        LazyVStack(spacing: MaxSpace.sm) {
          ForEach(workspaces) { workspace in
            NavigationLink {
              WorkspaceDetailView(workspace: workspace)
            } label: {
              WorkspaceRow(workspace: workspace)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_shared_space_\(workspace.id)")
          }
        }
      }
    }
  }

  private func filteredFiles(_ items: [MaxMediaItem]) -> [MaxMediaItem] {
    let currentUserID = model.sessionStore.user?.id
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    return items
      .filter { item in
        item.workspace != nil || item.uploader.id != currentUserID
      }
      .filter { item in
        switch fileFilter {
        case .all:
          true
        case .received:
          item.uploader.id != nil && item.uploader.id != currentUserID
        case .sent:
          item.uploader.id != nil && item.uploader.id == currentUserID
        }
      }
      .filter { item in
        guard !query.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(query)
          || (item.uploader.name ?? "").localizedCaseInsensitiveContains(query)
          || (item.workspace?.name ?? "").localizedCaseInsensitiveContains(query)
      }
      .sorted { ($0.uploadedAt ?? "") > ($1.uploadedAt ?? "") }
  }

  private func filteredSpaces(_ workspaces: [WorkspaceSummary]) -> [WorkspaceSummary] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return workspaces }
    return workspaces.filter {
      ($0.name ?? "").localizedCaseInsensitiveContains(query)
        || ($0.description ?? "").localizedCaseInsensitiveContains(query)
    }
  }
}

private struct SharedOverviewHeader: View {
  @Binding var selection: SharedTopSection
  let collectionCount: Int
  let spaceCount: Int

  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    MaxContentSurface(padding: 0) {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        HStack(alignment: .top, spacing: MaxSpace.md) {
          ZStack {
            Circle()
              .fill(
                LinearGradient(
                  colors: [palette.accent, MaxColor.periwinkle],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            Image(systemName: "folder.badge.person.crop.fill")
              .font(.title2.weight(.semibold))
              .foregroundStyle(palette.accentForeground)
          }
          .frame(width: 58, height: 58)

          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text("shared.eyebrow")
              .font(MaxTypography.eyebrow)
              .foregroundStyle(palette.accent)
            Text("tab.shared")
              .font(.title2.bold())
              .foregroundStyle(MaxColor.textPrimary)
            Text("shared.subtitle")
              .font(.subheadline)
              .foregroundStyle(MaxColor.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        HStack(spacing: MaxSpace.sm) {
          SharedCountChip(value: collectionCount, title: "shared.segment.collections", symbol: "rectangle.stack.fill")
          SharedCountChip(value: spaceCount, title: "shared.segment.spaces", symbol: "folder.fill")
        }

        Picker("shared.segment.title", selection: $selection) {
          ForEach(SharedTopSection.allCases) { section in
            Text(section.title)
              .tag(section)
              .accessibilityIdentifier("ui_shared_segment_\(section.rawValue)")
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("ui_shared_segment")
      }
      .padding(MaxSpace.md)
    }
  }
}

private struct SharedCountChip: View {
  let value: Int
  let title: LocalizedStringKey
  let symbol: String

  var body: some View {
    HStack(spacing: MaxSpace.xs) {
      Image(systemName: symbol)
        .foregroundStyle(MaxColor.accent)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: value.formatted())
          .font(.headline.monospacedDigit())
          .foregroundStyle(MaxColor.textPrimary)
        Text(title)
          .font(.caption2)
          .foregroundStyle(MaxColor.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
    .frame(maxWidth: .infinity)
    .background(
      MaxColor.surfaceSoft,
      in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
    )
  }
}

private struct SharedFileRow: View {
  @Environment(MaxAppModel.self) private var model

  let item: MaxMediaItem
  let currentUserID: String?
  let onSendToChat: () -> Void

  private var isSent: Bool {
    item.uploader.id != nil && item.uploader.id == currentUserID
  }

  private var counterpart: String {
    if isSent {
      return item.workspace?.name ?? String(localized: "shared.file.unknown_recipient")
    }
    return item.uploader.name ?? String(localized: "shared.file.unknown_sender")
  }

  var body: some View {
    MaxContentSurface(padding: MaxSpace.sm) {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        HStack(alignment: .top, spacing: MaxSpace.sm) {
          Button {
            model.openPlayer(for: item)
          } label: {
            MaxMediaPoster(item: item, compact: true, showsMetadata: false)
              .frame(width: 72, height: 72)
          }
          .buttonStyle(.plain)

          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text(verbatim: item.title)
              .font(.body.weight(.semibold))
              .foregroundStyle(MaxColor.textPrimary)
              .lineLimit(2)

            HStack(spacing: MaxSpace.xxs) {
              Text(isSent ? "shared.file.to" : "shared.file.from")
              Text(verbatim: counterpart)
            }
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .lineLimit(1)

            HStack(spacing: MaxSpace.xs) {
              SharedFileAccessBadge(item: item)
              if let date = SharedDateFormatting.formatted(item.uploadedAt) {
                Text(verbatim: date)
                  .font(.caption2)
                  .foregroundStyle(MaxColor.textTertiary)
              }
            }
          }

          Spacer(minLength: 0)
        }

        Divider()

        HStack(spacing: MaxSpace.xs) {
          Button("action.play", systemImage: "play.fill") {
            model.openPlayer(for: item)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("ui_shared_open_\(item.id)")

          Button("shared.action.send_to_chat", systemImage: "paperplane") {
            onSendToChat()
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("ui_shared_send_\(item.id)")

          MaxMediaSaveControl(item: item, presentation: .iconOnly)
          MaxMediaTransferControl(item: item, presentation: .iconOnly)

          Button("rating.title", systemImage: "star.bubble") {
            model.openRating(for: item)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("ui_shared_rate_\(item.id)")

          Spacer(minLength: 0)
        }
      }
    }
    .contextMenu {
      Button("action.play", systemImage: "play.fill") {
        model.openPlayer(for: item)
      }
      Button("shared.action.send_to_chat", systemImage: "paperplane") {
        onSendToChat()
      }
      Button(
        item.isFavorite || item.isSaved ? "action.unsave" : "action.save",
        systemImage: item.isFavorite || item.isSaved ? "heart.slash" : "heart"
      ) {
        Task { await model.toggleFavorite(item) }
      }
      if item.downloadable && model.transferStore.localURL(for: item) == nil {
        Button("action.download", systemImage: "arrow.down.circle") {
          Task { await model.transferStore.download(item) }
        }
      }
      Button("rating.title", systemImage: "star.bubble") {
        model.openRating(for: item)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ui_shared_file_\(item.id)")
  }
}

private struct SharedFileAccessBadge: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let item: MaxMediaItem

  var body: some View {
    Label(accessTitle, systemImage: accessSymbol)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(accessColor)
      .padding(.horizontal, MaxSpace.xs)
      .padding(.vertical, MaxSpace.xxs)
      .background(accessColor.opacity(0.12), in: Capsule())
  }

  private var accessTitle: LocalizedStringKey {
    if model.transferStore.localURL(for: item) != nil {
      return "shared.access.offline"
    }
    return item.downloadable ? "shared.access.downloadable" : "shared.access.view_only"
  }

  private var accessSymbol: String {
    if model.transferStore.localURL(for: item) != nil { return "checkmark.circle.fill" }
    return item.downloadable ? "arrow.down.circle" : "eye"
  }

  private var accessColor: Color {
    model.transferStore.localURL(for: item) != nil ? palette.success : MaxColor.accent
  }
}

private struct WorkspaceRow: View {
  let workspace: WorkspaceSummary

  var body: some View {
    MaxContentSurface(padding: MaxSpace.sm) {
      HStack(spacing: MaxSpace.md) {
        Image(systemName: workspace.spaceType == "private" ? "folder.fill.badge.minus" : "folder.fill.badge.person.crop")
          .font(.title2)
          .foregroundStyle(MaxColor.accent)
          .frame(width: 46, height: 46)
          .background(MaxColor.surfaceSoft, in: RoundedRectangle(cornerRadius: MaxRadius.small))

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: workspace.name ?? String(localized: "common.workspace"))
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
          if let description = workspace.description, !description.isEmpty {
            Text(verbatim: description)
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .lineLimit(1)
          }
          HStack(spacing: MaxSpace.xxs) {
            Image(systemName: "doc.on.doc")
            Text(verbatim: (workspace.itemCount ?? 0).formatted())
            Text("common.items")
          }
          .font(.caption2)
          .foregroundStyle(MaxColor.textTertiary)
        }

        Spacer(minLength: 0)
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
  }
}

private struct WorkspaceDetailView: View {
  @Environment(MaxAppModel.self) private var model

  let workspace: WorkspaceSummary

  @State private var searchText = ""
  @State private var shareToChatItem: MaxMediaItem?

  private let grid = [
    GridItem(.adaptive(minimum: 145, maximum: 220), spacing: MaxSpace.md)
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MaxSpace.lg) {
        workspaceHeader
        workspaceContent
      }
      .padding(MaxSpace.md)
    }
    .navigationTitle(workspace.name ?? String(localized: "common.workspace"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "shared.search.media")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("upload.title", systemImage: "square.and.arrow.up") {
          model.openUpload(
            destination: .workspace(
              id: workspace.id,
              name: workspace.name ?? String(localized: "common.workspace")
            )
          )
        }
        .accessibilityIdentifier("ui_shared_space_upload")

        Button("transfers.title", systemImage: "arrow.up.arrow.down") {
          model.openTransfers()
        }
      }
    }
    .refreshable {
      await model.libraryStore.loadWorkspaceMedia(workspaceID: workspace.id)
    }
    .task {
      guard !model.isUITestMode else { return }
      if model.libraryStore.workspaceMediaByID[workspace.id]?.value == nil {
        await model.libraryStore.loadWorkspaceMedia(workspaceID: workspace.id)
      }
    }
    .sheet(item: $shareToChatItem) { item in
      ShareFileToChatSheet(item: item)
    }
    .maxScreenBackground()
    .accessibilityIdentifier("ui_shared_space_detail")
  }

  @ViewBuilder
  private var workspaceHeader: some View {
    if let description = workspace.description, !description.isEmpty {
      Text(verbatim: description)
        .font(.body)
        .foregroundStyle(MaxColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    if let items = model.libraryStore.workspaceMediaByID[workspace.id]?.value {
      let members = visibleMembers(items)
      if !members.isEmpty {
        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          MaxSectionHeader(
            title: "shared.members",
            subtitle: "shared.members.visible.subtitle"
          )
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MaxSpace.md) {
              ForEach(members) { member in
                let isOwner = member.id == workspace.ownerId
                VStack(spacing: MaxSpace.xs) {
                  ZStack(alignment: .bottomTrailing) {
                    MaxAvatar(name: member.name, imageURL: member.avatarURL, size: 44)
                    if isOwner {
                      Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(3)
                        .background(MaxColor.surfaceStrong, in: Circle())
                        .offset(x: 4, y: 4)
                    }
                  }
                  Text(verbatim: member.name)
                    .font(.caption)
                    .lineLimit(1)
                }
                .frame(width: 72)
              }
            }
          }
        }
        .accessibilityIdentifier("ui_shared_space_members")
      }

      let recent = recentItems(items)
      if !recent.isEmpty {
        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          MaxSectionHeader(
            title: "shared.recent_files",
            subtitle: "shared.recent_files.subtitle"
          )
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: MaxSpace.md) {
              ForEach(recent) { item in
                Button { model.openPlayer(for: item) } label: {
                  MaxMediaPoster(item: item, compact: true, showsMetadata: true)
                    .frame(width: 168, height: 112)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ui_shared_recent_\(item.id)")
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var workspaceContent: some View {
    let phase = model.libraryStore.workspaceMediaByID[workspace.id] ?? .idle
    if let items = phase.value {
      let visible = filtered(items)
      if visible.isEmpty {
        MaxEmptyState(
          title: searchText.isEmpty ? "shared.media.empty" : "search.empty.title",
          subtitle: searchText.isEmpty ? "shared.media.empty.subtitle" : "search.empty.subtitle",
          symbol: searchText.isEmpty ? "person.2.crop.square.stack" : "magnifyingglass"
        )
      } else {
        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          MaxSectionHeader(
            title: "shared.space.files",
            subtitle: "shared.space.files.subtitle"
          )
          LazyVGrid(columns: grid, spacing: MaxSpace.lg) {
            ForEach(visible) { item in
              Button { model.openPlayer(for: item) } label: {
                MaxMediaTile(item: item)
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button("action.play", systemImage: "play.fill") {
                  model.openPlayer(for: item)
                }
                Button("shared.action.send_to_chat", systemImage: "paperplane") {
                  shareToChatItem = item
                }
                Button(
                  item.isFavorite || item.isSaved ? "action.unsave" : "action.save",
                  systemImage: item.isFavorite || item.isSaved ? "heart.slash" : "heart"
                ) {
                  Task { await model.toggleFavorite(item) }
                }
                if item.downloadable {
                  Button("action.download", systemImage: "arrow.down.circle") {
                    Task { await model.transferStore.download(item) }
                  }
                }
                Button("rating.title", systemImage: "star.bubble") {
                  model.openRating(for: item)
                }
              }
              .onAppear {
                guard item.id == visible.last?.id else { return }
                Task {
                  await model.libraryStore.loadMoreWorkspaceMedia(workspaceID: workspace.id)
                }
              }
              .accessibilityIdentifier("ui_shared_space_file_\(item.id)")
            }
          }
        }
      }
    } else if phase.isLoading {
      ProgressView("shared.loading")
        .frame(maxWidth: .infinity)
        .padding(.vertical, MaxSpace.xl)
    } else if let error = phase.errorMessage {
      MaxLoadFailureView(message: error) {
        Task { await model.libraryStore.loadWorkspaceMedia(workspaceID: workspace.id) }
      }
    } else {
      MaxEmptyState(
        title: "shared.media.empty",
        subtitle: "shared.media.empty.subtitle",
        symbol: "person.2.crop.square.stack"
      )
    }
  }

  private func filtered(_ items: [MaxMediaItem]) -> [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return items }
    return items.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || ($0.uploader.name ?? "").localizedCaseInsensitiveContains(query)
    }
  }

  private func recentItems(_ items: [MaxMediaItem]) -> [MaxMediaItem] {
    Array(items.sorted { ($0.uploadedAt ?? "") > ($1.uploadedAt ?? "") }.prefix(5))
  }

  private func visibleMembers(_ items: [MaxMediaItem]) -> [WorkspaceVisibleMember] {
    var seen = Set<String>()
    var members: [WorkspaceVisibleMember] = []

    if let user = model.sessionStore.user {
      seen.insert(user.id)
      members.append(
        WorkspaceVisibleMember(
          id: user.id,
          name: user.displayName,
          avatarURL: user.avatarUrl
        )
      )
    }

    members += items.compactMap { item in
      let name = item.uploader.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty else { return nil }
      let key = item.uploader.id ?? name.lowercased()
      guard seen.insert(key).inserted else { return nil }
      return WorkspaceVisibleMember(id: key, name: name, avatarURL: item.uploader.avatarUrl)
    }
    return members
  }
}

private struct WorkspaceVisibleMember: Identifiable {
  let id: String
  let name: String
  let avatarURL: URL?
}

private struct ShareFileToChatSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let item: MaxMediaItem

  @State private var caption = ""
  @State private var sendingThreadID: String?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: MaxSpace.md) {
            MaxMediaPoster(item: item, compact: true, showsMetadata: false)
              .frame(width: 76, height: 64)
            VStack(alignment: .leading, spacing: MaxSpace.xxs) {
              Text(verbatim: item.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
              Text(verbatim: item.sizeBytes.byteString)
                .font(.caption)
                .foregroundStyle(MaxColor.textSecondary)
            }
          }
        }

        Section("shared.share.caption") {
          TextField("chat.composer.placeholder", text: $caption, axis: .vertical)
            .lineLimit(1...4)
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier("ui_shared_share_caption")
        }

        Section("shared.share.chats") {
          if let threads = model.chatStore.threads.value {
            if threads.isEmpty {
              Text("chats.empty.title")
                .foregroundStyle(MaxColor.textSecondary)
            } else {
              ForEach(threads) { thread in
                Button {
                  send(to: thread)
                } label: {
                  HStack(spacing: MaxSpace.md) {
                    MaxAvatar(name: thread.title, imageURL: thread.avatarUrl, size: 38)
                    Text(verbatim: thread.title)
                      .foregroundStyle(MaxColor.textPrimary)
                    Spacer(minLength: 0)
                    if sendingThreadID == thread.id {
                      ProgressView().controlSize(.small)
                    } else {
                      Image(systemName: "paperplane")
                        .foregroundStyle(MaxColor.accent)
                    }
                  }
                }
                .disabled(sendingThreadID != nil)
                .accessibilityIdentifier("ui_shared_share_chat_\(thread.id)")
              }
            }
          } else if model.chatStore.threads.isLoading {
            HStack(spacing: MaxSpace.sm) {
              ProgressView()
              Text("chats.loading")
            }
          } else if let error = model.chatStore.threads.errorMessage {
            VStack(alignment: .leading, spacing: MaxSpace.sm) {
              Text(verbatim: error)
                .font(.caption)
                .foregroundStyle(MaxColor.danger)
              Button("common.retry") {
                Task { await model.chatStore.loadThreads(loadSelectedMessages: false) }
              }
            }
          }
        }

        if let errorMessage {
          Section {
            Label {
              Text(verbatim: errorMessage)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(MaxColor.danger)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("shared.share.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
            .disabled(sendingThreadID != nil)
        }
      }
      .task {
        guard !model.isUITestMode,
              model.chatStore.threads.value == nil else { return }
        await model.chatStore.loadThreads(loadSelectedMessages: false)
      }
      .interactiveDismissDisabled(sendingThreadID != nil)
      .maxScreenBackground()
      .accessibilityIdentifier("ui_shared_share_sheet")
    }
    .presentationDetents([.medium, .large])
  }

  private func send(to thread: ChatThread) {
    sendingThreadID = thread.id
    errorMessage = nil
    Task {
      let sent = await model.chatStore.sendMessage(
        to: thread.id,
        content: caption,
        mediaFileIDs: [item.id]
      )
      sendingThreadID = nil
      if sent != nil {
        dismiss()
      } else {
        errorMessage = model.chatStore.sendStateByChat[thread.id]?.errorMessage
          ?? String(localized: "chat.send.failed")
      }
    }
  }
}

private enum SharedDateFormatting {
  static func formatted(_ value: String?) -> String? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date: Date?
    if let fractionalDate = formatter.date(from: value) {
      date = fractionalDate
    } else {
      formatter.formatOptions = [.withInternetDateTime]
      date = formatter.date(from: value)
    }
    return date?.formatted(date: .abbreviated, time: .shortened)
  }
}
