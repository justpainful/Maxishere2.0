import SwiftUI

enum MaxS6Reaction: String, CaseIterable, Identifiable {
  case heart
  case thumbsUp = "thumbs_up"
  case thumbsDown = "thumbs_down"
  case laugh
  case emphasis
  case question

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .heart: "❤️"
    case .thumbsUp: "👍"
    case .thumbsDown: "👎"
    case .laugh: "😂"
    case .emphasis: "‼️"
    case .question: "❓"
    }
  }
}

struct MaxS6ReactionBar: View {
  @Environment(\.maxThemePalette) private var palette
  let reactions: [ChatReaction]
  let select: (ChatReaction) -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(reactions) { reaction in
        Button {
          select(reaction)
        } label: {
          HStack(spacing: 3) {
            Text(verbatim: MaxS6Reaction(rawValue: reaction.key)?.symbol ?? "•")
            if reaction.count > 1 {
              Text(verbatim: reaction.count.formatted())
                .font(.caption2.weight(.semibold).monospacedDigit())
            }
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(
            reaction.reactedByMe
              ? palette.accent.opacity(0.18) : palette.elevatedContentSurface,
            in: Capsule()
          )
          .overlay {
            Capsule().stroke(
              reaction.reactedByMe
                ? palette.accent.opacity(0.7) : palette.separator.opacity(0.65),
              lineWidth: 0.75
            )
          }
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("ui_s6_message_reactions")
  }
}

struct MaxS6ReadReceiptSummary: View {
  @Environment(\.maxThemePalette) private var palette
  let receipts: [ChatReadReceipt]
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 4) {
        HStack(spacing: -6) {
          ForEach(receipts.prefix(3)) { receipt in
            MaxAvatar(
              name: receipt.displayName ?? receipt.userId,
              imageURL: receipt.avatarUrl,
              size: 20
            )
            .overlay(Circle().stroke(palette.canvas, lineWidth: 1.5))
          }
        }
        Text(verbatim: receipts.count.formatted())
          .font(.caption2.weight(.semibold).monospacedDigit())
          .foregroundStyle(palette.secondaryText)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("chat.read_by"))
    .accessibilityIdentifier("ui_s6_read_receipts")
  }
}

struct MaxS6ReadReceiptsSheet: View {
  @Environment(\.dismiss) private var dismiss
  let receipts: [ChatReadReceipt]

  var body: some View {
    NavigationStack {
      List(receipts) { receipt in
        HStack(spacing: 12) {
          MaxAvatar(
            name: receipt.displayName ?? receipt.userId,
            imageURL: receipt.avatarUrl,
            size: 42
          )
          VStack(alignment: .leading, spacing: 3) {
            Text(receipt.displayName ?? receipt.userId)
              .font(.subheadline.weight(.semibold))
            if let time = MaxChatUIAdapter.messageTime(for: receipt.readAt) {
              Text(verbatim: time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("chat.read_by")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

struct MaxS6MessageActionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette

  let message: ChatMessage
  let isCurrentUser: Bool
  let react: (String?) -> Void
  let reply: () -> Void
  let copy: () -> Void
  let showThread: () -> Void
  let pin: () -> Void
  let forward: () -> Void
  let edit: () -> Void
  let select: () -> Void
  let delete: () -> Void

  private var selectedReaction: String? {
    message.reactions?.first(where: { $0.reactedByMe })?.key
  }

  var body: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(palette.separator)
        .frame(width: 36, height: 5)
        .padding(.top, 8)
        .padding(.bottom, 14)

      messagePreview

      HStack(spacing: 0) {
        ForEach(MaxS6Reaction.allCases) { reaction in
          Button {
            react(selectedReaction == reaction.rawValue ? nil : reaction.rawValue)
            dismiss()
          } label: {
            Text(verbatim: reaction.symbol)
              .font(.system(size: 27))
              .frame(maxWidth: .infinity, minHeight: 48)
              .background(
                selectedReaction == reaction.rawValue
                  ? palette.accent.opacity(0.16) : Color.clear,
                in: Circle()
              )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_s6_reaction_\(reaction.rawValue)")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      Divider()

      ScrollView {
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())],
          spacing: 8
        ) {
          action("chat.reply", icon: "arrowshape.turn.up.left", perform: reply)
          action("chat.copy", icon: "doc.on.doc", perform: copy)
          action("chat.thread", icon: "bubble.left.and.bubble.right", perform: showThread)
          action(
            message.isPinned == true ? "chat.unpin" : "chat.pin",
            icon: message.isPinned == true ? "pin.slash" : "pin",
            perform: pin
          )
          action("chat.forward", icon: "arrowshape.turn.up.right", perform: forward)
          action("chat.select", icon: "checkmark.circle", perform: select)
          if isCurrentUser {
            action("chat.edit", icon: "pencil", perform: edit)
            action("action.delete", icon: "trash", role: .destructive, perform: delete)
          }
        }
        .padding(12)
      }
    }
    .background(palette.elevatedContentSurface)
    .presentationDetents([.height(isCurrentUser ? 430 : 370), .large])
    .presentationDragIndicator(.hidden)
    .accessibilityIdentifier("ui_s6_message_actions")
  }

  private var messagePreview: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(message.sender?.displayName ?? message.senderId)
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.accent)
      Text(verbatim: message.content ?? String(localized: "chat.message.media"))
        .font(.subheadline)
        .foregroundStyle(palette.primaryText)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 16))
    .padding(.horizontal, 12)
  }

  private func action(
    _ title: LocalizedStringKey,
    icon: String,
    role: ButtonRole? = nil,
    perform: @escaping () -> Void
  ) -> some View {
    Button(role: role) {
      dismiss()
      perform()
    } label: {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 13))
    }
    .buttonStyle(.plain)
  }
}

