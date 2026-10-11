import SwiftUI

/// A single-request, discrete 1...10 control. Drag changes stay local until the
/// gesture ends; tapping the already selected value delegates clearing to RatingStore.
struct DiscreteRatingControl: View {
  let score: Int?
  let isEnabled: Bool
  let isUpdating: Bool
  let accessibilityName: String
  let accessibilityIdentifier: String
  let onCommit: (Int) -> Void

  @State private var previewScore: Int?

  private var displayedScore: Int? { previewScore ?? score }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Capsule(style: .continuous)
          .fill(MaxColor.surfaceStrong)

        HStack(spacing: 2) {
          ForEach(1...10, id: \.self) { value in
            RatingRailValue(value: value, isSelected: displayedScore == value)
          }
        }
        .padding(4)

        if isUpdating {
          ProgressView()
            .controlSize(.small)
            .padding(8)
            .background { MaxControlMaterial(Circle()) }
        }
      }
      .contentShape(Rectangle())
      .gesture(dragGesture(width: proxy.size.width))
    }
    .frame(height: 52)
    .opacity(isEnabled ? 1 : 0.52)
    .sensoryFeedback(.selection, trigger: previewScore) { oldValue, newValue in
      newValue != nil && oldValue != newValue
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: accessibilityName))
    .accessibilityValue(
      Text(verbatim: displayedScore.map { "\($0) / 10" } ?? "— / 10")
    )
    .accessibilityHint(Text("rating.control.hint"))
    .accessibilityIdentifier(accessibilityIdentifier)
    .accessibilityAdjustableAction(adjustRating)
  }

  private func dragGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard isEnabled, !isUpdating else { return }
        let next = score(at: value.location.x, width: width)
        if previewScore != next {
          previewScore = next
        }
      }
      .onEnded { value in
        guard isEnabled, !isUpdating else {
          previewScore = nil
          return
        }
        let finalScore = score(at: value.location.x, width: width)
        previewScore = nil
        onCommit(finalScore)
      }
  }

  private func score(at xPosition: CGFloat, width: CGFloat) -> Int {
    guard width > 0 else { return score ?? 1 }
    let clamped = min(max(xPosition, 0), max(width - 0.001, 0))
    return min(max(Int((clamped / width) * 10) + 1, 1), 10)
  }

  private func adjustRating(_ direction: AccessibilityAdjustmentDirection) {
    guard isEnabled, !isUpdating else { return }
    let current = score ?? 0
    switch direction {
    case .increment:
      onCommit(min(current + 1, 10))
    case .decrement:
      onCommit(max(current == 0 ? 10 : current - 1, 1))
    @unknown default:
      return
    }
  }
}

private struct RatingRailValue: View {
  @Environment(\.maxThemePalette) private var palette
  let value: Int
  let isSelected: Bool

  var body: some View {
    Text(verbatim: value.formatted())
      .font(.caption.monospacedDigit().weight(isSelected ? .bold : .medium))
      .foregroundStyle(isSelected ? Color.white : palette.secondaryText)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
            .fill(palette.accent)
        }
      }
      .animation(.snappy(duration: 0.16), value: isSelected)
  }
}
