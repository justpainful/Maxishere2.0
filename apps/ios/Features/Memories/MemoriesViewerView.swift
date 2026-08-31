import SwiftUI
import UIKit

@MainActor
struct MemoriesViewerView: View {
  let store: MemoriesStore
  let close: () -> Void

  @State private var selection: MemoryAssetKey?
  @State private var isPreparingExport = false
  @State private var actionErrorKey: String?
  @GestureState private var horizontalDismissOffset: CGFloat = 0

  var body: some View {
    let candidates = store.viewerCandidates
    Group {
      if candidates.isEmpty {
        // Nothing to show — dismiss the viewer immediately
        Color.black.ignoresSafeArea()
          .onAppear { close() }
      } else {
        ZStack {
          Color.black.ignoresSafeArea()

          ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
              ForEach(candidates) { candidate in
                MemoryStageView(
                  store: store,
                  candidate: candidate,
                  isActive: selection == candidate.key
                )
                .containerRelativeFrame([.horizontal, .vertical])
                .id(candidate.key)
              }
            }
            .scrollTargetLayout()
          }
          .scrollIndicators(.hidden)
          .scrollTargetBehavior(.paging)
          .scrollPosition(id: $selection)
          .accessibilityIdentifier("memories.viewer.pager")

          viewerChrome(candidates: candidates)
        }
        .ignoresSafeArea()
        .offset(x: max(0, horizontalDismissOffset))
        .simultaneousGesture(horizontalDismissGesture)
        .background(Color.black)
        .accessibilityIdentifier("memories.viewer")
        .onAppear {
          selection = store.selectedCandidateKey ?? candidates.first?.key
          updateSelection(selection, candidates: candidates)
        }
        .onChange(of: selection) { _, selected in
          updateSelection(selected, candidates: store.viewerCandidates)
        }
        .onChange(of: store.viewerCandidates.map(\.key)) { _, keys in
          guard let selection, keys.contains(selection) else {
            self.selection = keys.first
            return
          }
        }
      }
    }
  }

  private func viewerChrome(candidates: [MemoryCandidate]) -> some View {
    VStack(spacing: 0) {
      topBar(candidates: candidates)
        .padding(.horizontal, MaxSpace.md)

      Spacer(minLength: 0)

      if let candidate = currentCandidate(in: candidates) {
        bottomBar(candidate: candidate)
          .padding(.horizontal, MaxSpace.md)
      }
    }
    .safeAreaPadding(.top, MaxSpace.md)
    .safeAreaPadding(.bottom, MaxSpace.lg)
  }

  private func topBar(candidates: [MemoryCandidate]) -> some View {
    HStack(alignment: .top, spacing: MaxSpace.sm) {
      MemoriesViewerGlassPanel {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: MaxSpace.xs) {
            Image(systemName: "lock.fill")
            Text("memories.local.short")
          }
          .font(MaxTypography.caption.weight(.bold))
          .foregroundStyle(Color.white.opacity(0.82))
          if let candidate = currentCandidate(in: candidates) {
            Text(verbatim: candidate.title)
              .font(.system(.headline, design: .rounded).weight(.bold))
              .foregroundStyle(.white)
            Text(verbatim: progressText(candidate: candidate, in: candidates))
              .font(MaxTypography.caption)
              .foregroundStyle(Color.white.opacity(0.72))
          }
        }
      }

      Spacer(minLength: 0)

      GlassEffectContainer(spacing: MaxSpace.xs) {
        HStack(spacing: MaxSpace.xs) {
          MemoriesViewerActionButton(
            systemName: "gearshape",
            accessibilityLabel: "memories.settings"
          ) {
            store.showingSettings = true
          }
          .accessibilityIdentifier("memories.settings")

          MemoriesViewerActionButton(
            systemName: store.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            accessibilityLabel: "memories.audio",
            action: store.toggleMute
          )
          MemoriesViewerActionButton(
            systemName: "xmark",
            accessibilityLabel: "action.close",
            action: close
          )
          .accessibilityIdentifier("memories.viewer.close")
        }
      }
    }
  }

  private func bottomBar(candidate: MemoryCandidate) -> some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      if let actionErrorKey {
        Text(LocalizedStringKey(actionErrorKey))
          .font(MaxTypography.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, MaxSpace.sm)
          .padding(.vertical, MaxSpace.xs)
          .background(Color.red.opacity(0.72), in: Capsule())
      }

      MemoriesViewerGlassPanel {
        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: candidate.subtitle)
            .font(MaxTypography.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.84))
          HStack(spacing: MaxSpace.xs) {
            Label(
              candidate.kind == .video ? "media.kind.video" : "media.kind.media",
              systemImage: candidate.kind == .video ? "play.rectangle" : "photo"
            )
            if candidate.isFavorite {
              Image(systemName: "heart.fill")
                .accessibilityLabel(Text("memories.favorite"))
            }
          }
          .font(MaxTypography.caption)
          .foregroundStyle(Color.white.opacity(0.70))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GlassEffectContainer(spacing: MaxSpace.xs) {
        HStack(spacing: MaxSpace.sm) {
          MemoriesViewerActionButton(
            systemName: store.savedKeys.contains(candidate.key) ? "bookmark.fill" : "bookmark",
            accessibilityLabel: store.savedKeys.contains(candidate.key)
              ? "memories.unsave"
              : "action.save"
          ) {
            store.toggleSaved(candidate)
            confirmAction()
          }
          .accessibilityIdentifier("memories.save")

          MemoriesViewerActionButton(
            systemName: "square.and.arrow.up",
            accessibilityLabel: "memories.system_share"
          ) {
            share(candidate)
          }
          .disabled(isPreparingExport)

          MemoriesViewerActionButton(
            systemName: store.hiddenKeys.contains(candidate.key) ? "eye" : "eye.slash",
            accessibilityLabel: store.hiddenKeys.contains(candidate.key)
              ? "memories.restore"
              : "memories.hide"
          ) {
            if store.hiddenKeys.contains(candidate.key) {
              store.restore(candidate)
            } else {
              store.hide(candidate)
            }
            syncSelectionToStore()
            confirmAction()
          }
          .accessibilityIdentifier("memories.hide")

          Spacer(minLength: 0)

          actionMenu(candidate: candidate)
        }
        .padding(.horizontal, MaxSpace.xs)
      }
    }
  }

  private func actionMenu(candidate: MemoryCandidate) -> some View {
    Menu {
      Button("memories.action.never_show", systemImage: "nosign") {
        store.doNotShowAgain(candidate)
        syncSelectionToStore()
        confirmAction()
      }
      Button("memories.action.exclude_date", systemImage: "calendar.badge.minus") {
        store.excludeDate(of: candidate)
        syncSelectionToStore()
        confirmAction()
      }
      if candidate.isScreenshot {
        Button("memories.action.exclude_screenshots", systemImage: "rectangle.slash") {
          store.excludeScreenshots()
        }
      }
      if candidate.isScreenRecording {
        Button("memories.action.exclude_recordings", systemImage: "record.circle") {
          store.excludeScreenRecordings()
        }
      }
      Divider()
      if store.canPresentOriginalInPhotos {
        Button("memories.action.open_photos", systemImage: "photo.on.rectangle") {
          MemoriesLocalExportPresenter.presentOriginalInPhotos(
            localIdentifier: candidate.localIdentifier
          )
        }
      }
      Button("memories.action.export", systemImage: "folder.badge.plus") {
        export(candidate)
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .contentShape(Circle())
    }
    .buttonStyle(.glass)
    .accessibilityLabel(Text("memories.actions.more"))
    .accessibilityIdentifier("memories.more")
  }

  private var horizontalDismissGesture: some Gesture {
    DragGesture(minimumDistance: 20)
      .updating($horizontalDismissOffset) { value, state, _ in
        let width = value.translation.width
        let height = value.translation.height
        guard width > 0, abs(width) > abs(height) * 1.25 else { return }
        state = width
      }
      .onEnded { value in
        let width = value.translation.width
        let height = value.translation.height
        guard width > 110, abs(width) > abs(height) * 1.25 else { return }
        close()
      }
  }

  private func currentCandidate(in candidates: [MemoryCandidate]) -> MemoryCandidate? {
    guard let selection else { return candidates.first }
    return candidates.first(where: { $0.key == selection }) ?? candidates.first
  }

  private func progressText(
    candidate: MemoryCandidate,
    in candidates: [MemoryCandidate]
  ) -> String {
    let index = candidates.firstIndex(where: { $0.key == candidate.key }) ?? 0
    return "\((index + 1).formatted()) / \(candidates.count.formatted())"
  }

  private func updateSelection(
    _ key: MemoryAssetKey?,
    candidates: [MemoryCandidate]
  ) {
    guard let key, let candidate = candidates.first(where: { $0.key == key }) else { return }
    store.markViewed(candidate)
  }

  private func confirmAction() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func syncSelectionToStore() {
    let keys = store.viewerCandidates.map(\.key)
    if let selected = store.selectedCandidateKey, keys.contains(selected) {
      selection = selected
    } else {
      selection = keys.first
    }
  }

  private func share(_ candidate: MemoryCandidate) {
    isPreparingExport = true
    actionErrorKey = nil
    Task {
      defer { isPreparingExport = false }
      do {
        let url = try await store.deviceExportFile(
          localIdentifier: candidate.localIdentifier
        )
        MemoriesLocalExportPresenter.presentShare(for: url)
      } catch {
        actionErrorKey = "memories.action.export_failed"
      }
    }
  }

  private func export(_ candidate: MemoryCandidate) {
    isPreparingExport = true
    actionErrorKey = nil
    Task {
      defer { isPreparingExport = false }
      do {
        let url = try await store.deviceExportFile(
          localIdentifier: candidate.localIdentifier
        )
        MemoriesLocalExportPresenter.presentDocumentExport(for: url)
      } catch {
        actionErrorKey = "memories.action.export_failed"
      }
    }
  }

}
