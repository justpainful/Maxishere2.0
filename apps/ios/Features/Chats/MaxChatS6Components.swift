import SwiftUI
import UIKit

// UI primitives adapted from the authorized Max Developers S6 delivery.
// They intentionally consume Max domain models so ChatStore remains the source of truth.

struct MaxS6ChannelListItem: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let thread: ChatThread

  private var title: String {
    if !thread.isGroup, let partnerID = thread.partnerId {
      return model.preferencesStore.nicknames[partnerID] ?? thread.title
    }
    return thread.title
  }

  private var draft: String {
    model.chatStore.draft(for: thread.id)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isTyping: Bool {
    model.chatStore.typingUserIDByChat[thread.id] != nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      MaxAvatar(name: title, imageURL: thread.avatarUrl, size: 58)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: MaxSpace.xs) {
          Text(verbatim: title)
            .font(.body.weight(thread.unreadCount > 0 ? .bold : .semibold))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)

          if thread.isMuted == true {
            Image(systemName: "speaker.slash.fill")
              .font(.caption2)
              .foregroundStyle(palette.tertiaryText)
          }

          Spacer(minLength: MaxSpace.xs)

          if let timestamp = MaxChatUIAdapter.threadTime(for: thread.lastMessageAt) {
            Text(verbatim: timestamp)
              .font(.caption2.weight(thread.unreadCount > 0 ? .semibold : .regular))
              .foregroundStyle(thread.unreadCount > 0 ? palette.accent : palette.tertiaryText)
              .monospacedDigit()
          }

        }

        HStack(spacing: MaxSpace.xxs) {
          if thread.unreadCount == 0, !thread.lastMessage.isEmpty {
            Image(systemName: "checkmark")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(palette.accent)
          }
          if isTyping {
            Image(systemName: "ellipsis.message.fill")
              .foregroundStyle(palette.accent)
            Text("chat.typing")
              .foregroundStyle(palette.accent)
          } else if !draft.isEmpty {
            Image(systemName: "pencil.line")
              .foregroundStyle(palette.accent)
            Text(verbatim: draft)
              .foregroundStyle(palette.secondaryText)
          } else {
            if thread.lastMessage.isEmpty {
              Image(systemName: "bubble.left")
                .foregroundStyle(palette.tertiaryText)
            }
            Text(verbatim: thread.lastMessage.isEmpty
              ? String(localized: "chat.empty")
              : thread.lastMessage)
              .foregroundStyle(
                thread.unreadCount > 0 ? palette.primaryText : palette.secondaryText
              )
          }
          Spacer(minLength: 0)
          if thread.isMuted == true {
            Image(systemName: "speaker.slash.fill")
              .font(.caption2)
              .foregroundStyle(palette.tertiaryText)
          }
          if thread.unreadCount > 0 {
            Text(verbatim: thread.unreadCount.formatted())
              .font(.caption2.weight(.bold))
              .foregroundStyle(palette.accentForeground)
              .frame(minWidth: 22, minHeight: 22)
              .background(palette.accent, in: Capsule())
          }
        }
        .font(.subheadline.weight(thread.unreadCount > 0 ? .medium : .regular))
        .lineLimit(1)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: accessibilityLabel))
  }

  private var accessibilityLabel: String {
    var values = [title]
    if thread.unreadCount > 0 {
      values.append("\(thread.unreadCount.formatted()) \(String(localized: "chats.unread"))")
    }
    values.append(isTyping ? String(localized: "chat.typing") : thread.lastMessage)
    return values.filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

/// The widest a message bubble may grow.
///
/// A bubble must hug its text and stop at this bound — not adopt it. Setting a
/// definite width instead made a two-word reply occupy three quarters of the row,
/// which is what "the bubbles are bigger than the text" describes. The message
/// list measures its own width once and publishes the bound here so every row
/// agrees without each one running its own geometry reader.
private struct MaxChatBubbleWidthKey: EnvironmentKey {
  static let defaultValue: CGFloat = 420
}

extension EnvironmentValues {
  var maxChatBubbleWidth: CGFloat {
    get { self[MaxChatBubbleWidthKey.self] }
    set { self[MaxChatBubbleWidthKey.self] = newValue }
  }
}

extension View {
  /// Publishes the bubble bound derived from a container of `width`.
  ///
  /// Three quarters leaves the opposite margin legible enough to tell incoming
  /// from outgoing at a glance, and the absolute cap keeps a line measurable on
  /// an iPad instead of running the full width of the screen.
  func maxChatBubbleWidth(forContainerWidth width: CGFloat) -> some View {
    environment(\.maxChatBubbleWidth, min(max(width * 0.75, 160), 420))
  }
}

struct MaxS6MessageBubbleModifier: ViewModifier {
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.maxThemePalette) private var palette

  let isCurrentUser: Bool
  let clusterPosition: MaxChatMessageClusterPosition

  func body(content: Content) -> some View {
    content
      .background(background)
      .overlay {
        shape.stroke(
          isCurrentUser ? palette.accent.opacity(0.48) : palette.separator.opacity(0.72),
          lineWidth: 0.75
        )
      }
      .clipShape(shape)
  }

  private var shape: MaxS6BubbleShape {
    MaxS6BubbleShape(
      cornerRadius: 19,
      connectedRadius: 6,
      corners: corners
    )
  }

  private var corners: UIRectCorner {
    guard clusterPosition.endsCluster else { return .allCorners }
    let isRTL = layoutDirection == .rightToLeft
    if isCurrentUser {
      return [.topLeft, .topRight, isRTL ? .bottomRight : .bottomLeft]
    }
    return [.topLeft, .topRight, isRTL ? .bottomLeft : .bottomRight]
  }

  @ViewBuilder
  private var background: some View {
    if isCurrentUser {
      LinearGradient(
        colors: [palette.accent, palette.accent.opacity(0.86)],
        startPoint: .top,
        endPoint: .bottom
      )
    } else {
      palette.elevatedContentSurface
    }
  }
}

struct MaxS6BubbleShape: Shape {
  let cornerRadius: CGFloat
  let connectedRadius: CGFloat
  let corners: UIRectCorner

  func path(in rect: CGRect) -> Path {
    let outer = min(cornerRadius, min(rect.width, rect.height) / 2)
    let connected = min(connectedRadius, outer)
    let topLeft = corners.contains(.topLeft) ? outer : connected
    let topRight = corners.contains(.topRight) ? outer : connected
    let bottomRight = corners.contains(.bottomRight) ? outer : connected
    let bottomLeft = corners.contains(.bottomLeft) ? outer : connected
    return UnevenRoundedRectangle(
      topLeadingRadius: topLeft,
      bottomLeadingRadius: bottomLeft,
      bottomTrailingRadius: bottomRight,
      topTrailingRadius: topRight,
      style: .continuous
    ).path(in: rect)
  }
}

struct MaxS6ComposerSurface: ViewModifier {
  @Environment(\.maxThemePalette) private var palette

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, MaxSpace.sm)
      .padding(.top, MaxSpace.xs)
      .padding(.bottom, MaxSpace.xs)
      .background(.ultraThinMaterial)
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [palette.accent.opacity(0.58), palette.separator.opacity(0.22), .clear],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(height: 1)
      }
  }
}
