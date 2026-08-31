import SwiftUI

/// The chat workspace uses one navigation stack and the app-level tab bar only.
/// Inbox, mentions and archive are scopes inside Chats, not nested applications.
struct ChatsV3App: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  var tab: ChatsV3Tab { model.chatsV3Store.selectedTab }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Group {
          switch tab {
          case .inbox:
            ChatsV3InboxView()
          case .mentions:
            ChatsV3ActivityView()
          case .archive:
            ChatsV3InboxView(archiveOnly: true)
          }
        }
        .id(tab)
      }
    }
    .tint(MaxColor.accent)
    // Chats is a root destination, so it must participate in the same
    // semantic canvas/surface system as Vault, Library, Shared and Profile.
    // Without this, the native List background hides the selected core theme
    // and only button tint appears to change.
    .maxTabContent()
    .accessibilityIdentifier("ui_chats_v3_app")
    .task {
      if model.chatsV3Store.inbox.value == nil { await model.chatsV3Store.loadInbox() }
      if model.chatsV3Store.activity.value == nil { await model.chatsV3Store.loadActivity() }
    }
  }
}

struct ShimmerChatListPlaceholder: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var isShimmering = false

  private var suppressesMotion: Bool { reduceMotion || !motionEnabled }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ForEach(0..<8) { _ in
          HStack(spacing: 12) {
            Circle()
              .fill(Color.primary.opacity(0.08))
              .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 8) {
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 140, height: 16)
              
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 12)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.primary.opacity(0.05))
              .frame(width: 40, height: 12)
          }
          .padding(.horizontal, MaxSpace.md)
        }
      }
      .padding(.top, MaxSpace.md)
    }
    .disabled(true)
    // A `repeatForever` animation driven from `onAppear` onto a numeric phase
    // never stops and keeps the view invalidating; binding it to a Bool with
    // `.animation(_:value:)` lets SwiftUI tear it down with the view.
    .opacity(suppressesMotion ? 0.6 : (isShimmering ? 0.85 : 0.4))
    .animation(
      suppressesMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
      value: isShimmering
    )
    .onAppear { if !suppressesMotion { isShimmering = true } }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("common.loading"))
    .accessibilityAddTraits(.updatesFrequently)
  }
}

