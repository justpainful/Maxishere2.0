import SwiftUI

struct MemoriesSettingsView: View {
  let store: MemoriesStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: MemoryFilter
  @State private var muted: Bool
  @State private var prefetchEnabled: Bool
  @State private var calmMotionEnabled: Bool
  @State private var showingResetConfirmation = false
  @State private var showingClearCacheConfirmation = false

  init(store: MemoriesStore) {
    self.store = store
    _draft = State(initialValue: store.filter)
    _muted = State(initialValue: store.muted)
    _prefetchEnabled = State(initialValue: store.prefetchEnabled)
    _calmMotionEnabled = State(initialValue: store.calmMotionEnabled)
  }

  var body: some View {
    NavigationStack {
      Form {
        photoAccessSection
        contentSection
        playbackSection
        localStorageSection
        privacySection
        resetSection
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background { MaxLivingBackground() }
      .navigationTitle("memories.settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("action.cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("action.apply", action: apply)
            .accessibilityIdentifier("memories.settings.apply")
        }
      }
      .confirmationDialog(
        "memories.reset.confirm.title",
        isPresented: $showingResetConfirmation,
        titleVisibility: .visible
      ) {
        Button("memories.reset.confirm.action", role: .destructive) {
          Task {
            await store.resetLocalMemories()
            dismiss()
          }
        }
        Button("action.cancel", role: .cancel) {}
      } message: {
        Text("memories.reset.confirm.message")
      }
      .confirmationDialog(
        "memories.settings.clear_cache.confirm.title",
        isPresented: $showingClearCacheConfirmation,
        titleVisibility: .visible
      ) {
        Button("memories.settings.clear_cache", role: .destructive) {
          store.clearThumbnailCache()
        }
        Button("action.cancel", role: .cancel) {}
      } message: {
        Text("memories.settings.clear_cache.confirm.message")
      }
    }
  }

  private var photoAccessSection: some View {
    Section("memories.settings.photo_access") {
      LabeledContent("memories.settings.access_status") {
        Label(
          store.authorizationStatus.titleKey,
          systemImage: store.authorizationStatus.canReadLibrary
            ? "checkmark.circle.fill"
            : "exclamationmark.circle.fill"
        )
        .foregroundStyle(
          store.authorizationStatus.canReadLibrary ? MaxColor.mint : MaxColor.warning
        )
      }
      if store.authorizationStatus == .limited {
        Text("memories.settings.limited_explanation")
          .font(MaxTypography.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
    }
  }

  private var contentSection: some View {
    Section("memories.filter.explore") {
      Picker("memories.filter.mode", selection: $draft.mode) {
        ForEach(MemoryMode.allCases) { mode in
          Text(mode.titleKey).tag(mode)
        }
      }
      Picker("memories.filter.curation", selection: $draft.curationMode) {
        ForEach(MemoryCurationMode.allCases, id: \.self) { mode in
          Text(mode.titleKey).tag(mode)
        }
      }
      Picker("memories.filter.media", selection: $draft.mediaSelection) {
        ForEach(MemoryMediaSelection.allCases, id: \.self) { selection in
          Text(selection.titleKey).tag(selection)
        }
      }
      Toggle("memories.filter.include_screenshots", isOn: $draft.includeScreenshots)
      Toggle(
        "memories.filter.include_screen_recordings",
        isOn: $draft.includeScreenRecordings
      )
      yearPicker(
        title: "memories.filter.start_year",
        selection: Binding(
          get: { draft.startYear ?? 0 },
          set: { draft.startYear = $0 == 0 ? nil : $0 }
        )
      )
      yearPicker(
        title: "memories.filter.end_year",
        selection: Binding(
          get: { draft.endYear ?? 0 },
          set: { draft.endYear = $0 == 0 ? nil : $0 }
        )
      )
    }
  }

  private var playbackSection: some View {
    Section {
      Toggle("memories.settings.start_muted", isOn: $muted)
      Toggle("memories.settings.prefetch", isOn: $prefetchEnabled)
      Toggle("memories.settings.reduce_motion", isOn: $calmMotionEnabled)
    } header: {
      Text("memories.settings.playback")
    } footer: {
      Text("memories.settings.prefetch.footer")
    }
  }

  private var localStorageSection: some View {
    Section("memories.settings.local_storage") {
      LabeledContent("memories.settings.indexed_assets") {
        Text(store.storageMetrics.indexedAssetCount, format: .number)
      }
      LabeledContent("memories.settings.cache_size") {
        Text(
          ByteCountFormatter.string(
            fromByteCount: store.storageMetrics.thumbnailCacheBytes,
            countStyle: .file
          )
        )
      }
      if let date = store.storageMetrics.lastIndexedAt {
        LabeledContent("memories.settings.last_indexed") {
          Text(date, style: .relative)
        }
      }
      Button("memories.settings.reindex", systemImage: "arrow.triangle.2.circlepath") {
        Task { await store.refreshIndex() }
      }
      Button("memories.settings.clear_cache", systemImage: "trash", role: .destructive) {
        showingClearCacheConfirmation = true
      }
      .accessibilityIdentifier("memories.settings.clear_cache")
    }
  }

  private var privacySection: some View {
    Section("memories.settings.privacy") {
      Label("memories.settings.local_only", systemImage: "lock.shield.fill")
        .font(MaxTypography.sectionTitle)
      Text("memories.settings.local_only.explanation")
        .font(MaxTypography.caption)
        .foregroundStyle(MaxColor.textSecondary)
    }
  }

  private var resetSection: some View {
    Section {
      Button("memories.settings.reset", role: .destructive) {
        showingResetConfirmation = true
      }
      .accessibilityIdentifier("memories.settings.reset")
    } footer: {
      Text("memories.settings.reset.footer")
    }
  }

  private func yearPicker(
    title: LocalizedStringKey,
    selection: Binding<Int>
  ) -> some View {
    Picker(title, selection: selection) {
      Text("memories.filter.any_year").tag(0)
      ForEach(store.availableYears, id: \.self) { year in
        Text(year, format: .number.grouping(.never)).tag(year)
      }
    }
  }

  private func apply() {
    store.updatePreferences(
      filter: draft,
      muted: muted,
      prefetchEnabled: prefetchEnabled,
      calmMotionEnabled: calmMotionEnabled
    )
    dismiss()
  }
}
