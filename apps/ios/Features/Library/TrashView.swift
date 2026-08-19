import Foundation
import SwiftUI

/// The Trash screen: media the user soft-deleted, recoverable for 30 days.
/// Each item can be restored or permanently deleted; the whole bin can be
/// emptied at once. Talks to LibraryStore, which fronts /api/v2/media/trash.
struct TrashView: View {
  @Environment(MaxAppModel.self) private var model

  @State private var pendingPurge: TrashedMedia?
  @State private var isEmptyingConfirmation = false
  @State private var banner: TrashBanner?
  @State private var isEmptying = false

  private var store: LibraryStore { model.libraryStore }
  private var items: [TrashedMedia] { store.trashedItems }

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
    .toolbar {
      if !items.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button(role: .destructive) {
            isEmptyingConfirmation = true
          } label: {
            Text("trash.empty.action")
          }
          .disabled(isEmptying)
        }
      }
    }
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
    var blocked = 0
    for item in items {
      if await store.purge(item) == .inUse { blocked += 1 }
    }
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
  let onRestore: () -> Void
  let onDelete: () -> Void

  var body: some View {
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
    .contextMenu {
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
