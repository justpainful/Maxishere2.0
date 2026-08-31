import Foundation
import SwiftUI

/// The Trash screen: media the user soft-deleted, recoverable for 30 days.
/// Each item can be restored or permanently deleted; the whole bin can be
/// emptied at once. Talks to LibraryStore, which fronts /api/v2/media/trash.
struct TrashView: View {
  @Environment(MaxAppModel.self) private var model

  @State private var pendingPurge: TrashedMedia?
  @State private var isEmptyingConfirmation = false
  @State private var isRestoreAllConfirmation = false
  @State private var isPurgeSelectedConfirmation = false
  @State private var banner: TrashBanner?
  @State private var isEmptying = false
  @State private var isSelecting = false
  @State private var selection: Set<String> = []
  @State private var sort: TrashSort = .recent

  private var store: LibraryStore { model.libraryStore }
  private var items: [TrashedMedia] { sort.apply(to: store.trashedItems) }
  private var selectedItems: [TrashedMedia] { items.filter { selection.contains($0.id) } }
  private var selectedBytes: Int { selectedItems.reduce(0) { $0 + $1.media.sizeBytes } }
  private var isAllSelected: Bool { !items.isEmpty && selection.count == items.count }
  private var isBusy: Bool { isEmptying }

  private var purgeAlertPresented: Binding<Bool> {
    Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } })
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: MaxSpace.sm) {
        content
      }
      .frame(maxWidth: .infinity)
      .padding(MaxSpace.md)
    }
    .navigationTitle("library.trash")
    .navigationBarTitleDisplayMode(.inline)
    // An explicit ToolbarContent builder, and every action a closure: a bare
    // `if` here, or a bare method reference passed as an action, is reported as
    // an ambiguous `toolbar(content:)` on a later modifier rather than where the
    // problem is.
    .toolbar { toolbarContent }
    .refreshable { await store.loadTrash() }
    .task {
      guard !model.isUITestMode, store.trashPhase.value == nil else { return }
      await store.loadTrash()
    }
    .maxScreenBackground()
    .safeAreaInset(edge: .top) { bannerView }
    .alert(
      "trash.purge.title",
      isPresented: purgeAlertPresented,
      presenting: pendingPurge
    ) { item in
      Button("trash.delete", role: .destructive) { Task { await purge(item) } }
      Button("common.cancel", role: .cancel) {}
    } message: { item in
      // Formatted rather than interpolated into the key: interpolation builds a
      // lookup name that carries the format specifier with it.
      Text(String(format: String(localized: "trash.purge.message"), item.media.displayTitle))
    }
    .confirmationDialog(
      "trash.empty.title",
      isPresented: $isEmptyingConfirmation,
      titleVisibility: .visible
    ) {
      Button("trash.empty.confirm", role: .destructive) { Task { await emptyTrash() } }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("trash.empty.message")
    }
    .confirmationDialog(
      "trash.restore_all",
      isPresented: $isRestoreAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("trash.restore") { Task { await restoreEverything() } }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("trash.restore_all.message")
    }
    .confirmationDialog(
      "trash.purge.title",
      isPresented: $isPurgeSelectedConfirmation,
      titleVisibility: .visible
    ) {
      Button("trash.delete", role: .destructive) { Task { await purgeSelected() } }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text(String(format: String(localized: "trash.purge_selected.message"), selection.count))
    }
    .safeAreaInset(edge: .bottom) { selectionBar }
    .accessibilityIdentifier("ui_trash_screen")
  }

  @ViewBuilder
  private var content: some View {
    if store.trashPhase.isLoading && items.isEmpty {
      ProgressView()
        .controlSize(.large)
        .frame(maxWidth: .infinity, minHeight: 240)
    } else if let error = store.trashPhase.errorMessage, items.isEmpty {
      MaxLoadFailureView(message: error) {
        Task { await store.loadTrash() }
      }
    } else if items.isEmpty {
      MaxEmptyState(
        title: "library.trash.empty",
        subtitle: "library.trash.empty.subtitle",
        symbol: "trash"
      )
      .padding(.top, MaxSpace.xl)
    } else {
      ForEach(items) { item in
        TrashRow(
          item: item,
          isSelecting: isSelecting,
          isSelected: selection.contains(item.id),
          onToggleSelect: { toggle(item) },
          onRestore: { Task { await restore(item) } },
          onDelete: { pendingPurge = item }
        )
        .onAppear {
          if item.id == items.last?.id { Task { await store.loadMoreTrash() } }
        }
        .accessibilityIdentifier("ui_trash_item_\(item.id)")
      }

      if store.hasMoreTrash {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, MaxSpace.sm)
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      if items.isEmpty {
        // An empty Trash has nothing to sort, select or empty.
        EmptyView()
      } else {
        Menu {
          Picker("trash.sort", selection: $sort) {
            ForEach(TrashSort.allCases) { option in
              Label(option.title, systemImage: option.symbol).tag(option)
            }
          }
          Divider()
          Button {
            withAnimation(.snappy) {
              isSelecting.toggle()
              if !isSelecting { selection.removeAll() }
            }
          } label: {
            if isSelecting {
              Label("common.cancel", systemImage: "checkmark.circle")
            } else {
              Label("trash.select", systemImage: "checkmark.circle")
            }
          }
          Button { isRestoreAllConfirmation = true } label: {
            Label("trash.restore_all", systemImage: "arrow.uturn.backward")
          }
          Divider()
          Button(role: .destructive) { isEmptyingConfirmation = true } label: {
            Label("trash.empty.action", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .disabled(isBusy)
        .accessibilityIdentifier("ui_trash_menu")
      }
    }
  }

  /// The one place the Trash speaks about a group rather than a row, so it sits
  /// in a bar of its own rather than pretending to be another list item.
  @ViewBuilder
  private var selectionBar: some View {
    if isSelecting && !items.isEmpty {
      HStack(spacing: MaxSpace.sm) {
        Button {
          withAnimation(.snappy) {
            selection = isAllSelected ? Set<String>() : Set(items.map(\.id))
          }
        } label: {
          Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
        }
        .accessibilityLabel("trash.select_all")

        VStack(alignment: .leading, spacing: 1) {
          Text(
            verbatim: selection.isEmpty
              ? String(localized: "trash.select_all")
              : String(format: String(localized: "trash.selected"), selection.count)
          )
          .font(.subheadline.weight(.medium))
          if !selection.isEmpty {
            Text(verbatim: selectedBytes.byteString)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: MaxSpace.xs)

        Button { Task { await restoreSelected() } } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .tint(MaxColor.accent)
        .disabled(selection.isEmpty || isBusy)

        Button(role: .destructive) { isPurgeSelectedConfirmation = true } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(selection.isEmpty || isBusy)
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.sm)
      .background(.bar)
      .accessibilityIdentifier("ui_trash_selection_bar")
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  private func toggle(_ item: TrashedMedia) {
    if selection.contains(item.id) {
      selection.remove(item.id)
    } else {
      selection.insert(item.id)
    }
  }

  private func restoreSelected() async {
    let targets = selectedItems
    guard !targets.isEmpty else { return }
    isEmptying = true
    defer { isEmptying = false }
    let failed = await store.restore(targets)
    selection.removeAll()
    if failed > 0 {
      flash(TrashBanner(message: String(localized: "trash.error.restore"), isError: true))
    } else {
      flash(
        TrashBanner(
          message: String(format: String(localized: "trash.restored"), targets.count),
          isError: false
        )
      )
    }
  }

  private func purgeSelected() async {
    let targets = selectedItems
    guard !targets.isEmpty else { return }
    isEmptying = true
    defer { isEmptying = false }
    let result = await store.purge(targets)
    selection.removeAll()
    if result.blocked > 0 {
      flash(
        TrashBanner(
          message: String(format: String(localized: "trash.error.kept"), result.blocked),
          isError: true
        )
      )
    } else {
      flash(
        TrashBanner(
          message: String(format: String(localized: "trash.deleted"), result.purged),
          isError: false
        )
      )
    }
  }

  private func restoreEverything() async {
    isEmptying = true
    defer { isEmptying = false }
    await store.loadAllTrash()
    let all = store.trashedItems
    let failed = await store.restore(all)
    withAnimation(.snappy) {
      isSelecting = false
      selection.removeAll()
    }
    if failed > 0 {
      flash(TrashBanner(message: String(localized: "trash.error.restore"), isError: true))
    } else {
      flash(
        TrashBanner(
          message: String(format: String(localized: "trash.restored"), all.count),
          isError: false
        )
      )
    }
  }

  @ViewBuilder
  private var bannerView: some View {
    if let banner {
      Text(banner.message)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, MaxSpace.md)
        .padding(.vertical, MaxSpace.sm)
        .frame(maxWidth: .infinity)
        .background(banner.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private func restore(_ item: TrashedMedia) async {
    let ok = await store.restore(item)
    if !ok {
      flash(TrashBanner(message: String(localized: "trash.error.restore"), isError: true))
    }
  }

  private func purge(_ item: TrashedMedia) async {
    switch await store.purge(item) {
    case .purged:
      break
    case .inUse:
      flash(TrashBanner(message: String(localized: "trash.error.in_use"), isError: true))
    case .failed:
      flash(TrashBanner(message: String(localized: "trash.error.delete"), isError: true))
    }
  }

  private func emptyTrash() async {
    isEmptying = true
    defer { isEmptying = false }
    // Only the page on screen used to be purged, while the user was told the
    // Trash had been emptied.
    await store.loadAllTrash()
    let blocked = await store.purge(store.trashedItems).blocked
    if blocked > 0 {
      flash(
        TrashBanner(
          message: String(format: String(localized: "trash.error.kept"), blocked),
          isError: true
        )
      )
    }
  }

  private func flash(_ banner: TrashBanner) {
    withAnimation(.snappy) { self.banner = banner }
    Task {
      try? await Task.sleep(for: .seconds(3))
      withAnimation(.snappy) { self.banner = nil }
    }
  }
}

private struct TrashBanner: Identifiable, Equatable {
  let id = UUID()
  let message: String
  let isError: Bool
}

/// One trashed item: the media preview, a purge countdown, and inline
/// Restore / Delete actions (also available via long-press context menu).
private struct TrashRow: View {
  let item: TrashedMedia
  let isSelecting: Bool
  let isSelected: Bool
  let onToggleSelect: () -> Void
  let onRestore: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      if isSelecting {
        Button(action: onToggleSelect) {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? MaxColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityIdentifier("ui_trash_select_\(item.id)")
        .accessibilityLabel(item.media.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
      rowBody
    }
    // In selection mode the whole row is the target: reaching for a 44pt circle
    // beside every item is not how anyone selects a list on a phone.
    .contentShape(.rect)
    .onTapGesture { if isSelecting { onToggleSelect() } }
  }

  private var rowBody: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      MaxLibraryMediaRow(item: item.media, showsSavedState: false, isOffline: false)

      HStack(spacing: MaxSpace.sm) {
        Label {
          Text(countdownText)
        } icon: {
          Image(systemName: "clock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer(minLength: MaxSpace.sm)

        // Per-row commands would compete with the selection for the same tap.
        if !isSelecting {
          Button(action: onRestore) {
            Label("trash.restore", systemImage: "arrow.uturn.backward")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(MaxColor.accent)

          Button(role: .destructive, action: onDelete) {
            Label("trash.delete", systemImage: "trash")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
    .contextMenu {
      Button(action: onToggleSelect) {
        if isSelected {
          Label("trash.deselect", systemImage: "xmark")
        } else {
          Label("trash.select", systemImage: "checkmark")
        }
      }
      Button(action: onRestore) {
        Label("trash.restore", systemImage: "arrow.uturn.backward")
      }
      Button(role: .destructive, action: onDelete) {
        Label("trash.delete.permanently", systemImage: "trash")
      }
    }
  }

  private var countdownText: String {
    guard let days = item.daysUntilPurge else {
      return String(localized: "trash.countdown.scheduled")
    }
    if days == 0 { return String(localized: "trash.countdown.today") }
    if days == 1 { return String(localized: "trash.countdown.day") }
    return String(format: String(localized: "trash.countdown.days"), days)
  }
}

/// How the Trash is ordered.
///
/// `recent` is the server's own order - most recently deleted first - and stays
/// the default so the list does not rearrange itself under someone who did not
/// ask it to. Sorting applies to what has been paged in, which is the same list
/// the viewer can see.
enum TrashSort: String, CaseIterable, Identifiable, Sendable {
  case recent, largest, smallest, soonest, title

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .recent: "trash.sort.recent"
    case .largest: "trash.sort.largest"
    case .smallest: "trash.sort.smallest"
    case .soonest: "trash.sort.soonest"
    case .title: "trash.sort.title"
    }
  }

  var symbol: String {
    switch self {
    case .recent: "clock"
    case .largest: "arrow.down"
    case .smallest: "arrow.up"
    case .soonest: "hourglass"
    case .title: "textformat"
    }
  }

  func apply(to items: [TrashedMedia]) -> [TrashedMedia] {
    switch self {
    case .recent:
      return items
    case .largest:
      return items.sorted { $0.media.sizeBytes > $1.media.sizeBytes }
    case .smallest:
      return items.sorted { $0.media.sizeBytes < $1.media.sizeBytes }
    case .soonest:
      // Items with no scheduled removal are not urgent, so they sink.
      return items.sorted { ($0.daysUntilPurge ?? .max) < ($1.daysUntilPurge ?? .max) }
    case .title:
      return items.sorted {
        $0.media.displayTitle.localizedStandardCompare($1.media.displayTitle) == .orderedAscending
      }
    }
  }
}
