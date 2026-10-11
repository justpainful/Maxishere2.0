@preconcurrency import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Chats is one screen with two scopes rather than two applications. Archive is
/// reached from inside the inbox list, which already renders it.
private enum ChatsScope: String, CaseIterable, Identifiable {
  case inbox
  case mentions

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .inbox: "chats.inbox"
    case .mentions: "chat.mentions"
    }
  }
}

struct ChatsView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var searchText = ""
  @State private var showsNewConversation = false
  @State private var openedThread: ChatThread?
  @State private var showsChatKitPreview = false
  @State private var scope: ChatsScope = .inbox
  @State private var showsUnreadOnly = false

  var body: some View {
    VStack(spacing: 0) {
      scopePicker
      Group {
        switch scope {
        case .inbox: inboxContent
        case .mentions:
          ChatsMentionsList { thread in openedThread = thread }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle("tab.chats")
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "chats.search"
    )
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        MaxAccessRequestsToolbarButton()

        if scope == .inbox {
          Button {
            withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
              showsUnreadOnly.toggle()
            }
          } label: {
            Label(
              "chats.unread",
              systemImage: showsUnreadOnly
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            )
          }
          .accessibilityAddTraits(showsUnreadOnly ? .isSelected : [])
          .accessibilityIdentifier("ui_chats_unread_filter")

          Button("chat.new.title", systemImage: "square.and.pencil") {
            showsNewConversation = true
          }
          .accessibilityIdentifier("ui_s6_new_conversation_button")
        }

        Button("common.refresh", systemImage: "arrow.clockwise") {
          Task { await refresh() }
        }
        .accessibilityIdentifier("ui_chats_refresh")

        // Preview of the rebuilt ChatKit experience while it reaches parity.
        Button("New chat UI (preview)", systemImage: "sparkles") {
          showsChatKitPreview = true
        }
        .accessibilityIdentifier("ui_chatkit_preview_button")
      }
    }
    .fullScreenCover(isPresented: $showsChatKitPreview) {
      ChatKitApp(onClose: { showsChatKitPreview = false })
    }
    .sheet(isPresented: $showsNewConversation) {
      MaxS6NewConversationSheet { thread in
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(180))
          openedThread = thread
        }
      }
    }
    .navigationDestination(item: $openedThread) { thread in
      ChatDetailView(thread: thread)
    }
    .refreshable { await refresh() }
    .task {
      guard !model.isUITestMode else { return }
      if model.chatStore.threads.value == nil {
        await model.chatStore.loadThreads()
      }
      if model.chatStore.accessRequests.value == nil {
        await model.chatStore.loadAccessRequests()
      }
      if model.chatStore.activity.value == nil {
        await model.chatStore.loadActivity()
      }
    }
    .scrollContentBackground(.hidden)
    .maxTabContent()
    .councilLight(.chats)
    .accessibilityIdentifier("ui_chats_screen")
  }

  private var scopePicker: some View {
    Picker("tab.chats", selection: $scope) {
      ForEach(ChatsScope.allCases) { value in
        Text(value.titleKey).tag(value)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .padding(.horizontal, MaxSpace.md)
    .padding(.bottom, MaxSpace.xs)
    .accessibilityIdentifier("ui_chats_scope")
  }

  @ViewBuilder
  private var inboxContent: some View {
    let isCouncil = appTheme == .council
    if let threads = model.chatStore.threads.value {
      let visible = filtered(threads)
      if visible.isEmpty {
        if isCouncil {
          CouncilEmptyState(
            symbol: emptyStateSymbol,
            title: emptyStateTitle,
            subtitle: emptyStateSubtitle
          )
        } else {
          MaxEmptyState(
            title: emptyStateTitle,
            subtitle: emptyStateSubtitle,
            symbol: emptyStateSymbol
          )
        }
      } else {
        MaxS6ChannelList(threads: visible) { thread in
          ChatDetailView(thread: thread)
        } markRead: { thread in
          Task { await model.chatStore.markRead(thread.id) }
        }
      }
    } else if model.chatStore.threads.isLoading {
      ChatThreadListPlaceholder()
    } else if let error = model.chatStore.threads.errorMessage {
      MaxLoadFailureView(message: error) {
        Task { await model.chatStore.loadThreads() }
      }
    } else {
      if isCouncil {
        CouncilEmptyState(
          symbol: "bubble.left.and.bubble.right",
          title: "chats.empty.title",
          subtitle: "chats.empty.subtitle"
        )
      } else {
        MaxEmptyState(
          title: "chats.empty.title",
          subtitle: "chats.empty.subtitle",
          symbol: "bubble.left.and.bubble.right"
        )
      }
    }
  }

  private var isFiltering: Bool {
    !searchText.isEmpty || showsUnreadOnly
  }

  private var emptyStateSymbol: String {
    isFiltering ? "magnifyingglass" : "bubble.left.and.bubble.right"
  }

  private var emptyStateTitle: LocalizedStringKey {
    isFiltering ? "search.empty.title" : "chats.empty.title"
  }

  private var emptyStateSubtitle: LocalizedStringKey {
    isFiltering ? "search.empty.subtitle" : "chats.empty.subtitle"
  }

  private func refresh() async {
    await model.chatStore.loadThreads()
    await model.chatStore.loadAccessRequests()
    await model.chatStore.loadActivity()
  }

  private func filtered(_ threads: [ChatThread]) -> [ChatThread] {
    let matches = MaxChatUIAdapter.filteredThreads(threads, query: searchText)
    // The archived sub-list is a child of the inbox list, so an archived thread
    // must survive the unread filter to remain reachable.
    guard showsUnreadOnly else { return matches }
    return matches.filter { $0.unreadCount > 0 || $0.isArchived == true }
  }
}

/// The mentions / activity feed. The server records one row per member per
/// message, so this deliberately shows who acted and what was said rather than
/// asserting that every row is a mention of the reader.
private struct ChatsMentionsList: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let open: (ChatThread) -> Void

  private var activities: [ChatActivity] {
    model.chatStore.activity.value ?? []
  }

  var body: some View {
    Group {
      if activities.isEmpty {
        if model.chatStore.activity.isLoading {
          ChatThreadListPlaceholder()
        } else if let error = model.chatStore.activity.errorMessage {
          MaxLoadFailureView(message: error) {
            Task { await model.chatStore.loadActivity() }
          }
        } else {
          MaxEmptyState(
            title: "chat.mentions",
            subtitle: "chat.mentions.empty",
            symbol: "at"
          )
        }
      } else {
        List(activities) { item in
          Button {
            guard let thread = model.chatStore.threads.value?.first(where: {
              $0.id == item.dmId
            }) else { return }
            Task { await model.chatStore.markActivityRead([item]) }
            open(thread)
          } label: {
            ChatActivityRow(activity: item)
          }
          .buttonStyle(.plain)
          .listRowBackground(palette.canvas)
          .accessibilityIdentifier("ui_chat_activity_\(item.id)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .toolbar {
      if !activities.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button("common.mark_read", systemImage: "checkmark.circle") {
            Task { await model.chatStore.markActivityRead(activities) }
          }
          .accessibilityIdentifier("ui_chat_activity_mark_read")
        }
      }
    }
    .task {
      guard !model.isUITestMode, model.chatStore.activity.value == nil else { return }
      await model.chatStore.loadActivity()
    }
  }
}

private struct ChatActivityRow: View {
  @Environment(\.maxThemePalette) private var palette
  let activity: ChatActivity

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      MaxAvatar(
        name: activity.actorName ?? activity.actorId,
        imageURL: activity.actorAvatar,
        size: 42
      )
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: MaxSpace.xs) {
          Text(verbatim: activity.groupName ?? activity.actorName ?? activity.actorId)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
          if let time = MaxChatUIAdapter.messageTime(for: activity.createdAt) {
            Text(verbatim: time)
              .font(.caption2)
              .foregroundStyle(palette.tertiaryText)
          }
        }
        if let content = activity.content, !content.isEmpty {
          Text(verbatim: content)
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
            .lineLimit(2)
        } else {
          Text("chats.mentions.open_to_view")
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
            .lineLimit(2)
        }
      }
      if activity.readAt == nil {
        Circle()
          .fill(palette.accent)
          .frame(width: 8, height: 8)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, MaxSpace.xxs)
  }
}

private struct ChatThreadListPlaceholder: View {
  var body: some View {
    List(0..<5, id: \.self) { index in
      HStack(spacing: MaxSpace.md) {
        Circle()
          .fill(MaxColor.surfaceStrong)
          .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: MaxSpace.xs) {
          RoundedRectangle(cornerRadius: 4)
            .fill(MaxColor.surfaceStrong)
            .frame(width: index.isMultiple(of: 2) ? 132 : 176, height: 15)
          RoundedRectangle(cornerRadius: 4)
            .fill(MaxColor.surfaceSoft)
            .frame(maxWidth: .infinity)
            .frame(height: 12)
        }
      }
      .padding(.vertical, MaxSpace.xs)
      .redacted(reason: .placeholder)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .accessibilityHidden(true)
    }
    .listStyle(.plain)
    .scrollDisabled(true)
    .scrollContentBackground(.hidden)
    .accessibilityLabel(Text("chats.loading"))
  }
}

struct MaxAccessRequestsToolbarButton: View {
  @Environment(MaxAppModel.self) private var model

  private var pendingCount: Int {
    model.chatStore.accessRequests.value?.incoming.filter {
      $0.status.lowercased() == "pending"
    }.count ?? 0
  }

