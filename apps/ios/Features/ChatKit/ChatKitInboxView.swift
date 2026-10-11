import Foundation
import SwiftUI

/// ChatKit — the rebuilt chat experience. This is the new conversation list:
/// a Signal/Telegram-grade inbox built fresh on top of the proven ChatStore
/// networking layer (WebSocket realtime, idempotent send, optimistic updates).
/// It is deliberately decoupled from the legacy ChatsView so it can be swapped
/// in once the new thread + composer screens land.
struct ChatKitInboxView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var searchText = ""
  @State private var scope: ChatKitScope = .chats
  @State private var showsNewConversation = false
  @State private var pendingDelete: ChatThread?
  @State private var storyRails: [MaxStoryRail]?
  @State private var storyViewerStart: StoryViewerStart?

  private enum ChatKitScope: Hashable { case chats, mentions }

  /// The rail index the viewer opens on, boxed for `fullScreenCover(item:)`.
  private struct StoryViewerStart: Identifiable {
    let railIndex: Int
    var id: Int { railIndex }
  }

  /// Invoked when the user taps a conversation. The host provides navigation so
  /// this view stays presentation-only.
  var onOpen: (ChatThread) -> Void
  /// When set (e.g. the preview presentation), a close control appears in the header.
  var onClose: (() -> Void)?

  private var store: ChatStore { model.chatStore }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        header

        if scope == .chats, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          if let storyRails, !storyRails.isEmpty {
            ChatKitStoriesRail(rails: storyRails) { index in
              storyViewerStart = StoryViewerStart(railIndex: index)
            }
          }
          savedMessagesRow
          Divider()
            .padding(.leading, 84)
            .opacity(0.4)
        }

        if scope == .mentions {
          mentionsContent
        } else if store.threads.value == nil {
          if case .failed(let message) = store.threads {
            MaxLoadFailureView(message: message) {
              Task { await store.loadThreads() }
            }
            .padding(.top, MaxSpace.xl)
          } else {
            loadingState
          }
        } else if visibleThreads.isEmpty {
          emptyState
        } else {
          ForEach(visibleThreads) { thread in
            Button { open(thread) } label: {
              ChatKitConversationRow(
                thread: thread,
                isTyping: store.typingUserIDByChat[thread.id] != nil,
                isLocked: model.chatLockStore.isLocked(thread.id)
              )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_chatkit_thread_\(thread.id)")
            .contextMenu { rowActions(for: thread) }

            if thread.id != visibleThreads.last?.id {
              Divider()
                .padding(.leading, 84)
                .opacity(0.4)
            }
          }
        }
      }
      .padding(.bottom, MaxSpace.tabBarClearance)
    }
    .scrollDismissesKeyboard(.immediately)
    .refreshable {
      if scope == .mentions { await store.loadActivity() } else { await store.loadThreads() }
    }
    .task {
      guard !model.isUITestMode, store.threads.value == nil else { return }
      await store.loadThreads()
    }
    .task {
      guard storyRails == nil else { return }
      await loadStories()
    }
    .task(id: scope) {
      guard scope == .mentions, store.activity.value == nil else { return }
      await store.loadActivity()
    }
    .maxScreenBackground()
    .sheet(isPresented: $showsNewConversation) {
      ChatKitNewConversationView { thread in
        showsNewConversation = false
        onOpen(thread)
      }
    }
    .fullScreenCover(item: $storyViewerStart) { start in
      ChatKitStoryViewer(rails: storyRails ?? [], startRailIndex: start.railIndex) {
        storyViewerStart = nil
        // Reload so the rings the viewer just marked seen lose their accent.
        Task { await loadStories() }
      }
    }
    .confirmationDialog(
      "Delete conversation?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      presenting: pendingDelete
    ) { thread in
      Button("Delete", role: .destructive) {
        Task { _ = await store.deleteChat(thread.id) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { thread in
      Text(verbatim: "\"\(thread.displayTitle)\" will be removed from your inbox.")
    }
    .accessibilityIdentifier("ui_chatkit_inbox")
  }

  /// Navigates to the thread, demanding device-owner authentication first for
  /// a chat the user has locked.
  private func open(_ thread: ChatThread) {
    guard model.chatLockStore.needsUnlock(thread.id) else {
      onOpen(thread)
      return
    }
    Task {
      if await model.chatLockStore.unlock(thread.id) {
        onOpen(thread)
      }
    }
  }

  /// The fixed entry above the conversation list: the caller's own notebook.
  /// Tapping it asks the server for the self-conversation (created on first
  /// use) and navigates into it like any other thread.
  private var savedMessagesRow: some View {
    Button(action: openSavedMessages) {
      HStack(spacing: MaxSpace.sm) {
        ZStack {
          Circle().fill(MaxColor.accent.opacity(0.18))
          Image(systemName: "bookmark.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(MaxColor.accent)
        }
        .frame(width: 56, height: 56)

        VStack(alignment: .leading, spacing: 3) {
          Text("Saved Messages")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
          Text("Notes, links and files — just for you.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ui_chatkit_saved_messages")
  }

  private func openSavedMessages() {
    Task {
      if let thread = await store.openSavedMessages() {
        open(thread)
      }
    }
  }

  /// Loads the story rails; a failure leaves the rail hidden, matching the
  /// desktop's silent fallback.
  private func loadStories() async {
    storyRails = (try? await model.apiClient.stories()) ?? []
  }

  private var visibleThreads: [ChatThread] {
    let all = store.threads.value ?? []
    let active = all.filter { $0.isArchived != true }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return active }
    return active.filter {
      $0.displayTitle.localizedCaseInsensitiveContains(query)
        || $0.lastMessage.localizedCaseInsensitiveContains(query)
    }
  }

  @ViewBuilder
  private func rowActions(for thread: ChatThread) -> some View {
    if thread.unreadCount > 0 {
      Button {
        Task { await store.markRead(thread.id) }
      } label: {
        Label("Mark as read", systemImage: "checkmark.circle")
      }
    }
    Button {
      Task {
        await store.updatePreference(
          for: thread.id,
          isMuted: !(thread.isMuted ?? false),
          isArchived: thread.isArchived ?? false
        )
      }
    } label: {
      Label(
        thread.isMuted == true ? "Unmute" : "Mute",
        systemImage: thread.isMuted == true ? "bell" : "bell.slash"
      )
    }
    Button {
      Task {
        await store.updatePreference(
          for: thread.id,
          isMuted: thread.isMuted ?? false,
          isArchived: !(thread.isArchived ?? false)
        )
      }
    } label: {
      Label(
        thread.isArchived == true ? "Unarchive" : "Archive",
        systemImage: "archivebox"
      )
    }
    Divider()
    Button(role: .destructive) {
      pendingDelete = thread
    } label: {
      Label("Delete Conversation", systemImage: "trash")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      HStack {
        Text("Chats")
          .font(.largeTitle.bold())
          .foregroundStyle(.primary)
        Spacer()
        Button {
          showsNewConversation = true
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.title3)
            .foregroundStyle(MaxColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_chatkit_new_conversation")
        .accessibilityLabel(Text("New chat"))
        if let onClose {
          Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Close"))
        }
      }

      searchField

      Picker("", selection: $scope) {
        Text("Chats").tag(ChatKitScope.chats)
        Text("Mentions").tag(ChatKitScope.mentions)
      }
      .pickerStyle(.segmented)
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.top, MaxSpace.sm)
    .padding(.bottom, MaxSpace.md)
  }

  private var searchField: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search", text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: .capsule)
  }

  private var loadingState: some View {
    ProgressView()
      .controlSize(.large)
      .frame(maxWidth: .infinity, minHeight: 240)
  }

  private var emptyState: some View {
    MaxEmptyState(
      title: searchText.isEmpty ? "No conversations yet" : "No matches",
      subtitle: searchText.isEmpty
        ? "Start a new chat to see it here."
        : "Try a different search.",
      symbol: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass"
    )
    .padding(.top, MaxSpace.xl)
  }

  // MARK: - Mentions

  private var activities: [ChatActivity] { store.activity.value ?? [] }

  @ViewBuilder
  private var mentionsContent: some View {
    if store.activity.isLoading, activities.isEmpty {
      loadingState
    } else if activities.isEmpty {
      MaxEmptyState(
        title: "No mentions yet",
        subtitle: "Replies and mentions to you show up here.",
        symbol: "at"
      )
      .padding(.top, MaxSpace.xl)
    } else {
      ForEach(activities) { activity in
        Button { openActivity(activity) } label: { activityRow(activity) }
          .buttonStyle(.plain)
        Divider().padding(.leading, 72).opacity(0.4)
      }
    }
  }

  private func activityRow(_ activity: ChatActivity) -> some View {
    HStack(spacing: MaxSpace.sm) {
      ChatKitAvatar(
        url: activity.actorAvatar,
        title: activity.actorName ?? "",
        isGroup: activity.isGroup ?? false
      )
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(activity.actorName ?? "Someone")
            .font(.subheadline.weight(activity.readAt == nil ? .semibold : .regular))
            .foregroundStyle(.primary)
          Spacer()
          Text(ChatKitTime.short(activity.createdAt))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(activity.content ?? activityKindLabel(activity.kind))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }

  private func activityKindLabel(_ kind: String) -> String {
    switch kind {
    case "mention": return "mentioned you"
    case "reply": return "replied to you"
    case "reaction": return "reacted to your message"
    default: return "new activity"
    }
  }

  private func openActivity(_ activity: ChatActivity) {
    Task { await store.markActivityRead([activity]) }
    if let thread = (store.threads.value ?? []).first(where: { $0.id == activity.dmId }) {
      open(thread)
    }
  }
}

/// A single conversation row: avatar, title, last-message preview (or a live
/// "typing…" indicator), timestamp, and an unread badge / mute glyph.
struct ChatKitConversationRow: View {
  let thread: ChatThread
  var isTyping: Bool = false
  /// A locked thread hides its preview text behind a lock glyph.
  var isLocked: Bool = false

  private var isUnread: Bool { thread.unreadCount > 0 }

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      ChatKitAvatar(url: thread.avatarUrl, title: thread.displayTitle, isGroup: thread.isGroup)
        .frame(width: 56, height: 56)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(thread.displayTitle)
            .font(.body.weight(isUnread ? .semibold : .regular))
            .foregroundStyle(.primary)
            .lineLimit(1)
          if thread.isMuted == true {
            Image(systemName: "bell.slash.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 4)
          Text(ChatKitTime.short(thread.lastMessageAt))
            .font(.caption)
            .foregroundStyle(isUnread ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
        }

        HStack(alignment: .top, spacing: 6) {
          previewText
            .font(.subheadline)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

          if isUnread {
            Text(thread.unreadCount > 99 ? "99+" : "\(thread.unreadCount)")
              .font(.caption2.bold())
              .foregroundStyle(.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(MaxColor.accent, in: Capsule())
          }
        }
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var previewText: some View {
    if isLocked {
      Label("Locked", systemImage: "lock.fill")
        .foregroundStyle(.secondary)
    } else if isTyping {
      Text("typing…")
        .foregroundStyle(MaxColor.accent)
        .italic()
    } else {
      Text(thread.lastMessage.isEmpty ? " " : thread.lastMessage)
        .foregroundStyle(isUnread ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
  }
}

/// Circular avatar backed by the cached, auth-aware image loader, falling back
/// to tinted initials when there is no image.
struct ChatKitAvatar: View {
  let url: URL?
  let title: String
  var isGroup: Bool = false

  var body: some View {
    ZStack {
      Circle().fill(fallbackGradient)
      if isGroup, url == nil {
        Image(systemName: "person.2.fill")
          .foregroundStyle(.white.opacity(0.9))
          .font(.system(size: 20, weight: .semibold))
      } else {
        Text(initials)
          .foregroundStyle(.white)
          .font(.system(size: 20, weight: .semibold))
      }
      if let url {
        MaxAsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            Color.clear
          }
        }
      }
    }
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
  }

  private var initials: String {
    let parts = title.split(separator: " ").prefix(2)
    let letters = parts.compactMap { $0.first.map(String.init) }.joined()
    return letters.isEmpty ? "?" : letters.uppercased()
  }

  private var fallbackGradient: LinearGradient {
    // Deterministic tint from the title so each contact keeps a stable colour
    // across launches (Swift's hashValue is per-run randomised, so sum scalars).
    let seed = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    let hue = Double(seed % 360) / 360.0
    let base = Color(hue: hue, saturation: 0.55, brightness: 0.75)
    let dark = Color(hue: hue, saturation: 0.6, brightness: 0.55)
    return LinearGradient(colors: [base, dark], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

/// Compact, chat-list-style relative timestamps ("now", "5m", "3h", "Mon", date).
enum ChatKitTime {
  // ISO8601DateFormatter / DateFormatter are reference types that are not
  // Sendable; these are created once and only ever read, so nonisolated(unsafe)
  // is the correct, safe escape hatch under Swift 6 complete concurrency.
  nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()
  nonisolated(unsafe) private static let weekday: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
  }()
  nonisolated(unsafe) private static let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .none
    return f
  }()
  nonisolated(unsafe) private static let clockTime: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()
  nonisolated(unsafe) private static let daySeparator: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  /// "3:04 PM" — used on message bubbles.
  static func clock(_ raw: String?) -> String {
    guard let date = date(raw) else { return "" }
    return clockTime.string(from: date)
  }

  /// "Today" / "Yesterday" / "12 Jan 2026" — used for day separators.
  static func daySeparatorLabel(_ raw: String?) -> String {
    guard let date = date(raw) else { return "" }
    if Calendar.current.isDateInToday(date) { return "Today" }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    return daySeparator.string(from: date)
  }

  /// Whole-day key so consecutive messages on the same day group under one header.
  static func dayKey(_ raw: String?) -> String {
    guard let date = date(raw) else { return "" }
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
  }

  static func date(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return iso.date(from: raw) ?? isoPlain.date(from: raw)
  }

  /// "30s" / "5m" / "1h" / "1d" / "1w" — compact whole-unit duration, used by
  /// the disappearing-messages chips and the timer setting.
  static func compactDuration(_ seconds: Int) -> String {
    let total = max(seconds, 0)
    if total < 60 { return "\(total)s" }
    if total < 3600 { return "\(total / 60)m" }
    if total < 86_400 { return "\(total / 3600)h" }
    if total < 7 * 86_400 { return "\(total / 86_400)d" }
    return "\(total / (7 * 86_400))w"
  }

  static func short(_ raw: String?) -> String {
    guard let date = date(raw) else { return "" }
    let seconds = -date.timeIntervalSinceNow
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    if seconds < 7 * 86_400 { return weekday.string(from: date) }
    return shortDate.string(from: date)
  }
}