private struct ChatsV3InboxView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @State private var searchText = ""
  let archiveOnly: Bool

  init(archiveOnly: Bool = false) {
    self.archiveOnly = archiveOnly
  }

  private var threads: [ChatThread] {
    (model.chatsV3Store.inbox.value ?? []).filter { thread in
      let matchesArchive = (thread.isArchived ?? false) == archiveOnly
      guard matchesArchive else { return false }
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      return query.isEmpty
        || thread.title.localizedCaseInsensitiveContains(query)
        || thread.lastMessage.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    Group {
      if model.chatsV3Store.inbox.isLoading && model.chatsV3Store.inbox.value == nil {
        ShimmerChatListPlaceholder()
      } else if let error = model.chatsV3Store.inbox.errorMessage {
        ContentUnavailableView(
          "chats.unavailable",
          systemImage: "exclamationmark.bubble",
          description: Text(error)
        )
      } else if threads.isEmpty {
        ContentUnavailableView(
          archiveOnly ? "chats.archive.empty" : "chats.inbox.empty",
          systemImage: archiveOnly ? "archivebox" : "bubble.left.and.bubble.right",
          description: Text(
            archiveOnly
              ? "chats.archive.empty.subtitle"
              : "chats.inbox.empty.subtitle"
          )
        )
      } else {
        List(threads) { thread in
          NavigationLink(value: thread) {
            ChatsV3ThreadRow(thread: thread)
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
              Task { _ = await model.chatsV3Store.deleteChat(thread.id) }
            } label: {
              Label("action.delete", systemImage: "trash")
            }

            Button {
              Task {
                await model.chatsV3Store.updatePreference(
                  chatID: thread.id,
                  isMuted: thread.isMuted ?? false,
                  isArchived: !(thread.isArchived ?? false)
                )
              }
            } label: {
              Label(
                thread.isArchived == true ? "chat.unarchive" : "chat.archive",
                systemImage: thread.isArchived == true ? "tray.and.arrow.up" : "archivebox"
              )
            }
            .tint(MaxColor.accent)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowBackground(palette.primaryContentSurface.opacity(0.88))
      }
    }
    .navigationTitle(archiveOnly ? "chat.archive" : "chats.title")
    .navigationBarTitleDisplayMode(.large)
    .navigationDestination(for: ChatThread.self) { thread in
      ChatsV3ConversationView(thread: thread)
    }
    .searchable(text: $searchText, prompt: Text("chats.search.prompt"))
    .toolbar {
      if !archiveOnly {
        ToolbarItem(placement: .topBarTrailing) {
          Button("chat.new.title", systemImage: "square.and.pencil") { model.chatsV3Store.showsNewChatSheet = true }
            .accessibilityIdentifier("ui_chats_v3_new_chat")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("common.refresh", systemImage: "arrow.clockwise") {
          Task { await model.chatsV3Store.loadInbox() }
        }
      }
    }
    .sheet(isPresented: Binding(
      get: { model.chatsV3Store.showsNewChatSheet },
      set: { model.chatsV3Store.showsNewChatSheet = $0 }
    )) { ChatsV3NewChatSheet() }
    .refreshable { await model.chatsV3Store.loadInbox() }
  }
}

private struct ChatsV3ThreadRow: View {
  let thread: ChatThread

  var body: some View {
    HStack(spacing: 12) {
      ChatsV3Avatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(thread.title)
            .font(.headline)
            .lineLimit(1)
          if thread.isMuted == true {
            Image(systemName: "bell.slash.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          if let date = thread.lastMessageAt, !date.isEmpty {
            Text(ChatsV3TimeFormatter.inbox(date))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Text(thread.lastMessage.isEmpty ? String(localized: "chats.thread.no_messages") : thread.lastMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if thread.unreadCount > 0 {
        Text(thread.unreadCount.formatted())
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .padding(7)
          .background(MaxColor.accent, in: Circle())
      }
    }
    .padding(.vertical, 5)
  }
}

private struct ChatsV3ActivityView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Group {
      if model.chatsV3Store.activity.isLoading && model.chatsV3Store.activity.value == nil {
        ShimmerChatListPlaceholder()
      } else if let error = model.chatsV3Store.activity.errorMessage {
        ContentUnavailableView(
          "chats.mentions.unavailable",
          systemImage: "at.badge.minus",
          description: Text(error)
        )
      } else if let items = model.chatsV3Store.activity.value, !items.isEmpty {
        List(items) { item in
          NavigationLink(value: ChatsV3ActivityRoute(item: item)) {
            HStack(spacing: 12) {
              ChatsV3Avatar(url: item.actorAvatar, title: item.actorName ?? "@", isGroup: false)
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  Text("\(item.actorName ?? "Someone") mentioned you")
                    .font(.headline)
                    .lineLimit(1)
                  Spacer(minLength: 8)
                  if let createdAt = item.createdAt {
                    Text(ChatsV3TimeFormatter.inbox(createdAt))
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
                Text(item.content ?? String(localized: "chats.mentions.open_to_view"))
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              if item.readAt == nil {
                Circle().fill(MaxColor.accent).frame(width: 8, height: 8)
              }
            }
            .padding(.vertical, 4)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowBackground(palette.primaryContentSurface.opacity(0.88))
      } else {
        ContentUnavailableView(
          "No mentions",
          systemImage: "at",
          description: Text("chat.mentions.empty")
        )
      }
    }
    .navigationTitle("chat.mentions")
    .navigationBarTitleDisplayMode(.large)
    .navigationDestination(for: ChatsV3ActivityRoute.self) { route in
      ChatsV3ActivityDestination(item: route.item)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("common.mark_read", systemImage: "checkmark.circle") {
          Task { await model.chatsV3Store.markActivityRead(model.chatsV3Store.activity.value ?? []) }
        }
      }
    }
    .refreshable { await model.chatsV3Store.loadActivity() }
  }
}

private struct ChatsV3ActivityRoute: Hashable {
  let item: ChatActivity
}

private struct ChatsV3ActivityDestination: View {
  @Environment(MaxAppModel.self) private var model
  let item: ChatActivity

  var body: some View {
    if let thread = model.chatsV3Store.inbox.value?.first(where: { $0.id == item.dmId }) {
      ChatsV3ConversationView(thread: thread)
    } else {
      ContentUnavailableView("Chat not available", systemImage: "bubble.left.and.exclamationmark")
    }
  }
}

struct ChatsV3Avatar: View {
  let url: URL?
  let title: String
  let isGroup: Bool

  var body: some View {
    Group {
      if let url {
        MaxAsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Color.secondary.opacity(0.16)
        }
      } else {
        Image(systemName: isGroup ? "person.3.fill" : "person.fill")
          .font(.title3)
          .foregroundStyle(MaxColor.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(MaxColor.accent.opacity(0.12))
      }
    }
    .frame(width: 46, height: 46)
    .clipShape(Circle())
    .accessibilityLabel(title)
  }
}