  var body: some View {
    Button {
      model.openAccessRequests()
    } label: {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "lock.open")
          .frame(width: 28, height: 28)
        if pendingCount > 0 {
          Text(verbatim: min(pendingCount, 99).formatted())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 15, minHeight: 15)
            .background(MaxColor.danger, in: Capsule())
            .offset(x: 6, y: -4)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityLabel(Text("access.title"))
    .accessibilityValue(Text(verbatim: pendingCount.formatted()))
    .accessibilityIdentifier("ui_access_requests")
  }
}

private struct ChatDetailView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.dismiss) private var dismiss

  let thread: ChatThread

  @State private var replyTarget: ChatMessage?
  @State private var editingMessage: ChatMessage?
  @State private var deletingMessage: ChatMessage?
  @State private var showChatInfo = false
  @State private var forwardSelection: ChatForwardSelection?
  @State private var selectedMessageIDs = Set<String>()
  @State private var isSelectingMessages = false
  @State private var copyFeedbackTrigger = 0
  @State private var actionMessage: ChatMessage?
  @State private var threadParent: ChatMessage?
  @State private var showMessageSearch = false
  @State private var showPinnedMessages = false
  @State private var scrollTargetID: String?
  @State private var showsClearConfirmation = false
  @State private var showsDeleteConfirmation = false
  @State private var viewOnceMessage: ChatMessage?

  private var messages: [ChatMessage] {
    model.chatStore.messagesByChat[thread.id]?.value ?? []
  }

  private var chatTitle: String {
    if let partnerId = thread.partnerId {
      return model.preferencesStore.nicknames[partnerId] ?? thread.title
    }
    return thread.title
  }

  private var canDeleteSelectedMessages: Bool {
    guard !selectedMessageIDs.isEmpty, let currentUserID = model.sessionStore.user?.id else {
      return false
    }
    let selected = messages.filter { selectedMessageIDs.contains($0.id) }
    return selected.count == selectedMessageIDs.count
      && selected.allSatisfy { $0.senderId == currentUserID }
  }

  var body: some View {
    chatMainContent
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        chatPrincipalView
      }
      if isSelectingMessages {
        ToolbarItem(placement: .topBarTrailing) {
          Button("common.done", action: endSelection)
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          chatMoreMenu
        }
      }
    }
    .toolbar(.hidden, for: .tabBar)
    .sheet(isPresented: $showChatInfo) {
      ChatInfoSheet(thread: thread)
    }
    .sheet(isPresented: $showMessageSearch) {
      MaxS6MessageSearchSheet(thread: thread, onSelect: focusMessage)
    }
    .sheet(isPresented: $showPinnedMessages) {
      MaxS6PinnedMessagesSheet(thread: thread, onSelect: focusMessage)
    }
    .sheet(item: $threadParent) { parent in
      MaxS6ThreadRepliesSheet(thread: thread, parent: parent)
    }
    .sheet(item: $actionMessage) { message in
      MaxS6MessageActionSheet(
        message: message,
        isCurrentUser: message.senderId == model.sessionStore.user?.id,
        react: { reaction in
          Task {
            _ = await model.chatStore.setReaction(
              reaction,
              messageID: message.id,
              in: thread.id
            )
          }
        },
        reply: { replyTarget = message },
        copy: { copyMessage(message) },
        showThread: { presentThread(message) },
        pin: {
          Task {
            _ = await model.chatStore.setPinned(
              message.isPinned != true,
              messageID: message.id,
              in: thread.id
            )
          }
        },
        forward: {
          forwardSelection = ChatForwardSelection(messageIDs: [message.id])
        },
        edit: {
          withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
            editingMessage = message
          }
        },
        select: { beginSelection(with: message.id) },
        delete: { deletingMessage = message }
      )
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if isSelectingMessages {
        MaxS6SelectionToolbar(
          count: selectedMessageIDs.count,
          canDelete: canDeleteSelectedMessages,
          forward: {
            forwardSelection = ChatForwardSelection(messageIDs: Array(selectedMessageIDs))
          },
          delete: {
            let ids = Array(selectedMessageIDs)
            endSelection()
            if var messages = model.chatStore.messagesByChat[thread.id]?.value {
              withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
                messages.removeAll { ids.contains($0.id) }
                model.chatStore.messagesByChat[thread.id] = .loaded(messages)
              }
            }
            Task {
              await withTaskGroup(of: Void.self) { group in
                for msgID in ids {
                  group.addTask {
                    _ = await model.chatStore.deleteMessage(msgID, in: thread.id)
                  }
                }
              }
            }
          },
          cancel: endSelection
        )
      } else {
        ChatComposerView(
          thread: thread,
          replyTarget: $replyTarget,
          editingMessage: $editingMessage
        )
      }
    }
    .sheet(item: $forwardSelection) { selection in
      ChatForwardSheet(
        sourceThreadID: thread.id,
        messageIDs: selection.messageIDs
      )
    }
    .alert(
      "chat.delete.title",
      isPresented: deleteDialogPresented
    ) {
      Button("action.delete", role: .destructive) {
        if let message = deletingMessage {
          deletingMessage = nil
          Task { _ = await model.chatStore.deleteMessage(message.id, in: thread.id) }
        }
      }
      Button("common.cancel", role: .cancel) {
        deletingMessage = nil
      }
    } message: {
      Text("chat.delete.confirmation")
    }
    .alert("chat.clear_chat", isPresented: $showsClearConfirmation) {
      Button("action.delete", role: .destructive) {
        Task { _ = await model.chatStore.clearMessages(in: thread.id) }
      }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("chat.delete_chat.subtitle")
    }
    .alert("chat.delete_chat", isPresented: $showsDeleteConfirmation) {
      Button("action.delete", role: .destructive) {
        Task {
          if await model.chatStore.deleteChat(thread.id) { dismiss() }
        }
      }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("chat.delete_chat.subtitle")
    }
    .fullScreenCover(item: $viewOnceMessage) { message in
      viewOnceViewer(message)
    }
    .sensoryFeedback(.success, trigger: copyFeedbackTrigger)
    .task(id: thread.id) {
      model.chatStore.selectedThreadID = thread.id
      if !model.isUITestMode,
         model.chatStore.messagesByChat[thread.id]?.value == nil {
        await model.chatStore.loadMessages(for: thread.id)
      }
      await model.chatStore.markRead(thread.id)
      if thread.unreadCount > 0 {
        await model.chatStore.loadThreads(loadSelectedMessages: false)
      }
    }
    .task(id: "chat-poll-\(thread.id)") {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, !model.chatStore.isRealtimeConnected else { continue }
        await model.chatStore.refreshMessages(for: thread.id)
      }
    }
    .onAppear { model.chatStore.startRealtime(for: thread.id) }
    .onDisappear { model.chatStore.stopRealtime() }
    .maxScreenBackground()
    .accessibilityIdentifier("ui_chat_detail")
  }

  @ViewBuilder
  private var chatPrincipalView: some View {
    Button { showChatInfo = true } label: {
      HStack(spacing: 9) {
        MaxAvatar(name: chatTitle, imageURL: thread.avatarUrl)
          .frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: chatTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(
            model.chatStore.typingUserIDByChat[thread.id] == nil
              ? "chat.type.direct" : "chat.typing"
          )
            .font(.caption2)
            .foregroundStyle(
              model.chatStore.typingUserIDByChat[thread.id] == nil
                ? palette.secondaryText
                : palette.accent
            )
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(.thinMaterial, in: Capsule())
      .overlay(Capsule().stroke(palette.separator.opacity(0.7), lineWidth: 0.75))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ui_chat_header")
  }

  @ViewBuilder
  private var chatInfoButton: some View {
    Button {
      showChatInfo = true
    } label: {
      Image(systemName: "info.circle")
    }
    .accessibilityLabel(Text("chat.info"))
    .accessibilityIdentifier("ui_chat_info")
  }

  @ViewBuilder
  private var chatMoreMenu: some View {
    Menu {
      Button("chats.search", systemImage: "magnifyingglass") {
        showMessageSearch = true
      }
      Button("chat.pinned", systemImage: "pin") {
        showPinnedMessages = true
      }
      Button("chat.info", systemImage: "info.circle") {
        showChatInfo = true
      }
      Divider()
      Button("chat.clear_chat", systemImage: "eraser", role: .destructive) {
        showsClearConfirmation = true
      }
      .accessibilityIdentifier("ui_chat_clear")
      Button("chat.delete_chat", systemImage: "trash", role: .destructive) {
        showsDeleteConfirmation = true
      }
      .accessibilityIdentifier("ui_chat_delete")
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("chat.more_actions"))
    .accessibilityIdentifier("ui_chat_more_actions")
  }

  /// A view-once photo is shown inside a secure-field container so the system
  /// screenshot and screen-recording pipelines capture nothing, and the server
  /// is told to consume it only once the viewer is dismissed.
  @ViewBuilder
  private func viewOnceViewer(_ message: ChatMessage) -> some View {
    ScreenshotPreventingView(
      content: ZStack {
        Color.black.ignoresSafeArea()
        if let raw = message.mediaUrl, let url = URL(string: raw) {
          MaxAsyncImage(url: url) { phase in
            if let image = phase.image {
              image
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
            } else {
              ProgressView().tint(.white)
            }
          }
        }
        VStack {
          HStack {
            Spacer()
            Button {
              viewOnceMessage = nil
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
                .padding()
            }
            .accessibilityLabel(Text("common.close"))
          }
          Spacer()
        }
      }
    )
    .ignoresSafeArea()
    .onDisappear {
      Task { await model.chatStore.markViewOnceRead(message.id, in: thread.id) }
    }
  }

  @ViewBuilder
  private var chatMainContent: some View {
    let phase = model.chatStore.messagesByChat[thread.id] ?? .idle
    Group {
      if phase.isLoading {
        ProgressView("chat.loading")
      } else if let error = phase.errorMessage {
        MaxLoadFailureView(message: error) {
          Task { await model.chatStore.loadMessages(for: thread.id) }
        }
      } else if messages.isEmpty {
        MaxEmptyState(
          title: "chat.empty.title",
          subtitle: "chat.empty.subtitle",
          symbol: "bubble.left"
        )
      } else {
        MaxS6MessageList(
          messages: messages,
          unreadCount: thread.unreadCount,
          showsDemoNotice: model.isDemoMode,
          isTyping: model.chatStore.typingUserIDByChat[thread.id] != nil,
          scrollTargetID: scrollTargetID
        ) {
            olderMessagesControl
        } row: { message, clusterPosition, proxy in
          messageRow(message, clusterPosition: clusterPosition, proxy: proxy)
        }
      }
    }
  }

  private func scrollToMessage(_ messageID: String, proxy: ScrollViewProxy) {
    guard messages.contains(where: { $0.id == messageID }) else { return }
    withAnimation(MaxMotion.animation(MaxMotion.standard, enabled: motionEnabled)) {
      proxy.scrollTo(messageID, anchor: .center)
    }
  }

  @ViewBuilder
  private func messageRow(
    _ message: ChatMessage,
    clusterPosition: MaxChatMessageClusterPosition,
    proxy: ScrollViewProxy
  ) -> some View {
    let isCurrentUser = message.senderId == model.sessionStore.user?.id
    ChatMessageRow(
      message: message,
      isCurrentUser: isCurrentUser,
      clusterPosition: clusterPosition,
      isSelected: selectedMessageIDs.contains(message.id),
      isSelectionMode: isSelectingMessages,
      onSelectionToggle: { toggleSelection(message.id) },
      onReply: { replyTarget = message },
      onReplyPreviewTap: { messageID in
        scrollToMessage(messageID, proxy: proxy)
      },
      onOpenViewOnce: { viewOnceMessage = message }
    )
    .id(message.id)
    .onLongPressGesture(minimumDuration: 0.35) {
      guard !message.isDeleted, !message.isHardDeleted, !isSelectingMessages else { return }
      actionMessage = message
    }
  }

  private func focusMessage(_ messageID: String) {
    scrollTargetID = nil
    Task { @MainActor in
      await Task.yield()
      scrollTargetID = messageID
    }
  }

  private func presentThread(_ message: ChatMessage) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      threadParent = message
    }
  }

  private func copyMessage(_ message: ChatMessage) {
    guard let content = message.content else { return }
    UIPasteboard.general.string = content
    copyFeedbackTrigger += 1
    UIAccessibility.post(
      notification: .announcement,
      argument: String(localized: "chat.copy.confirmation")
    )
  }

  private var deleteDialogPresented: Binding<Bool> {
    Binding(
      get: { deletingMessage != nil },
      set: { isPresented in
        if !isPresented { deletingMessage = nil }
      }
    )
  }

  @ViewBuilder
  private func messageActions(for message: ChatMessage, isCurrentUser: Bool) -> some View {
    let capabilities = MaxChatUIAdapter.capabilities(
      for: message,
      isCurrentUser: isCurrentUser
    )
    if capabilities.contains(.reply) {
      Button("chat.reply", systemImage: "arrowshape.turn.up.left") {
        replyTarget = message
      }
    }

    if capabilities.contains(.copy), let content = message.content {
      Button("chat.copy", systemImage: "doc.on.doc") {
          UIPasteboard.general.string = content
          copyFeedbackTrigger += 1
          UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "chat.copy.confirmation")
          )
      }
    }

    if capabilities.contains(.pin) {
      Button(
        message.isPinned == true ? "chat.unpin" : "chat.pin",
        systemImage: message.isPinned == true ? "pin.slash" : "pin"
      ) {
        Task {
          _ = await model.chatStore.setPinned(
            message.isPinned != true,
            messageID: message.id,
            in: thread.id
          )
        }
      }
    }

    if capabilities.contains(.forward) {
      Button("chat.forward", systemImage: "arrowshape.turn.up.right") {
        forwardSelection = ChatForwardSelection(messageIDs: [message.id])
      }
    }

    if capabilities.contains(.edit) {
      Button("chat.edit", systemImage: "pencil") {
        withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
          editingMessage = message
        }
      }
    }

    if capabilities.contains(.delete) {
      Button("action.delete", systemImage: "trash", role: .destructive) {
        deletingMessage = message
      }
    }

    if capabilities.contains(.select) {
      Button("chat.select", systemImage: "checkmark.circle") {
        beginSelection(with: message.id)
      }
    }
  }

  private func toggleSelection(_ messageID: String) {
    if !selectedMessageIDs.insert(messageID).inserted {
      selectedMessageIDs.remove(messageID)
    }
  }

  private func beginSelection(with messageID: String) {
    withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
      isSelectingMessages = true
      selectedMessageIDs.insert(messageID)
    }
  }

  private func endSelection() {
    // The composer/selection bar swap and the per-row checkboxes are declared
    // with transitions but nothing was driving them from a transaction, so both
    // appeared instantly.
    withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
      isSelectingMessages = false
      selectedMessageIDs = []
    }
  }

  @ViewBuilder
  private var olderMessagesControl: some View {
    let state = model.chatStore.messagePageStateByChat[thread.id] ?? .idle
    switch state {
    case .loadingOlder:
      ProgressView("chat.loading_older")
        .controlSize(.small)
    case .loaded(let canLoadMore) where canLoadMore:
      Button("chat.load_older") {
        Task { await model.chatStore.loadOlderMessages(for: thread.id) }
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("ui_chat_load_older")
    case .failed(let message):
      VStack(spacing: MaxSpace.xs) {
        Text(verbatim: message)
          .font(.caption)
          .foregroundStyle(MaxColor.danger)
        Button("common.retry") {
          Task { await model.chatStore.loadOlderMessages(for: thread.id) }
        }
      }
    default:
      EmptyView()
    }
  }
}

