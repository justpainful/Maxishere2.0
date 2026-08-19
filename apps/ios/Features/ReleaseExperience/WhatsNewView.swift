import SwiftUI

struct WhatsNewView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private let storeOverride: ReleaseAnnouncementStore?
  private let openDestinationOverride: ((ReleaseDestination) -> Void)?

  init(
    store: ReleaseAnnouncementStore? = nil,
    onOpenDestination: ((ReleaseDestination) -> Void)? = nil
  ) {
    self.storeOverride = store
    self.openDestinationOverride = onOpenDestination
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MaxSpace.lg) {
          MaxTitleBlock(
            eyebrow: "release.whats_new.eyebrow",
            title: "release.whats_new.title",
            subtitle: "release.whats_new.subtitle"
          )

          content
        }
        .padding(.horizontal, MaxSpace.md)
        .padding(.vertical, MaxSpace.lg)
      }
      .maxScreenBackground()
      .scrollIndicators(.hidden)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("action.close") {
            dismiss()
          }
        }
      }
    }
    .accessibilityIdentifier("ui_whats_new")
  }

  @ViewBuilder
  private var content: some View {
    let announcements = releaseStore.whatsNewAnnouncements.filter {
      $0.destination != .memories || model.isMemoriesEnabled
    }
    if announcements.isEmpty {
      MaxEmptyState(
        title: "release.whats_new.empty.title",
        subtitle: "release.whats_new.empty.subtitle",
        symbol: "sparkles"
      )
    } else {
      LazyVStack(spacing: MaxSpace.sm) {
        ForEach(announcements) { announcement in
          Button {
            open(announcement)
          } label: {
            WhatsNewRow(announcement: announcement)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var releaseStore: ReleaseAnnouncementStore {
    storeOverride ?? model.releaseStore
  }

  private func open(_ announcement: ReleaseAnnouncement) {
    releaseStore.markSeen(announcement)
    releaseStore.markDestinationVisited(announcement.destination)
    dismiss()

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 180_000_000)
      if let openDestinationOverride {
        openDestinationOverride(announcement.destination)
      } else {
        model.openReleaseDestination(announcement.destination)
      }
    }
  }
}

private struct WhatsNewRow: View {
  let announcement: ReleaseAnnouncement

  var body: some View {
    MaxSurfaceCard(prominence: announcement.hasBeenSeen ? 0.28 : 0.52) {
      HStack(alignment: .top, spacing: MaxSpace.md) {
        Image(systemName: announcement.destination.symbolName)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(MaxColor.accent)
          .frame(width: 38, height: 38)
          .background(MaxColor.surfaceSoft, in: Circle())
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: MaxSpace.xs) {
          HStack(spacing: MaxSpace.xs) {
            Text(LocalizedStringKey(announcement.title))
              .font(.system(.headline, design: .rounded).weight(.bold))
              .foregroundStyle(MaxColor.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
            if !announcement.hasBeenSeen {
              NewFeatureBadge()
            }
          }

          Text(LocalizedStringKey(announcement.subtitle))
            .font(MaxTypography.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

          Label(
            LocalizedStringKey(announcement.destination.titleKey),
            systemImage: "arrow.forward.circle.fill"
          )
          .font(MaxTypography.caption.weight(.semibold))
          .foregroundStyle(MaxColor.accent)
        }

        Spacer(minLength: 0)

        Image(systemName: "chevron.forward")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(MaxColor.textSecondary)
          .padding(.top, MaxSpace.xs)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(LocalizedStringKey(announcement.title))
    .accessibilityHint("release.whats_new.open_hint")
  }
}

#Preview("What's New") {
  WhatsNewView(
    store: ReleaseAnnouncementStore(
      announcements: ReleaseAnnouncement.defaultAnnouncements(),
      defaults: UserDefaults(suiteName: "release-preview"),
      currentBuild: 1
    ),
    onOpenDestination: { _ in }
  )
}
