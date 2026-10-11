import SwiftUI

struct MaxS6SwipeToReplyModifier: ViewModifier {
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.maxThemePalette) private var palette

  let enabled: Bool
  let reply: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var didCrossThreshold = false

  private let threshold: CGFloat = 62

  func body(content: Content) -> some View {
    content
      .offset(x: dragOffset)
      .overlay(alignment: replyAlignment) {
        Image(systemName: "arrowshape.turn.up.left.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(palette.accentForeground)
          .frame(width: 34, height: 34)
          .background(palette.accent, in: Circle())
          .scaleEffect(min(abs(dragOffset) / threshold, 1))
          .opacity(min(abs(dragOffset) / 24, 1))
          .offset(x: replyIconOffset)
          .accessibilityHidden(true)
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 16)
          .onChanged { value in
            guard enabled, isReplyDirection(value.translation.width) else { return }
            let proposed = min(abs(value.translation.width) * 0.42, threshold + 12)
            dragOffset = proposed * replyDirection
            if proposed >= threshold, !didCrossThreshold {
              didCrossThreshold = true
            }
          }
          .onEnded { _ in
            let shouldReply = enabled && abs(dragOffset) >= threshold
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
              dragOffset = 0
            }
            didCrossThreshold = false
            if shouldReply { reply() }
          }
      )
      .sensoryFeedback(.selection, trigger: didCrossThreshold)
  }

  private var replyDirection: CGFloat {
    layoutDirection == .rightToLeft ? -1 : 1
  }

  private var replyAlignment: Alignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }

  private var replyIconOffset: CGFloat {
    -replyDirection * 44
  }

  private func isReplyDirection(_ width: CGFloat) -> Bool {
    width * replyDirection > 0
  }
}

extension View {
  func maxS6SwipeToReply(enabled: Bool = true, reply: @escaping () -> Void) -> some View {
    modifier(MaxS6SwipeToReplyModifier(enabled: enabled, reply: reply))
  }
}

struct MaxS6SelectionToolbar: View {
  @Environment(\.maxThemePalette) private var palette
  let count: Int
  let canDelete: Bool
  let forward: () -> Void
  let delete: () -> Void
  let cancel: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Button("common.cancel", action: cancel)
      Spacer(minLength: 0)
      Text(verbatim: count.formatted())
        .font(.headline.monospacedDigit())
        .foregroundStyle(palette.primaryText)
        .contentTransition(.numericText())
      Spacer(minLength: 0)
      Button("chat.forward", systemImage: "arrowshape.turn.up.right", action: forward)
        .labelStyle(.iconOnly)
      Button("action.delete", systemImage: "trash", role: .destructive, action: delete)
        .labelStyle(.iconOnly)
        .disabled(!canDelete)
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, MaxSpace.sm)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle().fill(palette.separator.opacity(0.48)).frame(height: 1)
    }
    .accessibilityIdentifier("ui_s6_selection_toolbar")
  }
}