private struct ChatComposerView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.maxMotionEnabled) private var motionEnabled

  let thread: ChatThread
  @Binding var replyTarget: ChatMessage?
  @Binding var editingMessage: ChatMessage?

  @FocusState private var isComposerFocused: Bool
  @State private var editingContent = ""
  @State private var attachmentItems: [PhotosPickerItem] = []
  @State private var isUploadingAttachment = false
  @State private var isFileImporterPresented = false
  @State private var isAttachmentTrayPresented = false
  @State private var attachmentError: String?
  @State private var isPollComposerPresented = false
  @State private var isCameraPresented = false
  @State private var voiceRecorder: AVAudioRecorder?
  @State private var voiceRecordingURL: URL?
  @State private var voiceDuration = 0
  @State private var voiceTimerTask: Task<Void, Never>?

  private let maximumAttachmentBytes = 250 * 1_024 * 1_024

  private var draftBinding: Binding<String> {
    Binding(
      get: { model.chatStore.draft(for: thread.id) },
      set: { model.chatStore.setDraft($0, for: thread.id) }
    )
  }

  private var sendState: ChatSendState {
    model.chatStore.sendStateByChat[thread.id] ?? .idle
  }

  private var mentionQuery: String? {
    guard thread.isGroup,
          let token = model.chatStore.draft(for: thread.id).split(separator: " ").last,
          token.hasPrefix("@") else { return nil }
    return String(token.dropFirst())
  }

  private var commandQuery: String? {
    let draft = model.chatStore.draft(for: thread.id)
    guard !draft.contains(" "), draft.hasPrefix("/") else { return nil }
    return String(draft.dropFirst())
  }

  private var canRetryFailedSend: Bool {
    guard case .failed(let failure) = sendState else { return false }
    let draft = model.chatStore.draft(for: thread.id)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return !failure.transaction.mediaFileIDs.isEmpty
      || failure.transaction.replyToID != nil
      || (!draft.isEmpty && draft == failure.transaction.content)
  }

  var body: some View {
    let attachmentUploadInProgress = isUploadingAttachment

    VStack(spacing: MaxSpace.xs) {
      if let editingMessage {
        HStack(alignment: .bottom, spacing: 8) {
          Button {
            withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
              self.editingMessage = nil
            }
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.red)
              .frame(width: 38, height: 38)
              .background { MaxControlMaterial(Circle(), interactive: true) }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_chat_inline_edit_cancel")

          TextField("chat.edit.placeholder", text: $editingContent, axis: .vertical)
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              MaxColor.surfaceStrong,
              in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.accent.opacity(0.4), lineWidth: 1.25)
            }
            .focused($isComposerFocused)
            .accessibilityIdentifier("ui_chat_composer_edit")

          Button {
            saveEdit(editingMessage)
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(palette.accentForeground)
              .frame(width: 38, height: 38)
              .background { MaxControlMaterial(Circle(), tone: .prominent, interactive: true) }
          }
          .buttonStyle(.plain)
          .disabled(editingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("ui_chat_inline_edit_save")
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      } else {
        if let replyTarget {
          MaxS6ReplyBanner(message: replyTarget) {
            self.replyTarget = nil
          }
        }

        if let error = sendState.errorMessage {
          HStack(spacing: MaxSpace.sm) {
            Label {
              Text(verbatim: error)
                .lineLimit(2)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(MaxColor.danger)
            Spacer(minLength: 0)
            if canRetryFailedSend {
              Button("common.retry") {
                Task { await model.chatStore.retrySend(to: thread.id) }
              }
              .font(.caption.weight(.semibold))
              .accessibilityIdentifier("ui_chat_retry_send")
            }
            Button("common.dismiss", systemImage: "xmark") {
              model.chatStore.clearSendError(for: thread.id)
            }
            .labelStyle(.iconOnly)
          }
        }

        if let attachmentError {
          HStack(spacing: MaxSpace.sm) {
            Label {
              Text(verbatim: attachmentError).lineLimit(2)
            } icon: {
              Image(systemName: "paperclip.badge.ellipsis")
            }
            .font(.caption)
            .foregroundStyle(MaxColor.danger)
            Spacer(minLength: 0)
            Button("common.dismiss", systemImage: "xmark") {
              self.attachmentError = nil
            }
            .labelStyle(.iconOnly)
          }
        }

        if isAttachmentTrayPresented {
          MaxS6AttachmentPickerTray(
            selection: $attachmentItems,
            isBusy: attachmentUploadInProgress
          ) {
              isAttachmentTrayPresented = false
              isFileImporterPresented = true
          } takePhoto: {
              isAttachmentTrayPresented = false
              isCameraPresented = true
          } createPoll: {
              isAttachmentTrayPresented = false
              isPollComposerPresented = true
          }
        }

        MaxS6ComposerSuggestions(
          mentionQuery: mentionQuery,
          commandQuery: commandQuery,
          members: model.chatStore.membersByChat[thread.id]?.value ?? [],
          selectMention: insertMention,
          selectCommand: runCommand
        )

        MaxS6ComposerInput(
          text: draftBinding,
          showsAttachmentPicker: $isAttachmentTrayPresented,
          focus: $isComposerFocused,
          isBusy: attachmentUploadInProgress || sendState.isSending,
          isRecording: voiceRecorder?.isRecording == true,
          recordingDuration: voiceDuration,
          toggleRecording: toggleVoiceRecording,
          send: send
        )
      }
    }
    .modifier(MaxS6ComposerSurface())
    .onChange(of: replyTarget?.id) { _, messageID in
      if messageID != nil { isComposerFocused = true }
    }
    .onChange(of: editingMessage?.id) { _, messageID in
      if let messageID,
         let message = model.chatStore.messagesByChat[thread.id]?.value?.first(where: {
           $0.id == messageID
         }) {
        editingContent = message.content ?? ""
        isComposerFocused = true
      }
    }
    .onChange(of: attachmentItems) { _, items in
      guard !items.isEmpty else { return }
      isAttachmentTrayPresented = false
      Task { await uploadAttachments(items) }
    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true,
      onCompletion: handleDocumentSelection
    )
    .sheet(isPresented: $isPollComposerPresented) {
      MaxS6CreatePollSheet(thread: thread)
    }
    .fullScreenCover(isPresented: $isCameraPresented) {
      MaxS6CameraPicker(
        onCapture: { image in
          isCameraPresented = false
          Task { await uploadCapturedImage(image) }
        },
        onCancel: { isCameraPresented = false }
      )
      .ignoresSafeArea()
    }
    .onDisappear {
      voiceTimerTask?.cancel()
      voiceRecorder?.stop()
      voiceRecorder = nil
    }
    .task(id: thread.id) {
      if thread.isGroup, model.chatStore.membersByChat[thread.id]?.value == nil {
        await model.chatStore.loadMembers(for: thread.id)
      }
    }
  }

  private func send() {
    let replyID = replyTarget?.id
    Task {
      let sent = await model.chatStore.sendMessage(to: thread.id, replyToID: replyID)
      if sent != nil {
        replyTarget = nil
      }
    }
  }

  private func saveEdit(_ message: ChatMessage) {
    let content = editingContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    Task {
      if await model.chatStore.editMessage(message.id, in: thread.id, content: content) != nil {
        withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
          editingMessage = nil
        }
      }
    }
  }

  private func uploadAttachments(_ items: [PhotosPickerItem]) async {
    isUploadingAttachment = true
    defer { isUploadingAttachment = false; attachmentItems = [] }
    attachmentError = nil

    var files: [MobileUploadFile] = []
    for (index, item) in items.prefix(6).enumerated() {
      guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
        continue
      }
      guard data.count <= maximumAttachmentBytes else {
        attachmentError = String(localized: "upload.error.too_large")
        continue
      }
      let type = item.supportedContentTypes.first
      let ext = type?.preferredFilenameExtension ?? "bin"
      let mime = type?.preferredMIMEType ?? "application/octet-stream"
      files.append(
        MobileUploadFile(
          data: data,
          fileName: "Max-\(index + 1).\(ext)",
          mimeType: mime
        )
      )
    }
    guard !files.isEmpty,
          let fileIDs = await model.transferStore.upload(files: files) else {
      attachmentError = String(localized: "error.upload.failed")
      return
    }
    await sendAttachments(fileIDs)
  }

  @MainActor
  private func uploadCapturedImage(_ image: UIImage) async {
    guard let data = image.jpegData(compressionQuality: 0.9), !data.isEmpty else {
      attachmentError = String(localized: "error.upload.failed")
      return
    }
    isUploadingAttachment = true
    defer { isUploadingAttachment = false }
    let file = MobileUploadFile(
      data: data,
      fileName: "Max Camera.jpg",
      mimeType: "image/jpeg"
    )
    guard let fileIDs = await model.transferStore.upload(files: [file]) else {
      attachmentError = String(localized: "error.upload.failed")
      return
    }
    await sendAttachments(fileIDs)
  }

  private func handleDocumentSelection(_ result: Result<[URL], Error>) {
    Task { @MainActor in
      isUploadingAttachment = true
      attachmentError = nil
      defer { isUploadingAttachment = false }

      do {
        let urls = try result.get()
        var files: [MobileUploadFile] = []
        for url in urls.prefix(6) {
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }

          let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard values.isRegularFile == true, let byteCount = values.fileSize, byteCount > 0 else {
            throw ChatAttachmentPreparationError.unreadable
          }
          guard byteCount <= maximumAttachmentBytes else {
            throw ChatAttachmentPreparationError.tooLarge
          }
          let localURL = try ChatAttachmentFiles.copy(url)
          let type = UTType(filenameExtension: url.pathExtension)
          files.append(
            MobileUploadFile(
              fileURL: localURL,
              byteCount: byteCount,
              fileName: url.lastPathComponent,
              mimeType: type?.preferredMIMEType ?? "application/octet-stream"
            )
          )
        }

        guard !files.isEmpty,
              let fileIDs = await model.transferStore.upload(files: files) else {
          throw ChatAttachmentPreparationError.uploadFailed
        }
        await sendAttachments(fileIDs)
      } catch ChatAttachmentPreparationError.tooLarge {
        attachmentError = String(localized: "upload.error.too_large")
      } catch ChatAttachmentPreparationError.unreadable {
        attachmentError = String(localized: "upload.error.unreadable")
      } catch {
        attachmentError = String(localized: "error.upload.failed")
      }
    }
  }

  private func sendAttachments(_ fileIDs: [String]) async {
    let draft = model.chatStore.draft(for: thread.id)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let sent = await model.chatStore.sendMessage(
      to: thread.id,
      content: draft,
      mediaFileIDs: fileIDs,
      replyToID: replyTarget?.id
    )
    if sent != nil { replyTarget = nil }
  }

  private func toggleVoiceRecording() {
    if voiceRecorder?.isRecording == true {
      finishVoiceRecording()
    } else {
      Task { await startVoiceRecording() }
    }
  }

  private func insertMention(_ member: ChatGroupMember) {
    var parts = model.chatStore.draft(for: thread.id).split(
      separator: " ",
      omittingEmptySubsequences: false
    )
    if !parts.isEmpty { parts.removeLast() }
    let prefix = parts.joined(separator: " ")
    model.chatStore.setDraft(
      (prefix.isEmpty ? "" : prefix + " ") + "@\(member.displayName) ",
      for: thread.id
    )
    isComposerFocused = true
  }

  private func runCommand(_ command: MaxS6ComposerCommand) {
    switch command {
    case .poll:
      model.chatStore.setDraft("", for: thread.id)
      isPollComposerPresented = true
    case .shrug:
      model.chatStore.setDraft("¯\\_(ツ)_/¯ ", for: thread.id)
      isComposerFocused = true
    case .tableflip:
      model.chatStore.setDraft("(╯°□°)╯︵ ┻━┻ ", for: thread.id)
      isComposerFocused = true
    }
  }

  @MainActor
  private func startVoiceRecording() async {
    let granted = await AVAudioApplication.requestRecordPermission()
    guard granted else {
      attachmentError = String(localized: "chat.voice.permission_denied")
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true)
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MaxChatVoice", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
      let recorder = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
      )
      recorder.prepareToRecord()
      guard recorder.record() else { throw ChatAttachmentPreparationError.unreadable }
      voiceRecordingURL = url
      voiceRecorder = recorder
      voiceDuration = 0
      voiceTimerTask?.cancel()
      voiceTimerTask = Task { @MainActor in
        while !Task.isCancelled, voiceRecorder?.isRecording == true {
          try? await Task.sleep(for: .seconds(1))
          guard !Task.isCancelled else { return }
          voiceDuration += 1
        }
      }
    } catch {
      attachmentError = String(localized: "chat.voice.failed")
    }
  }

  private func finishVoiceRecording() {
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceTimerTask?.cancel()
    voiceTimerTask = nil
    guard let url = voiceRecordingURL else { return }
    voiceRecordingURL = nil
    Task { await uploadVoiceRecording(url) }
  }

  @MainActor
  private func uploadVoiceRecording(_ url: URL) async {
    isUploadingAttachment = true
    defer {
      isUploadingAttachment = false
      try? FileManager.default.removeItem(at: url)
    }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard let byteCount = values.fileSize, byteCount > 0 else {
        throw ChatAttachmentPreparationError.unreadable
      }
      let file = MobileUploadFile(
        fileURL: url,
        byteCount: byteCount,
        fileName: "Max Voice.m4a",
        mimeType: "audio/mp4"
      )
      guard let fileIDs = await model.transferStore.upload(files: [file]) else {
        throw ChatAttachmentPreparationError.uploadFailed
      }
      await sendAttachments(fileIDs)
    } catch {
      attachmentError = String(localized: "chat.voice.failed")
    }
  }
}

