import SwiftUI

struct NewFeatureBadge: View {
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Text("release.badge.new")
      .font(.system(.caption2, design: .rounded).weight(.bold))
      .foregroundStyle(palette.successForeground)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.horizontal, MaxSpace.xs)
      .padding(.vertical, MaxSpace.xxs)
      .background {
        Capsule(style: .continuous)
          .fill(MaxColor.mint)
      }
      .accessibilityLabel("release.badge.new.accessibility")
  }
}

#Preview("New Feature Badge") {
  ZStack {
    Rectangle().fill(MaxColor.canvas).ignoresSafeArea()
    NewFeatureBadge()
  }
}