struct MaxS6MessageSearchSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette

  let thread: ChatThread
  let onSelect: (String) -> Void

  @State private var query = ""
  @State private var searchTask: Task<Void, Never>?

  private var phase: LoadState<[ChatMessage]> {
    model.chatStore.searchResultsByChat[thread.id] ?? .idle
  }

  var body: some View {
    NavigationStack {
      Group {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView(
            "chats.search",
            systemImage: "magnifyingglass",
            description: Text("chat.search.help")
          )
        } else if phase.isLoading {
          ProgressView("common.loading")
        } else if let error = phase.errorMessage {
          MaxLoadFailureView(message: error) { runSearch() }
        } else if let messages = phase.value, !messages.isEmpty {
          List(messages) { message in
            Button {
              dismiss()
              onSelect(message.id)
            } label: {
              MaxS6SearchResultRow(message: message)
            }
            .buttonStyle(.plain)
            .listRowBackground(palette.canvas)
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
      .background(palette.canvas)
      .navigationTitle("chats.search")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
      .onChange(of: query) { _, _ in scheduleSearch() }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
    .accessibilityIdentifier("ui_s6_message_search")
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(280))
      guard !Task.isCancelled else { return }
      await model.chatStore.searchMessages(in: thread.id, query: query)
    }
  }

  private func runSearch() {
    Task { await model.chatStore.searchMessages(in: thread.id, query: query) }
  }
}

private struct MaxS6SearchResultRow: View {
  @Environment(\.maxThemePalette) private var palette
  let message: ChatMessage

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      MaxAvatar(
        name: message.sender?.displayName ?? message.senderId,
        imageURL: message.sender?.avatarUrl,
        size: 42
      )
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(message.sender?.displayName ?? message.senderId)
            .font(.subheadline.weight(.semibold))
          Spacer()
          if let time = MaxChatUIAdapter.messageTime(for: message.createdAt) {
            Text(verbatim: time)
              .font(.caption2)
              .foregroundStyle(palette.tertiaryText)
          }
        }
        Text(verbatim: message.content ?? String(localized: "chat.message.media"))
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
          .lineLimit(3)
      }
    }
    .padding(.vertical, 5)
  }
}

struct MaxS6PinnedMessagesSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread
  let onSelect: (String) -> Void

  private var phase: LoadState<[ChatMessage]> {
    model.chatStore.pinnedMessagesByChat[thread.id] ?? .idle
  }

  var body: some View {
    NavigationStack {
      Group {
        if phase.isLoading {
          ProgressView("common.loading")
        } else if let error = phase.errorMessage {
          MaxLoadFailureView(message: error) { load() }
        } else if let messages = phase.value, !messages.isEmpty {
          List(messages) { message in
            Button {
              dismiss()
              onSelect(message.id)
            } label: {
              MaxS6SearchResultRow(message: message)
            }
            .buttonStyle(.plain)
          }
          .listStyle(.plain)
        } else {
          ContentUnavailableView(
            "chat.pinned",
            systemImage: "pin",
            description: Text("chat.pinned.empty")
          )
        }
      }
      .navigationTitle("chat.pinned")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
      .task { await model.chatStore.loadPinnedMessages(in: thread.id) }
      .refreshable { await model.chatStore.loadPinnedMessages(in: thread.id) }
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_s6_pinned_messages")
  }

  private func load() {
    Task { await model.chatStore.loadPinnedMessages(in: thread.id) }
  }
}

struct MaxS6ThreadRepliesSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette
  let thread: ChatThread
  let parent: ChatMessage

  @State private var draft = ""

  private var replies: [ChatMessage] {
    (model.chatStore.messagesByChat[thread.id]?.value ?? []).filter {
      $0.replyToId == parent.id
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        MaxS6SearchResultRow(message: parent)
          .padding(12)
          .background(palette.selectedControl)

        if replies.isEmpty {
          ContentUnavailableView(
            "chat.thread",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("chat.thread.empty")
          )
          .frame(maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 10) {
              ForEach(replies) { reply in
                MaxS6SearchResultRow(message: reply)
                  .padding(10)
                  .background(
                    palette.elevatedContentSurface,
                    in: RoundedRectangle(cornerRadius: 14)
                  )
              }
            }
            .padding(12)
          }
        }

        HStack(alignment: .bottom, spacing: 8) {
          TextField("chat.composer.placeholder", text: $draft, axis: .vertical)
            .lineLimit(1...5)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(palette.elevatedContentSurface, in: Capsule())
          Button {
            send()
          } label: {
            Image(systemName: "arrow.up")
              .font(.body.weight(.bold))
              .foregroundStyle(palette.accentForeground)
              .frame(width: 42, height: 42)
              .background(palette.accent, in: Circle())
          }
          .buttonStyle(.plain)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
      }
      .navigationTitle("chat.thread")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
    .accessibilityIdentifier("ui_s6_thread_replies")
  }

  private func send() {
    let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    draft = ""
    Task {
      _ = await model.chatStore.sendMessage(
        to: thread.id,
        content: content,
        replyToID: parent.id
      )
    }
  }
}