private enum ChatAttachmentPreparationError: Error {
  case unreadable
  case tooLarge
  case uploadFailed
}

private enum ChatAttachmentFiles {
  static func copy(_ source: URL) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaxChatAttachments", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: directory.path
    )

    let fileName = source.lastPathComponent.isEmpty ? "attachment" : source.lastPathComponent
    let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    try FileManager.default.copyItem(at: source, to: destination)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: destination.path
    )
    return destination
  }
}

private struct ChatForwardSelection: Identifiable {
  let id = UUID()
  let messageIDs: [String]
}

private struct ChatForwardSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MaxAppModel.self) private var model

  let sourceThreadID: String
  let messageIDs: [String]

  @State private var isForwarding = false

  var body: some View {
    NavigationStack {
      Group {
        if let threads = model.chatStore.threads.value {
          List(threads) { thread in
            Button {
              Task { await forward(to: thread.id) }
            } label: {
              MaxThreadRow(thread: thread)
            }
            .buttonStyle(.plain)
            .disabled(isForwarding)
          }
          .listStyle(.plain)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("chat.forward")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func forward(to targetThreadID: String) async {
    guard !isForwarding else { return }
    isForwarding = true
    var didForwardEveryMessage = true
    for messageID in messageIDs {
      let didForward = await model.chatStore.forwardMessage(
        messageID,
        from: sourceThreadID,
        to: targetThreadID
      )
      didForwardEveryMessage = didForwardEveryMessage && didForward
    }
    isForwarding = false
    if didForwardEveryMessage { dismiss() }
  }
}

private struct ChatMessageRow: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxChatBubbleWidth) private var maxBubbleWidth

  let message: ChatMessage
  let isCurrentUser: Bool
  let clusterPosition: MaxChatMessageClusterPosition
  let isSelected: Bool
  let isSelectionMode: Bool
  let onSelectionToggle: () -> Void
  let onReply: () -> Void
  let onReplyPreviewTap: (String) -> Void
  let onOpenViewOnce: () -> Void

  @State private var viewerSelection: ChatMediaViewerSelection?
  @State private var showsReadReceipts = false

  private var isDeleted: Bool {
    message.isDeleted || message.isHardDeleted
  }

  private var isViewOnce: Bool {
    message.isViewOnce == true
  }

  private var isPlainTextMessage: Bool {
    MaxChatUIAdapter.isPlainText(message)
      && !isViewOnce
      && resolvedFallbackMedia == nil
      && messageLinkURL == nil
  }

  private var messageLinkURL: URL? {
    guard let content = message.content else { return nil }
    return content.split(whereSeparator: { $0.isWhitespace }).compactMap { token -> URL? in
      let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>,.!?"))
      guard cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") else { return nil }
      return URL(string: cleaned)
    }.first
  }

  private var bubbleTextColor: Color {
    isCurrentUser ? palette.accentForeground : palette.primaryText
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: MaxSpace.xs) {
      if isSelectionMode {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(
            isSelected
              ? AnyShapeStyle(palette.accent)
              : AnyShapeStyle(MaxColor.textSecondary)
          )
          .accessibilityHidden(true)
      }

      if !isCurrentUser {
        Group {
          if clusterPosition.endsCluster {
            MaxAvatar(
              name: message.sender?.displayName ?? message.senderId,
              imageURL: message.sender?.avatarUrl,
              size: 30
            )
          } else {
            Color.clear.frame(width: 30, height: 30)
          }
        }
        .accessibilityHidden(true)
      }

      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: MaxSpace.xxs) {
        if !isCurrentUser,
           clusterPosition.startsCluster,
           let sender = message.sender?.displayName,
           !sender.isEmpty {
          Text(verbatim: sender)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MaxColor.textSecondary)
            .padding(.horizontal, MaxSpace.xs)
        }

        VStack(alignment: .leading, spacing: MaxSpace.xs) {
          if isPlainTextMessage {
            plainTextMessageView
          } else {
            complexMessageView
          }
        }
        .padding(.horizontal, 11)
        .padding(.top, 7)
        .padding(.bottom, 5)
        // A bound, not a size. The bubble hugs its content and only wraps once it
        // reaches this width; the previous containerRelativeFrame handed every
        // message a definite 72-78% of the row, so a one-word reply rendered as a
        // full-width slab.
        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(
          MaxS6MessageBubbleModifier(
            isCurrentUser: isCurrentUser,
            clusterPosition: clusterPosition
          )
        )

        if let reactions = message.reactions, !reactions.isEmpty {
          MaxS6ReactionBar(reactions: reactions) { reaction in
            Task {
              _ = await model.chatStore.setReaction(
                reaction.reactedByMe ? nil : reaction.key,
                messageID: message.id,
                in: message.dmId
              )
            }
          }
          .padding(.horizontal, 4)
          .offset(y: -2)
        }

        if isCurrentUser,
           let receipts = message.readReceipts,
           !receipts.isEmpty {
          MaxS6ReadReceiptSummary(receipts: receipts) {
            showsReadReceipts = true
          }
          .padding(.horizontal, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
    .padding(.top, clusterPosition.startsCluster ? MaxSpace.xs : 0)
    .contentShape(Rectangle())
    .onTapGesture {
      if isSelectionMode { onSelectionToggle() }
    }
    .maxS6SwipeToReply(
      enabled: !isSelectionMode && !isDeleted,
      reply: onReply
    )
    .fullScreenCover(item: $viewerSelection) { selection in
      MaxDMPlayerView(items: selection.items, selectedIndex: selection.selectedIndex)
    }
    .sheet(isPresented: $showsReadReceipts) {
      MaxS6ReadReceiptsSheet(receipts: message.readReceipts ?? [])
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ui_chat_message_\(message.id)")
  }

  @ViewBuilder
  private var plainTextMessageView: some View {
    if let content = message.content {
      let baseText = Text(verbatim: content)
        .font(.subheadline)
        .foregroundStyle(bubbleTextColor)

      let spacingText = Text(verbatim: "   ")
      let metaText = getMetaText()

      (baseText + spacingText + metaText.foregroundStyle(bubbleTextColor.opacity(0.64)))
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }
  }

  private func getMetaText() -> Text {
    var metaText = Text(verbatim: "")
    if message.isEdited {
      metaText = metaText
        + Text("chat.message.edited").font(.caption2.italic())
        + Text(verbatim: " ")
    }
    if message.isPinned == true {
      metaText = metaText
        + Text(Image(systemName: "pin.fill")).font(.system(size: 8))
        + Text(verbatim: " ")
    }
    if let timestamp = MaxChatDate.formatted(message.createdAt) {
      metaText = metaText + Text(verbatim: timestamp).font(.caption2)
    }
    if isCurrentUser {
      let checkIcon = hasBeenRead ? "checkmark.circle.fill" : "checkmark"
      metaText = metaText
        + Text(verbatim: " ")
        + Text(Image(systemName: checkIcon)).font(.system(size: 9))
    }
    return metaText
  }

  /// A view-once photo never renders inline: the bubble only offers to open it,
  /// and switches to a spent state once the server records that it was consumed.
  @ViewBuilder
  private var viewOnceContent: some View {
    if message.isViewOnceConsumed {
      Label("chats.opened_photo", systemImage: "eye.slash.fill")
        .font(.subheadline)
        .foregroundStyle(bubbleTextColor.opacity(0.72))
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, MaxSpace.xs)
        .background(
          palette.selectedControl,
          in: RoundedRectangle(cornerRadius: MaxRadius.small)
        )
    } else {
      Button(action: onOpenViewOnce) {
        Label("chats.view_photo_once", systemImage: "viewfinder.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(bubbleTextColor)
          .padding(.horizontal, MaxSpace.sm)
          .padding(.vertical, MaxSpace.xs)
          .background(
            palette.selectedControl,
            in: RoundedRectangle(cornerRadius: MaxRadius.small)
          )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_chat_view_once_\(message.id)")
    }
  }

  @ViewBuilder
  private var complexMessageView: some View {
    if isDeleted {
      Label("chat.message.deleted", systemImage: "trash")
        .font(.subheadline.italic())
        .foregroundStyle(bubbleTextColor.opacity(0.78))
    } else if isViewOnce {
      viewOnceContent
      messageFooter
    } else {
      if let poll = message.poll {
        MaxS6PollAttachmentView(threadID: message.dmId, poll: poll)
      }

      if let forwarded = message.forwardedFrom {
        Label {
          Text(verbatim: forwarded.senderName ?? String(localized: "chat.forwarded"))
            .lineLimit(1)
        } icon: {
          Image(systemName: "arrowshape.turn.up.right.fill")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(bubbleTextColor.opacity(0.76))
      }

      if let preview = message.replyPreview {
        Button {
          onReplyPreviewTap(preview.id)
        } label: {
          ChatReplyPreviewView(preview: preview, isCurrentUser: isCurrentUser)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_chat_reply_link_\(preview.id)")
      }

      if let content = message.content, !content.isEmpty {
        Text(verbatim: content)
          .font(.subheadline)
          .foregroundStyle(bubbleTextColor)
          .multilineTextAlignment(.leading)
          .textSelection(.enabled)
      }


      if let messageLinkURL {
        MaxS6LinkPreviewView(url: messageLinkURL)
      }

      // The server's `attachments[]` payload carries a signed URL, a poster and a
      // duration per item, so it — not the single flat mediaUrl — is what makes a
      // multi-attachment message and a video thumbnail render at all.
      let availableItems = message.attachmentMediaItems
      if !availableItems.isEmpty {
        let visualItems = availableItems.filter {
          let kind = $0.kind.lowercased()
          return kind == "image" || kind == "video"
        }
        let fileItems = availableItems.filter {
          let kind = $0.kind.lowercased()
          return kind != "image" && kind != "video"
        }
        if !visualItems.isEmpty {
          ChatMediaGallery(items: visualItems) { index in
            viewerSelection = ChatMediaViewerSelection(
              items: visualItems,
              selectedIndex: index
            )
          }
        }
        ForEach(fileItems) { item in
          MaxS6FileAttachmentView(item: item)
        }
      }

      if let references = message.mediaReferences, !references.isEmpty {
        ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
          if case .locked = reference.file {
            mediaReference(reference)
          }
        }
      }

      if availableItems.isEmpty {
        if let item = resolvedFallbackMedia {
          ChatMediaGallery(items: [item]) { _ in
            viewerSelection = ChatMediaViewerSelection(items: [item], selectedIndex: 0)
          }
        } else if let mediaName = message.mediaName, !mediaName.isEmpty {
          Label {
            Text(verbatim: mediaName)
              .lineLimit(2)
          } icon: {
            Image(
              systemName: message.resolvedMediaKind == "video" ? "video.fill" : "paperclip"
            )
          }
          .font(.caption.weight(.semibold))
        }
      }

      messageFooter
    }
  }

  @ViewBuilder
  private var messageFooter: some View {
    HStack(spacing: MaxSpace.xxs) {
      Spacer()
      if message.isEdited {
        Text("chat.message.edited")
          .font(.caption2.italic())
      }
      if message.isPinned == true {
        Image(systemName: "pin.fill")
          .font(.system(size: 8))
      }
      if let timestamp = MaxChatDate.formatted(message.createdAt) {
        Text(verbatim: timestamp)
      }
      if isCurrentUser {
        let checkIcon = hasBeenRead ? "checkmark.circle.fill" : "checkmark"
        Image(systemName: checkIcon)
          .font(.system(size: 9))
      }
    }
    .font(.caption2)
    .foregroundStyle(bubbleTextColor.opacity(0.64))
  }

  /// Read state is derived from the receipts the server now sends; `readAt` was
  /// never populated on the wire, so every sent message showed a single tick.
  private var hasBeenRead: Bool {
    message.readAt != nil || !(message.readReceipts ?? []).isEmpty
  }

  private var resolvedFallbackMedia: MaxMediaItem? {
    let candidates = model.libraryStore.catalogItems
    if let fileID = message.dmMediaId,
       let exact = candidates.first(where: { $0.id == fileID }) {
      return exact
    }
    if let rawURL = message.mediaUrl, !rawURL.isEmpty {
      let url: URL
      if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
        guard let parsed = URL(string: rawURL) else { return nil }
        url = parsed
      } else {
        let base = MaxConfiguration.fromBundle().baseURL
        guard let parsed = URL(string: rawURL, relativeTo: base) else { return nil }
        url = parsed.absoluteURL
      }
      // mediaType is a MIME type on the wire ("video/mp4"), so a bare equality
      // check classified every video as an image and asked the thumbnail loader
      // to decode video bytes.
      let kind = message.resolvedMediaKind
      return MaxMediaItem(
        id: message.dmMediaId ?? "message-media-\(message.id)",
        title: message.mediaName ?? String(localized: "chat.message.media"),
        kind: kind,
        sizeBytes: 0,
        duration: nil,
        mediaUrl: url,
        thumbnailUrl: kind == "image" ? url : nil,
        videoThumbnailUrl: nil,
        uploader: .init(
          id: message.sender?.id,
          name: message.sender?.displayName,
          avatarUrl: message.sender?.avatarUrl
        ),
        workspace: nil,
        uploadedAt: message.createdAt,
        rating: nil,
        isFavorite: false,
        isSaved: false,
        lastPosition: 0,
        lastViewedAt: nil,
        isPrivate: false,
        downloadable: true
      )
    }
    guard let mediaName = message.mediaName else { return nil }
    let baseName = (mediaName as NSString).deletingPathExtension
    return candidates.first {
      $0.title.localizedCaseInsensitiveCompare(baseName) == .orderedSame
    }
  }

  @ViewBuilder
  private func mediaReference(_ reference: MediaReference) -> some View {
    switch reference.file {
    case .media(let item):
      ChatMediaAttachment(item: item, isCurrentUser: isCurrentUser)
    case .locked(let item):
      VStack(alignment: .leading, spacing: MaxSpace.xs) {
        Label {
          Text(verbatim: item.title)
            .lineLimit(2)
        } icon: {
          Image(systemName: "lock.fill")
        }
        .font(.caption.weight(.semibold))
        if reference.requestAccessSupported {
          Button("access.request") {
            Task {
              await model.chatStore.requestAccess(for: item.id, messageID: message.id)
            }
          }
          .font(.caption.weight(.semibold))
          .buttonStyle(.bordered)
          .tint(isCurrentUser ? palette.accentForeground : palette.accent)
          .accessibilityIdentifier("ui_chat_request_access_\(item.id)")
        }
      }
      .padding(MaxSpace.sm)
      .background(
        isCurrentUser ? palette.accentForeground.opacity(0.12) : palette.selectedControl,
        in: RoundedRectangle(cornerRadius: MaxRadius.small)
      )
    }
  }
}

private struct ChatReplyPreviewView: View {
  @Environment(\.maxThemePalette) private var palette

  let preview: ChatReplyPreview
  let isCurrentUser: Bool

  var body: some View {
    HStack(spacing: MaxSpace.xs) {
      Capsule()
        .fill(isCurrentUser ? palette.accentForeground.opacity(0.76) : palette.accent)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        if let sender = preview.sender?.displayName, !sender.isEmpty {
          Text(verbatim: sender)
            .font(.caption2.weight(.semibold))
        }
        if preview.isDeleted {
          Text("chat.message.deleted")
        } else if let content = preview.content, !content.isEmpty {
          Text(verbatim: content)
        } else {
          Label("chat.message.media", systemImage: "paperclip")
        }
      }
      .font(.caption)
      .lineLimit(2)
      Spacer(minLength: 0)
      // The server sends a poster for the quoted message's first attachment, so
      // a reply to a photo reads as a reply to that photo rather than as
      // "Attachment".
      if !preview.isDeleted, let thumbnailUrl = preview.thumbnailUrl {
        MaxAsyncImage(url: thumbnailUrl) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            palette.selectedControl
          }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))
        .accessibilityHidden(true)
      }
    }
    .foregroundStyle(
      (isCurrentUser ? palette.accentForeground : palette.primaryText).opacity(0.88)
    )
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
    .background(
      isCurrentUser ? palette.accentForeground.opacity(0.12) : palette.selectedControl,
      in: RoundedRectangle(cornerRadius: MaxRadius.small)
    )
  }
}

