import SwiftUI

struct PlayerSendToChatSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let item: MaxMediaItem

  @State private var sendingThreadID: String?
  @State private var presentedError: ProductError?

  private var threads: [ChatThread] {
    model.chatStore.threads.value ?? []
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: MaxSpace.sm) {
          if let presentedError {
            PlayerActionErrorView(error: presentedError)
          }

          if threads.isEmpty {
            emptyOrLoading
          } else {
            ForEach(threads) { thread in
              Button { send(to: thread) } label: {
                HStack(spacing: MaxSpace.md) {
                  MaxAvatar(name: thread.title, imageURL: thread.avatarUrl)
                  VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                    Text(verbatim: thread.title)
                      .font(.body.weight(.semibold))
                      .foregroundStyle(MaxColor.textPrimary)
                    Text("player.send_to_chat.subtitle")
                      .font(.caption)
                      .foregroundStyle(MaxColor.textSecondary)
                  }
                  Spacer(minLength: 0)
                  if sendingThreadID == thread.id {
                    ProgressView()
                  } else {
                    Image(systemName: "paperplane.fill")
                      .foregroundStyle(MaxColor.accent)
                  }
                }
                .padding(MaxSpace.md)
                .background(
                  MaxColor.surface,
                  in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
                )
              }
              .buttonStyle(.plain)
              .disabled(sendingThreadID != nil)
              .accessibilityIdentifier(
                "ui_player_send_chat_\(thread.id.maxAccessibilityToken)"
              )
            }
          }
        }
        .padding(MaxSpace.md)
      }
      .navigationTitle("player.send_to_chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel", action: dismiss.callAsFunction)
        }
      }
      .task {
        guard model.chatStore.threads.value == nil else { return }
        await model.chatStore.loadThreads(loadSelectedMessages: false)
      }
      .accessibilityIdentifier("ui_player_send_chat_sheet")
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private var emptyOrLoading: some View {
    if model.chatStore.threads.isLoading {
      HStack(spacing: MaxSpace.sm) {
        ProgressView()
        Text("chats.loading")
      }
      .frame(maxWidth: .infinity, minHeight: 100)
    } else {
      ContentUnavailableView(
        "chats.empty.title",
        systemImage: "bubble.left.and.bubble.right",
        description: Text("chats.empty.subtitle")
      )
    }
  }

  private func send(to thread: ChatThread) {
    sendingThreadID = thread.id
    presentedError = nil
    Task {
      let message = await model.chatStore.sendMessage(
        to: thread.id,
        mediaFileIDs: [item.id]
      )
      if message != nil {
        dismiss()
      } else {
        presentedError = ProductError(
          area: .chats,
          code: .unknown,
          title: String(localized: "error.product.chat_send.title"),
          reason: String(localized: "error.product.chat_send.reason"),
          recoverySuggestion: String(localized: "error.product.retry")
        )
      }
      sendingThreadID = nil
    }
  }
}

struct PlayerActionErrorView: View {
  let error: ProductError

  var body: some View {
    MaxContentSurface {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        Label(error.title, systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(MaxColor.warning)
        Text(verbatim: error.reason)
          .font(.subheadline)
          .foregroundStyle(MaxColor.textSecondary)
        DisclosureGroup("error.support_details") {
          Text(verbatim: error.supportDetails)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(.top, MaxSpace.xs)
        }
      }
    }
  }
}
