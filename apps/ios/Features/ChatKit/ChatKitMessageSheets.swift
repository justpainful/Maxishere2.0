import SwiftUI

/// Pick a conversation to forward a message into.
struct ChatKitForwardSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let message: ChatMessage
  let sourceThreadID: String

  @State private var busyTargetID: String?

  private var store: ChatStore { model.chatStore }
  private var targets: [ChatThread] {
    (store.threads.value ?? []).filter { $0.id != sourceThreadID }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0) {
          if targets.isEmpty {
            MaxEmptyState(
              title: "No conversations",
              subtitle: "Start a chat first, then forward messages into it.",
              symbol: "arrowshape.turn.up.right"
            )
            .padding(.top, MaxSpace.xl)
          } else {
            ForEach(targets) { thread in
              Button { forward(to: thread) } label: {
                HStack(spacing: MaxSpace.sm) {
                  ChatKitAvatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
                    .frame(width: 44, height: 44)
                  Text(thread.title).foregroundStyle(.primary)
                  Spacer()
                  if busyTargetID == thread.id {
                    ProgressView()
                  }
                }
                .padding(.horizontal, MaxSpace.md)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(busyTargetID != nil)
              Divider().padding(.leading, 72).opacity(0.4)
            }
          }
        }
      }
      .navigationTitle("Forward to")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
      }
      .maxScreenBackground()
    }
  }

  private func forward(to thread: ChatThread) {
    guard busyTargetID == nil else { return }
    busyTargetID = thread.id
    Task {
      let ok = await store.forwardMessage(message.id, from: sourceThreadID, to: thread.id)
      busyTargetID = nil
      if ok { dismiss() }
    }
  }
}

/// Search within a conversation and jump to a result.
struct ChatKitSearchSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let threadID: String
  var onSelect: (String) -> Void

  @State private var searchText = ""

  private var store: ChatStore { model.chatStore }
  private var results: [ChatMessage] { store.searchResultsByChat[threadID]?.value ?? [] }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0) {
          if store.searchResultsByChat[threadID]?.isLoading == true {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 160)
          } else if searchText.isEmpty {
            MaxEmptyState(title: "Search messages", subtitle: "Find any message in this conversation.", symbol: "magnifyingglass")
              .padding(.top, MaxSpace.xl)
          } else if results.isEmpty {
            MaxEmptyState(title: "No results", subtitle: "Try a different search.", symbol: "magnifyingglass")
              .padding(.top, MaxSpace.xl)
          } else {
            ForEach(results) { message in
              Button { onSelect(message.id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                  HStack {
                    Text(message.sender?.displayName ?? "")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(MaxColor.accent)
                    Spacer()
                    Text(ChatKitTime.short(message.createdAt))
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                  Text(message.content ?? "Media")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, MaxSpace.md)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              Divider().opacity(0.4)
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "Search this chat")
      .navigationTitle("Search")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
      }
      .task(id: searchText) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        await store.searchMessages(in: threadID, query: query)
      }
      .maxScreenBackground()
    }
  }
}