private struct ChatMediaViewerSelection: Identifiable {
  let id = UUID()
  let items: [MaxMediaItem]
  let selectedIndex: Int
}

private struct ChatSingleMediaView: View {
  let item: MaxMediaItem
  let onOpen: () -> Void

  private let maxWidth: CGFloat = min(UIScreen.main.bounds.width * 0.72, 280)

  var body: some View {
    Button {
      onOpen()
    } label: {
      ZStack {
        if let url = item.posterURL {
          MaxAsyncImage(url: url) { phase in
            if let image = phase.image {
              image
                .resizable()
                .scaledToFill()
            } else if phase.error != nil {
              placeholderContent
            } else {
              placeholderContent
                .overlay { ProgressView().tint(.white) }
            }
          }
        } else {
          placeholderContent
        }

        if item.kind.lowercased() == "video" {
          Image(systemName: "play.fill")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.5), in: Circle())
        }
      }
      // Constrain to a sensible bubble size; scaledToFill + clipped gives the
      // Telegram feel where the image fills the frame without letterboxing.
      .frame(maxWidth: maxWidth)
      .frame(height: item.kind.lowercased() == "video" ? maxWidth * 0.65 : maxWidth * 0.75)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var placeholderContent: some View {
    Color(red: 0.10, green: 0.11, blue: 0.14)
      .overlay {
        Image(systemName: item.kind.lowercased() == "video" ? "video.fill" : "photo.fill")
          .font(.title2)
          .foregroundStyle(.white.opacity(0.45))
      }
  }
}

