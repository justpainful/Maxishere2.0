import SwiftUI

struct ReleaseTimeline: View {
  let featureItems: [ReleaseFeatureItem]
  let visibleCount: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: MaxSpace.sm) {
      ForEach(Array(featureItems.enumerated()), id: \.element.id) { index, item in
        // No `.animation(_:value:)` here on purpose: it overrode the sequencer's
        // own transaction in ReleaseHeroView, so the rows ran on a fixed curve
        // out of sync with the logo, preview and CTA — and still moved under
        // Reduce Motion. The caller's `withAnimation` already covers this tree.
        releaseRow(item)
          .opacity(index < visibleCount ? 1 : 0)
          .offset(y: reduceMotion || index < visibleCount ? 0 : 10)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func releaseRow(_ item: ReleaseFeatureItem) -> some View {
    HStack(alignment: .center, spacing: MaxSpace.sm) {
      Image(systemName: item.symbolName)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(MaxColor.accent)
        .frame(width: 34, height: 34)
        .background(MaxColor.surfaceStrong, in: Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(LocalizedStringKey(item.title))
          .font(.system(.body, design: .rounded).weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle = item.subtitle {
          Text(LocalizedStringKey(subtitle))
            .font(MaxTypography.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
        .stroke(MaxColor.line, lineWidth: 1)
    }
  }
}
