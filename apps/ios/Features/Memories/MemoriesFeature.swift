import CryptoKit
import SwiftUI

enum MemoriesFeatureAccess {
  /// SHA-256 of the single allowlisted account's lowercased, trimmed e-mail.
  ///
  /// Stored as a digest rather than the address itself so the source can live in
  /// a public build mirror without publishing a real person's e-mail. The
  /// comparison is unchanged: normalise the signed-in address, hash it, compare.
  static let enabledEmailDigest = "130f751840251bad6368398481a85af9abb3acc478ed9fb8fe57d6d03585d9d5"

  static func digest(of email: String) -> String {
    let normalised = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return SHA256.hash(data: Data(normalised.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Memories is switched off for everyone.
  ///
  /// It crashes and ejects the user from the app, which is worse than the feature
  /// being absent: a crash loses whatever they were doing everywhere else. Until
  /// the fault is found and fixed, the surface stays unreachable rather than
  /// shipping a known way to lose the session.
  ///
  /// Every entry point already routes through `isEnabled`, so this one constant
  /// closes all of them — the tab item, the full-screen cover, the release
  /// announcement destination and the deep link.
  static let isTemporarilyDisabled = true

  static func isEnabled(for user: MaxUser?) -> Bool {
    if isTemporarilyDisabled { return false }
    guard let email = user?.email else { return false }
    return digest(of: email) == enabledEmailDigest
  }
}

struct MemoriesRootView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let store = model.memoriesStore

    ZStack {
      Color.black.ignoresSafeArea()
      content(store: store)
    }
    .accessibilityIdentifier("memories.root")
    .sheet(isPresented: settingsBinding(store: store)) {
      MemoriesSettingsView(store: store)
    }
    .task {
      await store.activate()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await store.resumeAfterSceneActivation() }
    }
  }

  @ViewBuilder
  private func content(store: MemoriesStore) -> some View {
    if !store.authorizationStatus.canReadLibrary {
      MemoriesEntryView(close: closeFeature) {
        MemoriesPermissionState(
          status: store.authorizationStatus,
          requestAccess: { Task { await store.requestPhotoAccess() } }
        )
      }
    } else if store.isLoading, !store.hasLoaded {
      MemoriesEntryView(close: closeFeature) {
        ProgressView()
          .controlSize(.large)
          .tint(MaxColor.accent)
          .accessibilityLabel(Text("memories.loading.index"))
      }
    } else if let errorKey = store.errorMessageKey, store.allCandidates.isEmpty {
      MemoriesEntryView(close: closeFeature) {
        MaxContentSurface {
          VStack(alignment: .leading, spacing: MaxSpace.md) {
            Label(LocalizedStringKey(errorKey), systemImage: "exclamationmark.triangle.fill")
              .font(MaxTypography.sectionTitle)
              .foregroundStyle(MaxColor.textPrimary)
            Button("common.retry") {
              Task { await store.refreshIndex() }
            }
            .buttonStyle(MaxPrimaryButtonStyle())
          }
        }
      }
    } else if store.viewerCandidates.isEmpty {
      MemoriesEntryView(close: closeFeature) {
        VStack(spacing: MaxSpace.md) {
          MaxEmptyState(
            title: "memories.empty.title",
            subtitle: "memories.empty.subtitle",
            symbol: "rectangle.stack"
          )
          Button("memories.settings.adjust") {
            store.showingSettings = true
          }
          .buttonStyle(MaxSecondaryButtonStyle())
        }
      }
    } else {
      MemoriesViewerView(store: store, close: closeFeature)
    }
  }

  private func settingsBinding(store: MemoriesStore) -> Binding<Bool> {
    Binding(
      get: { store.showingSettings },
      set: { store.showingSettings = $0 }
    )
  }

  private func closeFeature() {
    model.memoriesStore.dismissViewer()
    dismiss()
  }
}

private struct MemoriesEntryView<Content: View>: View {
  let close: () -> Void
  let content: Content

  init(close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
    self.close = close
    self.content = content()
  }

  var body: some View {
    MaxScreen {
      VStack(spacing: MaxSpace.lg) {
        HStack {
          Spacer(minLength: 0)
          MaxIconButton(
            systemName: "xmark",
            size: .navigation,
            accessibilityLabel: "action.close",
            action: close
          )
          .accessibilityIdentifier("memories.close")
        }

        content
          .frame(maxWidth: 560)

        Spacer(minLength: 0)
      }
      .padding(MaxSpace.md)
    }
  }
}
