import SwiftUI

struct MaxS6MessageList<Row: View, OlderControl: View>: View {
  let messages: [ChatMessage]
  let unreadCount: Int
  let showsDemoNotice: Bool
  let isTyping: Bool
  let scrollTargetID: String?
  let olderControl: () -> OlderControl
  let row: (ChatMessage, MaxChatMessageClusterPosition, ScrollViewProxy) -> Row

  @State private var showsScrollToBottom = false
  /// Width of the list, measured once and used to bound bubble growth.
  @State private var containerWidth: CGFloat = 420

  init(
    messages: [ChatMessage],
    unreadCount: Int,
    showsDemoNotice: Bool,
    isTyping: Bool,
    scrollTargetID: String? = nil,
    @ViewBuilder olderControl: @escaping () -> OlderControl,
    @ViewBuilder row: @escaping (
      ChatMessage,
      MaxChatMessageClusterPosition,
      ScrollViewProxy
    ) -> Row
  ) {
    self.messages = messages
    self.unreadCount = unreadCount
    self.showsDemoNotice = showsDemoNotice
    self.isTyping = isTyping
    self.scrollTargetID = scrollTargetID
    self.olderControl = olderControl
    self.row = row
  }

  private var unreadStartIndex: Int? {
    guard unreadCount > 0, unreadCount < messages.count else { return nil }
    return max(messages.startIndex, messages.endIndex - unreadCount)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          if showsDemoNotice {
            Label("chat.demo.local_notice", systemImage: "iphone")
              .font(.caption.weight(.semibold))
              .foregroundStyle(MaxColor.textSecondary)
              .padding(.horizontal, MaxSpace.sm)
              .padding(.vertical, MaxSpace.xs)
              .background(MaxColor.surfaceSoft, in: Capsule())
              .accessibilityIdentifier("ui_chat_demo_local_notice")
          }

          olderControl()

          ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            if unreadStartIndex == index {
              MaxS6UnreadMessagesDivider(count: unreadCount)
            }
            if MaxChatUIAdapter.startsNewDay(in: messages, at: index),
               let label = MaxChatUIAdapter.dayLabel(for: message.createdAt) {
              MaxS6DaySeparator(label: label)
            }
            row(
              message,
              MaxChatUIAdapter.clusterPosition(in: messages, at: index),
              proxy
            )
          }

          if isTyping {
            MaxS6TypingIndicator()
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          }

          Color.clear
            .frame(height: 1)
            .id("s6-message-list-bottom")
            .onAppear { showsScrollToBottom = false }
            .onDisappear {
              if messages.count > 8 { showsScrollToBottom = true }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, MaxSpace.sm)
        .padding(.bottom, MaxSpace.md)
      }
      // Measured once here and published to every row, so a bubble knows how wide
      // it may grow without each one measuring the container for itself.
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
      .maxChatBubbleWidth(forContainerWidth: containerWidth)
      // Both flags are flipped from outside a transaction — `isTyping` by the
      // realtime store and `showsScrollToBottom` by a sentinel's appearance — so
      // their declared transitions only run when the value drives them here.
      .maxAnimation(MaxMotion.quick, value: isTyping)
      .maxAnimation(MaxMotion.quick, value: showsScrollToBottom)
      .scrollDismissesKeyboard(.interactively)
      .defaultScrollAnchor(.bottom)
      .onChange(of: messages.last?.id) { _, messageID in
        guard let messageID else { return }
        withAnimation(MaxMotion.quick) {
          proxy.scrollTo(messageID, anchor: .bottom)
        }
      }
      .onChange(of: scrollTargetID) { _, messageID in
        guard let messageID else { return }
        withAnimation(MaxMotion.standard) {
          proxy.scrollTo(messageID, anchor: .center)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if showsScrollToBottom {
          Button {
            withAnimation(MaxMotion.standard) {
              proxy.scrollTo("s6-message-list-bottom", anchor: .bottom)
            }
          } label: {
            Image(systemName: "arrow.down")
              .font(.body.weight(.bold))
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.glassProminent)
          .padding(MaxSpace.md)
          .transition(.scale.combined(with: .opacity))
          .accessibilityLabel(Text("chat.scroll_to_bottom"))
          .accessibilityIdentifier("ui_s6_chat_scroll_bottom")
        }
      }
    }
    .background {
      MaxS6ChatBackdrop().ignoresSafeArea()
    }
    .accessibilityIdentifier("ui_s6_message_list")
  }
}

private struct MaxS6DaySeparator: View {
  let label: String

  var body: some View {
    Text(verbatim: label)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(MaxColor.textSecondary)
      .padding(.horizontal, MaxSpace.sm)
      .padding(.vertical, MaxSpace.xxs)
      .background(.thinMaterial, in: Capsule())
      .padding(.vertical, MaxSpace.sm)
      .frame(maxWidth: .infinity)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct MaxS6UnreadMessagesDivider: View {
  @Environment(\.maxThemePalette) private var palette
  let count: Int

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Rectangle().fill(palette.accent.opacity(0.35)).frame(height: 1)
      Label {
        Text(verbatim: count.formatted())
      } icon: {
        Image(systemName: "envelope.badge.fill")
      }
      .font(.caption2.weight(.bold))
      .foregroundStyle(palette.accent)
      Rectangle().fill(palette.accent.opacity(0.35)).frame(height: 1)
    }
    .padding(.vertical, MaxSpace.sm)
    .accessibilityIdentifier("ui_s6_unread_divider")
  }
}

private struct MaxS6TypingIndicator: View {
  @Environment(\.maxThemePalette) private var palette
  @State private var phase = 0

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(palette.secondaryText.opacity(phase == index ? 0.95 : 0.42))
          .frame(width: 6, height: 6)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(palette.elevatedContentSurface, in: Capsule())
    .frame(maxWidth: .infinity, alignment: .leading)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
      }
    }
    .accessibilityLabel(Text("chat.typing"))
  }
}

struct MaxS6ChatBackdrop: View {
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    ZStack {
      palette.canvas
      LinearGradient(
        colors: [
          palette.accent.opacity(0.06),
          Color.clear,
          Color.primary.opacity(0.025),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Canvas { context, size in
        let spacing: CGFloat = 34
        var path = Path()
        var x: CGFloat = -size.height
        while x < size.width {
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x + size.height, y: size.height))
          x += spacing
        }
        context.stroke(path, with: .color(Color.primary.opacity(0.018)), lineWidth: 0.7)
      }
    }
    .accessibilityHidden(true)
  }
}