private struct ChatMediaGallery: View {
  let items: [MaxMediaItem]
  let onOpen: (Int) -> Void

  private var columns: [GridItem] {
    let count = items.count == 1 ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 3), count: count)
  }

  private var cellHeight: CGFloat {
    items.count == 1 ? 176 : 124
  }

  var body: some View {
    Group {
      if items.count == 1, let item = items.first {
        ChatSingleMediaView(item: item, onOpen: { onOpen(0) })
      } else {
        LazyVGrid(columns: columns, spacing: 3) {
          ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, item in
            Button { onOpen(index) } label: {
              ChatGalleryThumbnail(item: item)
                .frame(height: cellHeight)
                .overlay(alignment: .topTrailing) {
                  if index == 5, items.count > 6 {
                    Text("+\(items.count - 6)")
                      .font(.headline.monospacedDigit())
                      .foregroundStyle(.white)
                      .padding(8)
                      .background(.black.opacity(0.64), in: Capsule())
                      .padding(6)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: item.title))
          }
        }
        .frame(width: 270)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
  }
}

private struct ChatGalleryThumbnail: View {
  let item: MaxMediaItem

  var body: some View {
    ZStack {
      // Keep chat attachments on the canonical poster pipeline as well. A
      // video must not become a blank square merely because a server thumbnail
      // is absent or its signed URL has expired.
      MaxMediaPoster(item: item, compact: true, showsMetadata: false)

      if item.kind.lowercased() == "video" {
        Image(systemName: "play.fill")
          .font(.title3.weight(.bold))
          .foregroundStyle(.white)
          .padding(12)
          .background(.black.opacity(0.46), in: Circle())
      }
    }
    .clipped()
    .contentShape(Rectangle())
  }

}

private extension RandomAccessCollection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

private struct ChatMediaAttachment: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(MaxAppModel.self) private var model

  let item: MaxMediaItem
  let isCurrentUser: Bool

  private var controlTint: Color? {
    isCurrentUser ? palette.accentForeground : nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      Button {
        model.openPlayer(for: item)
      } label: {
        MaxMediaPoster(item: item, compact: true, showsMetadata: true)
          .frame(maxWidth: 238)
          .frame(height: 116)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ui_chat_media_open_\(item.id)")

      ViewThatFits(in: .horizontal) {
        HStack(spacing: MaxSpace.xs) { mediaActions }
        VStack(alignment: .leading, spacing: MaxSpace.xs) { mediaActions }
      }
    }
    .padding(MaxSpace.xs)
    .background(
      isCurrentUser ? palette.accentForeground.opacity(0.12) : palette.selectedControl,
      in: RoundedRectangle(cornerRadius: MaxRadius.small)
    )
  }

  @ViewBuilder
  private var mediaActions: some View {
    Button("action.play", systemImage: "play.fill") {
      model.openPlayer(for: item)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .tint(controlTint)

    MaxMediaSaveControl(item: item, tint: controlTint)
    MaxMediaTransferControl(item: item, tint: controlTint)
  }
}

private struct ChatMessageEditSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let threadID: String
  let message: ChatMessage

  @State private var content: String
  @State private var isSaving = false
  @State private var errorMessage: String?
  @FocusState private var isEditorFocused: Bool

  init(threadID: String, message: ChatMessage) {
    self.threadID = threadID
    self.message = message
    _content = State(initialValue: message.content ?? "")
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        Text("chat.edit.help")
          .font(.subheadline)
          .foregroundStyle(MaxColor.textSecondary)

        TextEditor(text: $content)
          .multilineTextAlignment(.leading)
          .focused($isEditorFocused)
          .padding(MaxSpace.sm)
          .frame(minHeight: 150)
          .background(
            MaxColor.surface,
            in: RoundedRectangle(cornerRadius: MaxRadius.medium)
          )
          .accessibilityIdentifier("ui_chat_edit_editor")

        if let errorMessage {
          Label {
            Text(verbatim: errorMessage)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
          }
          .font(.caption)
          .foregroundStyle(MaxColor.danger)
        }

        Spacer(minLength: 0)
      }
      .padding(MaxSpace.md)
      .navigationTitle("chat.edit.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("common.save") { save() }
            .disabled(isSaving || trimmedContent.isEmpty || trimmedContent == message.content)
            .accessibilityIdentifier("ui_chat_edit_save")
        }
      }
      .onAppear { isEditorFocused = true }
      .interactiveDismissDisabled(isSaving)
      .maxScreenBackground()
      .accessibilityIdentifier("ui_chat_edit_sheet")
    }
    .presentationDetents([.medium, .large])
  }

  private var trimmedContent: String {
    content.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() {
    isSaving = true
    errorMessage = nil
    Task {
      let result = await model.chatStore.editMessage(
        message.id,
        in: threadID,
        content: trimmedContent
      )
      isSaving = false
      if result != nil {
        dismiss()
      } else {
        errorMessage = model.chatStore.sendStateByChat[threadID]?.errorMessage
          ?? String(localized: "chat.edit.failed")
      }
    }
  }
}

