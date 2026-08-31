import SwiftUI

/// The Clips shelf: every saved range the user has clipped, newest first.
/// Each row is a RANGE of a media item, stored as data — playing one opens the
/// ordinary player with enforced bounds, deleting one deletes nothing but the
/// row. Clips are created inside the player with the scissors button.
struct ClipsLibraryView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var toast: String?
  @State private var toastTask: Task<Void, Never>?

  private var store: ClipsStore { model.clipsStore }
  private var clips: [MediaClip] { store.shelf ?? [] }

  var body: some View {
    Group {
      if store.isShelfLoading && clips.isEmpty {
        ProgressView()
          .controlSize(.large)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if clips.isEmpty {
        ScrollView {
          MaxEmptyState(
            title: "No clips yet",
            subtitle: "Save a range from the player with the scissors button.",
            symbol: "scissors"
          )
          .padding(.top, MaxSpace.xl)
          .frame(maxWidth: .infinity)
        }
      } else {
        List {
          ForEach(clips) { clip in
            Button {
              play(clip)
            } label: {
              ClipShelfRow(clip: clip, source: source(for: clip))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(
              top: MaxSpace.xs,
              leading: MaxSpace.md,
              bottom: MaxSpace.xs,
              trailing: MaxSpace.md
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button(role: .destructive) {
                delete(clip)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
            .contextMenu {
              Button("Play", systemImage: "play.fill") { play(clip) }
              Divider()
              Button("Export as Video", systemImage: "square.and.arrow.up") {
                export(clip, format: "mp4")
              }
              Button("Export as GIF", systemImage: "photo") {
                export(clip, format: "gif")
              }
              Divider()
              Button(role: .destructive) {
                delete(clip)
              } label: {
                Label("Delete clip", systemImage: "trash")
              }
            }
            .accessibilityIdentifier("ui_clips_item_\(clip.id)")
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .navigationTitle("Clips")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await store.loadShelf() }
    .task {
      guard !model.isUITestMode, store.shelf == nil else { return }
      await store.loadShelf()
    }
    .maxScreenBackground()
    .overlay(alignment: .bottom) {
      if let toast {
        Text(verbatim: toast)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .padding(.horizontal, MaxSpace.md)
          .padding(.vertical, MaxSpace.sm)
          .background(.regularMaterial, in: Capsule())
          .padding(.bottom, MaxSpace.xl)
          .transition(.opacity)
          .accessibilityIdentifier("ui_clips_toast")
      }
    }
    .accessibilityIdentifier("ui_clips_screen")
  }

  /// Queues a server-side export and confirms with a brief toast — the worker
  /// does the rendering, so there is nothing further to wait on here.
  private func export(_ clip: MediaClip, format: String) {
    Task {
      do {
        _ = try await model.apiClient.exportClip(clipID: clip.id, format: format)
        showToast("Export queued — it will appear with your media when ready.")
      } catch {
        showToast("Export failed. Try again.")
      }
    }
  }

  private func showToast(_ text: String) {
    withAnimation { toast = text }
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(2.4))
      guard !Task.isCancelled else { return }
      withAnimation { toast = nil }
    }
  }

  /// The clip's media, resolved from whatever catalogs are already loaded —
  /// enough for the poster thumb and source title. Playback resolves again,
  /// falling back to a single-item fetch.
  private func source(for clip: MediaClip) -> MaxMediaItem? {
    model.libraryStore.catalogItems.first { $0.id == clip.mediaId }
      ?? model.libraryStore.phase.value?.saved.first { $0.id == clip.mediaId }
      ?? model.homeStore.overview.value?.browse.first { $0.id == clip.mediaId }
  }

  private func play(_ clip: MediaClip) {
    Task { await model.openClip(clip) }
  }

  private func delete(_ clip: MediaClip) {
    Task { await store.removeClip(clipID: clip.id, mediaID: clip.mediaId) }
  }
}

/// One shelf row: poster thumb (or a film glyph when the media is not in any
/// loaded catalog), the clip's name, its range, and the source title.
private struct ClipShelfRow: View {
  let clip: MediaClip
  let source: MaxMediaItem?

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      thumb

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: clip.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .lineLimit(2)

        Label {
          Text(verbatim: "\(clip.startSeconds.minuteString)–\(clip.endSeconds.minuteString)")
            .monospacedDigit()
        } icon: {
          Image(systemName: "scissors")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MaxColor.textSecondary)

        if let source {
          Text(verbatim: source.displayTitle)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .lineLimit(1)
        }
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
    .accessibilityLabel(Text(verbatim: clip.title))
  }

  @ViewBuilder
  private var thumb: some View {
    if let source {
      MaxMediaPoster(item: source, compact: true, showsMetadata: false)
        .frame(width: 78, height: 78)
    } else {
      Image(systemName: "film")
        .font(.title2)
        .foregroundStyle(MaxColor.accent)
        .frame(width: 78, height: 78)
        .background(MaxColor.surfaceSoft, in: RoundedRectangle(
          cornerRadius: MaxRadius.small,
          style: .continuous
        ))
    }
  }
}
