import SwiftUI

/// The reaction picker, as its own surface instead of a cramped `ControlGroup`
/// squeezed into the system context menu: big glyphs, a highlight on the one
/// you already picked, a spring entrance, and a second page of emoji behind
/// the plus button. Presented as a popover anchored to the bubble.
struct ChatKitReactionPicker: View {
  /// The reaction key the current user has on this message, if any.
  let current: String?
  /// nil = clear the current reaction.
  let onPick: (String?) -> Void

  @State private var expanded = false
  @State private var appeared = false
  @State private var customEmoji = ""

  private static let quick = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
  private static let extended = [
    "🔥", "🎉", "💯", "👏", "😍", "🥹",
    "😅", "🤔", "🤯", "😭", "😡", "👎",
    "🤝", "✨", "💀", "🫡", "🍿", "⚡️",
  ]

  var body: some View {
    VStack(spacing: MaxSpace.sm) {
      // Any emoji at all: type (or paste) one and submit. Goes through the
      // exact same onPick path as the preset glyphs.
      TextField("Any emoji…", text: $customEmoji)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit(submitCustomEmoji)
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .accessibilityLabel(Text("React with any emoji"))

      HStack(spacing: 4) {
        ForEach(Array(Self.quick.enumerated()), id: \.element) { index, emoji in
          reactionButton(emoji)
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)
            .animation(
              .spring(response: 0.32, dampingFraction: 0.62).delay(Double(index) * 0.03),
              value: appeared
            )
        }
        Button {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
        } label: {
          Image(systemName: expanded ? "chevron.up" : "plus")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 38, height: 38)
            .background(.quaternary.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Fewer reactions" : "More reactions")
      }

      if expanded {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
          ForEach(Self.extended, id: \.self) { emoji in
            reactionButton(emoji)
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
      }
    }
    .padding(MaxSpace.sm)
    .environment(\.layoutDirection, .leftToRight)
    .onAppear { appeared = true }
  }

  private func submitCustomEmoji() {
    let trimmed = customEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    // Reactions are one glyph, not a sentence — cap the length, keep whole
    // characters so a multi-scalar emoji is never cut in half.
    onPick(String(trimmed.prefix(8)))
  }

  private func reactionButton(_ emoji: String) -> some View {
    let isMine = emoji == current
    return Button {
      onPick(isMine ? nil : emoji)
    } label: {
      Text(emoji)
        .font(.system(size: 28))
        .frame(width: 38, height: 38)
        .background(
          isMine ? AnyShapeStyle(MaxColor.accent.opacity(0.3)) : AnyShapeStyle(.clear),
          in: Circle()
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isMine ? "Remove \(emoji) reaction" : "React \(emoji)")
  }
}