struct AccessRequestsSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let response = model.chatStore.accessRequests.value {
          if response.incoming.isEmpty && response.outgoing.isEmpty {
            MaxEmptyState(
              title: "access.empty.title",
              subtitle: "access.empty.subtitle",
              symbol: "lock.open"
            )
          } else {
            List {
              if !response.incoming.isEmpty {
                Section("access.incoming") {
                  ForEach(response.incoming) { request in
                    AccessRequestRow(request: request, isIncoming: true)
                  }
                }
              }
              if !response.outgoing.isEmpty {
                Section("access.outgoing") {
                  ForEach(response.outgoing) { request in
                    AccessRequestRow(request: request, isIncoming: false)
                  }
                }
              }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
          }
        } else if model.chatStore.accessRequests.isLoading {
          ProgressView("access.loading")
        } else if let error = model.chatStore.accessRequests.errorMessage {
          MaxLoadFailureView(message: error) {
            Task { await model.chatStore.loadAccessRequests() }
          }
        }
      }
      .navigationTitle("access.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("common.refresh", systemImage: "arrow.clockwise") {
            Task { await model.chatStore.loadAccessRequests() }
          }
        }
      }
      .task {
        guard !model.isUITestMode,
              model.chatStore.accessRequests.value == nil else { return }
        await model.chatStore.loadAccessRequests()
      }
      .maxScreenBackground()
      .accessibilityIdentifier("ui_access_requests_sheet")
    }
    .presentationDetents([.medium, .large])
  }
}

private struct AccessRequestRow: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let request: AccessRequest
  let isIncoming: Bool

  @State private var isDeciding = false

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      HStack(alignment: .firstTextBaseline, spacing: MaxSpace.sm) {
        Text(verbatim: request.fileName ?? String(localized: "access.file"))
          .font(.body.weight(.semibold))
          .lineLimit(2)
        Spacer(minLength: 0)
        Text(verbatim: localizedStatus)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(statusColor)
          .padding(.horizontal, MaxSpace.xs)
          .padding(.vertical, MaxSpace.xxs)
          .background(statusColor.opacity(0.12), in: Capsule())
      }

      if let requester = request.requesterName, !requester.isEmpty {
        Label {
          Text(verbatim: requester)
        } icon: {
          Image(systemName: "person.crop.circle")
        }
        .font(.caption)
        .foregroundStyle(MaxColor.textSecondary)
      }

      if let note = request.note, !note.isEmpty {
        Text(verbatim: note)
          .font(.subheadline)
          .lineLimit(3)
      }

      if isIncoming && request.status.lowercased() == "pending" {
        ViewThatFits(in: .horizontal) {
          HStack { decisionButtons }
          VStack(alignment: .leading) { decisionButtons }
        }
      }
    }
    .padding(.vertical, MaxSpace.xs)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ui_access_request_\(request.id)")
  }

  @ViewBuilder
  private var decisionButtons: some View {
    Button("access.approve") {
      decide(approve: true)
    }
    .buttonStyle(.borderedProminent)
    .disabled(isDeciding)
    .accessibilityIdentifier("ui_access_approve_\(request.id)")

    Button("access.deny", role: .destructive) {
      decide(approve: false)
    }
    .buttonStyle(.bordered)
    .disabled(isDeciding)
    .accessibilityIdentifier("ui_access_deny_\(request.id)")
  }

  private func decide(approve: Bool) {
    guard !isDeciding else { return }
    isDeciding = true
    Task {
      await model.chatStore.decideAccessRequest(request.id, approve: approve)
      isDeciding = false
    }
  }

  private var localizedStatus: String {
    switch request.status.lowercased() {
    case "approved": String(localized: "access.status.approved")
    case "denied": String(localized: "access.status.denied")
    case "expired": String(localized: "access.status.expired")
    case "pending": String(localized: "access.status.pending")
    case "rejected": String(localized: "access.status.rejected")
    default: request.status
    }
  }

  private var statusColor: Color {
    switch request.status.lowercased() {
    case "approved": palette.success
    case "denied", "rejected", "expired": palette.destructive
    default: palette.warning
    }
  }
}

private enum MaxChatDate {
  static func formatted(_ value: String?) -> String? {
    MaxChatUIAdapter.messageTime(for: value)
  }
}

