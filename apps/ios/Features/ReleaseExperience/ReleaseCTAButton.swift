import SwiftUI

struct ReleaseCTAButton: View {
  let titleKey: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: MaxSpace.sm) {
        Text(LocalizedStringKey(titleKey))
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Image(systemName: "arrow.forward")
          .imageScale(.medium)
          .accessibilityHidden(true)
      }
      .font(.system(.body, design: .rounded).weight(.bold))
      .frame(maxWidth: .infinity)
      .frame(minHeight: 54)
      .contentShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
    }
    .buttonStyle(.glassProminent)
    .tint(MaxColor.accent)
    .accessibilityLabel(LocalizedStringKey(titleKey))
  }
}
