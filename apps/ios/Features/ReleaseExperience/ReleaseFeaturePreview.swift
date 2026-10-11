import SwiftUI

struct ReleaseFeaturePreview: View {
  let visualStyle: ReleaseVisualStyle

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.maxThemePalette) private var palette
  @State private var isLifted = false

  private var isCalm: Bool { reduceMotion || !motionEnabled }

  var body: some View {
    Group {
      switch visualStyle {
      case .mobileLaunch:
        mobileLaunchPreview
      case .memories:
        memoriesPreview
      case .settings:
        settingsPreview
      case .featurePreview:
        genericFeaturePreview
      }
    }
    .offset(y: isCalm || !isLifted ? 0 : -5)
    .animation(
      isCalm ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
      value: isLifted
    )
    .task {
      guard !isCalm else { return }
      isLifted = true
    }
    .accessibilityElement(children: .contain)
  }

  private var mobileLaunchPreview: some View {
    ReleasePhoneFrame {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        HStack {
          HStack(spacing: MaxSpace.xs) {
            MaxIdentityMark(size: 22)
            Text("Max")
              .font(.system(.caption, design: .rounded).weight(.bold))
              .foregroundStyle(MaxColor.textPrimary)
          }
          Spacer()
          NewFeatureBadge()
        }

        HStack(spacing: MaxSpace.xs) {
          MaxChip(title: "home.mode.shuffle", isSelected: true)
          MaxChip(title: "home.mode.browse", isSelected: false)
        }

        ReleaseMiniPanel(
          titleKey: "release.preview.tasks",
          subtitleKey: "release.preview.tasks.subtitle",
          symbolName: "checklist"
        )
        ReleaseMiniPanel(
          titleKey: "release.preview.plans",
          subtitleKey: "release.preview.plans.subtitle",
          symbolName: "calendar"
        )
      }
    }
  }

  private var memoriesPreview: some View {
    ReleasePhoneFrame {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        HStack {
          Label("memories.library.title", systemImage: "rectangle.stack.fill")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(MaxColor.textPrimary)
          Spacer()
          NewFeatureBadge()
        }

        MemoriesPanel(padding: MaxSpace.sm) {
          VStack(alignment: .leading, spacing: MaxSpace.xs) {
            Text("memories.source.mixed")
              .font(MaxTypography.caption.weight(.bold))
              .foregroundStyle(MaxColor.textPrimary)
            HStack(spacing: MaxSpace.xs) {
              ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
                  .fill(index == 0 ? MaxColor.accent : MaxColor.midnight)
                  .frame(height: index == 1 ? 78 : 64)
                  .overlay {
                    Image(systemName: index == 2 ? "play.fill" : "photo.fill")
                      .foregroundStyle(
                        index == 0
                          ? palette.accentForeground.opacity(0.82)
                          : Color.white.opacity(0.72)
                      )
                      .accessibilityHidden(true)
                  }
              }
            }
          }
        }

        ReleaseMiniPanel(
          titleKey: "release.memories.feature.privacy",
          subtitleKey: "release.memories.feature.privacy.subtitle",
          symbolName: "lock.shield.fill"
        )
      }
    }
  }

  private var settingsPreview: some View {
    ReleasePhoneFrame {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        HStack {
          Label("settings.title", systemImage: "gearshape.fill")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(MaxColor.accent)
          Spacer()
          NewFeatureBadge()
        }

        ReleaseSettingsRow(titleKey: "release.whats_new.title", symbolName: "sparkles")
        ReleaseSettingsRow(titleKey: "settings.connection", symbolName: "server.rack")
        ReleaseSettingsRow(titleKey: "settings.account", symbolName: "person.crop.circle")
      }
    }
  }

  private var genericFeaturePreview: some View {
    ReleasePhoneFrame {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        Label("release.feature_preview.title", systemImage: "sparkles")
          .font(.system(.caption, design: .rounded).weight(.bold))
          .foregroundStyle(MaxColor.accent)

        ReleaseMiniPanel(
          titleKey: "release.feature_preview.feature.native",
          subtitleKey: "release.feature_preview.feature.native.subtitle",
          symbolName: "iphone"
        )
        ReleaseMiniPanel(
          titleKey: "release.feature_preview.feature.reusable",
          subtitleKey: "release.feature_preview.feature.reusable.subtitle",
          symbolName: "square.stack.3d.forward.dottedline"
        )
        ReleaseMiniPanel(
          titleKey: "release.feature_preview.feature.private",
          subtitleKey: "release.feature_preview.feature.private.subtitle",
          symbolName: "lock.fill"
        )
      }
    }
  }
}

private struct ReleasePhoneFrame<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(MaxSpace.md)
      .frame(maxWidth: 310)
      .frame(minHeight: 280)
      .background(
        MaxColor.canvasRaised,
        in: RoundedRectangle(cornerRadius: 34, style: .continuous)
      )
      .overlay(alignment: .top) {
        Capsule(style: .continuous)
          .fill(MaxColor.lineStrong)
          .frame(width: 78, height: 5)
          .padding(.top, 10)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
          .stroke(MaxColor.lineStrong, lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.28), radius: 24, y: 16)
  }
}

private struct ReleaseMiniPanel: View {
  let titleKey: String
  let subtitleKey: String
  let symbolName: String

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: symbolName)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(MaxColor.accent)
        .frame(width: 32, height: 32)
        .background(MaxColor.surfaceSoft, in: Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(LocalizedStringKey(titleKey))
          .font(.system(.subheadline, design: .rounded).weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(LocalizedStringKey(subtitleKey))
          .font(MaxTypography.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
  }
}

private struct ReleaseSettingsRow: View {
  let titleKey: String
  let symbolName: String

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: symbolName)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(MaxColor.accent)
        .frame(width: 32, height: 32)
        .background(MaxColor.surfaceSoft, in: Circle())
        .accessibilityHidden(true)
      Text(LocalizedStringKey(titleKey))
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundStyle(MaxColor.textPrimary)
      Spacer()
      Image(systemName: "chevron.forward")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(MaxColor.textSecondary)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
  }
}

private struct MemoriesPanel<Content: View>: View {
  let padding: CGFloat
  let content: Content

  init(padding: CGFloat = MaxSpace.sm, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background(
        MaxColor.surface,
        in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
      )
  }
}

#Preview("Release Preview - Mobile") {
  ZStack {
    Rectangle().fill(MaxColor.canvas).ignoresSafeArea()
    ReleaseFeaturePreview(visualStyle: .mobileLaunch)
      .padding()
  }
}

#Preview("Release Preview - Memories") {
  ZStack {
    Rectangle().fill(MaxColor.canvas).ignoresSafeArea()
    ReleaseFeaturePreview(visualStyle: .memories)
      .padding()
  }
}

#Preview("Release Preview - Settings") {
  ZStack {
    Rectangle().fill(MaxColor.canvas).ignoresSafeArea()
    ReleaseFeaturePreview(visualStyle: .settings)
      .padding()
  }
}

#Preview("Release Preview - Feature") {
  ZStack {
    Rectangle().fill(MaxColor.canvas).ignoresSafeArea()
    ReleaseFeaturePreview(visualStyle: .featurePreview)
      .padding()
  }
}