private struct ChatInfoSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.maxMotionEnabled) private var motionEnabled
  let thread: ChatThread

  @State private var partnerNickname = ""
  @State private var showingEditNickname = false
  @State private var showingAvatarDetail = false
  @State private var groupName = ""
  @State private var showingRenameGroup = false
  @State private var showingAddMember = false

  private var partnerId: String? {
    thread.partnerId
  }

  private var currentUserID: String? {
    model.sessionStore.user?.id
  }

  private var canManageGroup: Bool {
    guard thread.isGroup else { return false }
    let members = model.chatStore.membersByChat[thread.id]?.value ?? []
    if let role = members.first(where: { $0.userId == currentUserID })?.role.lowercased() {
      return role == "owner" || role == "admin"
    }
    // Members have not loaded yet; fall back to the conversation's own owner.
    guard let ownerId = thread.ownerId, let currentUserID else { return false }
    return ownerId == currentUserID
  }

  private var isBlocked: Bool {
    guard let partnerId else { return false }
    return model.preferencesStore.blockedUserIDs.contains(partnerId)
  }

  private var nickname: String {
    if let partnerId = thread.partnerId {
      return model.preferencesStore.nicknames[partnerId] ?? thread.title
    }
    return thread.title
  }

  private var preference: ChatThreadPreference? {
    model.chatStore.preferencesByChat[thread.id]?.value
  }

  private var isMuted: Bool {
    preference?.isMuted ?? (thread.isMuted == true)
  }

  private var isArchived: Bool {
    preference?.isArchived ?? (thread.isArchived == true)
  }

  private var sharedMediaItems: [MaxMediaItem] {
    let allMessages = model.chatStore.messagesByChat[thread.id]?.value ?? []
    // View-once media is deliberately excluded: it must not become browsable
    // from the conversation info sheet.
    return allMessages
      .filter { $0.isViewOnce != true }
      .flatMap(\.attachmentMediaItems)
  }

  var body: some View {
    NavigationStack {
      List {
        // Profile Summary
        Section {
          VStack(spacing: MaxSpace.md) {
            Button {
              showingAvatarDetail = true
            } label: {
              MaxAvatar(name: nickname, imageURL: thread.avatarUrl)
                .frame(width: 86, height: 86)
                .shadow(radius: 4)
            }
            .buttonStyle(.plain)

            VStack(spacing: MaxSpace.xxs) {
              Text(verbatim: nickname)
                .font(.title2.weight(.bold))
                .foregroundStyle(MaxColor.textPrimary)

              if let partnerId, model.preferencesStore.nicknames[partnerId] != nil {
                Text(verbatim: thread.title)
                  .font(.subheadline)
                  .foregroundStyle(MaxColor.textSecondary)
              } else {
                Text(thread.isGroup ? "chat.type.group" : "chat.type.direct")
                  .font(.caption)
                  .foregroundStyle(MaxColor.textSecondary)
              }
            }

            HStack(spacing: MaxSpace.md) {
              Button {
                partnerNickname = model.preferencesStore.nicknames[partnerId ?? ""] ?? ""
                showingEditNickname = true
              } label: {
                Label("chat.action.nickname", systemImage: "pencil")
                  .font(.subheadline.weight(.semibold))
                  .padding(.vertical, 8)
                  .frame(maxWidth: .infinity)
                  .background(MaxColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 10))
              }
              .buttonStyle(.plain)

              if let partnerId {
                Button {
                  withAnimation(MaxMotion.animation(MaxMotion.quick, enabled: motionEnabled)) {
                    if isBlocked {
                      model.preferencesStore.blockedUserIDs.remove(partnerId)
                    } else {
                      model.preferencesStore.blockedUserIDs.insert(partnerId)
                    }
                  }
                } label: {
                  Label(
                    isBlocked ? "chat.action.unblock" : "chat.action.block",
                    systemImage: isBlocked ? "person.badge.shield.checkmark.fill" : "nosign"
                  )
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(isBlocked ? .green : .red)
                  .padding(.vertical, 8)
                  .frame(maxWidth: .infinity)
                  .background(MaxColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.top, MaxSpace.xs)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, MaxSpace.sm)
          .listRowBackground(Color.clear)
        }

        Section("chat.settings") {
          Toggle(
            "chat.mute",
            systemImage: "speaker.slash.fill",
            isOn: Binding(
              get: { isMuted },
              set: { value in updatePreference(isMuted: value, isArchived: isArchived) }
            )
          )
          Toggle(
            "chat.archive",
            systemImage: "archivebox.fill",
            isOn: Binding(
              get: { isArchived },
              set: { value in updatePreference(isMuted: isMuted, isArchived: value) }
            )
          )
        }

        if thread.isGroup {
          Section("chat.members") {
            if canManageGroup {
              Button("chat.new.group_name", systemImage: "pencil") {
                groupName = thread.title
                showingRenameGroup = true
              }
              .accessibilityIdentifier("ui_chat_rename_group")

              Button("chat.add_member", systemImage: "person.badge.plus") {
                showingAddMember = true
              }
              .accessibilityIdentifier("ui_chat_add_member")
            }

            if model.chatStore.membersByChat[thread.id]?.isLoading == true {
              ProgressView()
            } else if let members = model.chatStore.membersByChat[thread.id]?.value {
              ForEach(members) { member in
                ChatMemberRow(
                  member: member,
                  // Owners cannot be demoted or removed, and nobody manages
                  // themselves from this list.
                  canManage: canManageGroup
                    && member.userId != currentUserID
                    && member.role.lowercased() != "owner",
                  updateRole: { role in
                    Task {
                      _ = await model.chatStore.updateMemberRole(
                        member.userId,
                        in: thread.id,
                        role: role
                      )
                    }
                  },
                  remove: {
                    Task {
                      _ = await model.chatStore.removeMember(member.userId, from: thread.id)
                    }
                  }
                )
              }
            }
          }
        }

        // Shared Media Grid
        let media = sharedMediaItems
        if !media.isEmpty {
          Section(header: Text("chat.shared_media")) {
            ScrollView(.horizontal, showsIndicators: false) {
              LazyHStack(spacing: MaxSpace.sm) {
                ForEach(media) { item in
                  ChatGalleryThumbnail(item: item)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
              }
              .padding(.vertical, MaxSpace.xs)
            }
            .listRowBackground(Color.clear)
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .navigationTitle("chat.info")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
      .maxScreenBackground()
      .task {
        await model.chatStore.loadPreference(for: thread.id)
        if thread.isGroup {
          await model.chatStore.loadMembers(for: thread.id)
        }
      }
      .alert("chat.action.nickname.title", isPresented: $showingEditNickname) {
        TextField("chat.action.nickname.placeholder", text: $partnerNickname)
        Button("common.save") {
          if let partnerId {
            let cleaned = partnerNickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
              model.preferencesStore.nicknames.removeValue(forKey: partnerId)
            } else {
              model.preferencesStore.nicknames[partnerId] = cleaned
            }
          }
        }
        Button("common.cancel", role: .cancel) {}
      }
      .alert("chat.new.group_name", isPresented: $showingRenameGroup) {
        TextField("chat.new.group_name", text: $groupName)
        Button("common.save") {
          let name = groupName
          Task { _ = await model.chatStore.renameGroup(thread.id, name: name) }
        }
        Button("common.cancel", role: .cancel) {}
      }
      .sheet(isPresented: $showingAddMember) {
        ChatAddMemberSheet(threadID: thread.id)
      }
      .sheet(isPresented: $showingAvatarDetail) {
        NavigationStack {
          ZStack {
            Color.black.ignoresSafeArea()
            MaxAsyncImage(url: thread.avatarUrl) { phase in
              if let image = phase.image {
                image
                  .resizable()
                  .scaledToFit()
              } else {
                Image(systemName: "person.circle.fill")
                  .font(.system(size: 120))
                  .foregroundStyle(.white.opacity(0.3))
              }
            }
          }
          .navigationTitle(nickname)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("common.close") { showingAvatarDetail = false }
            }
          }
        }
      }
    }
  }

  private func updatePreference(isMuted: Bool, isArchived: Bool) {
    Task {
      _ = await model.chatStore.updatePreference(
        for: thread.id,
        isMuted: isMuted,
        isArchived: isArchived,
        mutedUntil: preference?.mutedUntil
      )
    }
  }
}

private struct ChatMemberRow: View {
  @Environment(\.maxThemePalette) private var palette

  let member: ChatGroupMember
  let canManage: Bool
  let updateRole: (String) -> Void
  let remove: () -> Void

  private var isAdmin: Bool {
    member.role.lowercased() == "admin"
  }

  private static func roleLabel(for role: String) -> LocalizedStringKey {
    switch role.lowercased() {
    case "owner": "chat.role.owner"
    case "admin": "chat.role.admin"
    default: "chat.role.member"
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      MaxAvatar(name: member.displayName, imageURL: member.avatarUrl, size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: member.displayName)
          .font(.subheadline.weight(.semibold))
        // Localized rather than `member.role.capitalized`: the wire value is an
        // English enum, so capitalizing it showed "Owner"/"Admin"/"Member" to
        // Arabic readers.
        Text(Self.roleLabel(for: member.role))
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
      }
      Spacer(minLength: 0)
      if canManage {
        Menu {
          Button(
            isAdmin ? "chat.member.make_member" : "chat.member.make_admin",
            systemImage: isAdmin ? "person" : "person.badge.shield.checkmark"
          ) {
            updateRole(isAdmin ? "member" : "admin")
          }
          Button("action.remove", systemImage: "person.badge.minus", role: .destructive) {
            remove()
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("common.more"))
        .accessibilityIdentifier("ui_chat_member_actions_\(member.userId)")
      }
    }
  }
}

private struct ChatAddMemberSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let threadID: String

  @State private var query = ""
  @State private var searchTask: Task<Void, Never>?
  @State private var isAdding = false

  private var people: [ChatPerson] {
    let existing = Set(
      (model.chatStore.membersByChat[threadID]?.value ?? []).map(\.userId)
    )
    return (model.chatStore.peopleSearch.value ?? []).filter { !existing.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      Group {
        if model.chatStore.peopleSearch.isLoading && people.isEmpty {
          ProgressView("chat.new.loading_people")
        } else if people.isEmpty {
          ContentUnavailableView(
            "chat.new.no_people",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("chat.new.no_people_hint")
          )
        } else {
          List(people) { person in
            Button {
              guard !isAdding else { return }
              isAdding = true
              Task {
                let added = await model.chatStore.addMember(person.id, to: threadID)
                isAdding = false
                if added { dismiss() }
              }
            } label: {
              HStack(spacing: 12) {
                MaxAvatar(name: person.displayName, imageURL: person.avatarUrl, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                  Text(verbatim: person.displayName)
                    .font(.subheadline.weight(.semibold))
                  if let username = person.username, !username.isEmpty {
                    Text(verbatim: "@\(username)")
                      .font(.caption)
                      .foregroundStyle(MaxColor.textSecondary)
                  }
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
            .accessibilityIdentifier("ui_chat_add_member_\(person.id)")
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
        }
      }
      .navigationTitle("chat.add_member")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "chat.new.search_people")
      .onChange(of: query) { _, value in
        searchTask?.cancel()
        searchTask = Task {
          try? await Task.sleep(for: .milliseconds(280))
          guard !Task.isCancelled else { return }
          await model.chatStore.searchPeople(query: value)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
        }
      }
      .task { await model.chatStore.searchPeople(query: "") }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_chat_add_member_sheet")
  }
}
