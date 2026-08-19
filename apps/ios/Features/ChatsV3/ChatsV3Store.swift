import Foundation
import Observation
import SwiftUI

/// Dedicated state boundary for Chats. Message visibility preferences are kept
/// locally, while edits, pins, forwards and permanent deletes use Max APIs.
@MainActor
@Observable
final class ChatsV3Store {
  private static let hiddenMessagesKey = "max.chats.hidden-message-ids"
  private static let hiddenSentKey = "max.chats.hidden-sent-message-ids"

  private let api: any MaxService

  var selectedTab: ChatsV3Tab = .inbox
  var activeChatID: String? = nil
  var showsNewChatSheet = false
  var inbox: LoadState<[ChatThread]> = .idle
  var activity: LoadState<[ChatActivity]> = .idle
  var messagesByChat: [String: LoadState<[ChatMessage]>] = [:]
  var membersByChat: [String: LoadState<[ChatGroupMember]>] = [:]
  var preferencesByChat: [String: LoadState<ChatThreadPreference>] = [:]
  var composerByChat: [String: String] = [:]
  var sendErrorByChat: [String: String] = [:]
  var isSending = Set<String>()
  var hiddenMessageIDs: Set<String>
  var hiddenSentMessageIDs: Set<String>

  init(api: any MaxService) {
    self.api = api
    hiddenMessageIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenMessagesKey) ?? [])
    hiddenSentMessageIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenSentKey) ?? [])
  }

  func reset() {
    inbox = .idle
    activity = .idle
    messagesByChat = [:]
    membersByChat = [:]
    preferencesByChat = [:]
    composerByChat = [:]
    sendErrorByChat = [:]
    isSending = []
    hiddenMessageIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenMessagesKey) ?? [])
    hiddenSentMessageIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenSentKey) ?? [])
  }

  func visibleMessages(for chatID: String) -> [ChatMessage] {
    (messagesByChat[chatID]?.value ?? []).filter { !hiddenMessageIDs.contains($0.id) }
  }

  // `LoadState.loading` carries no payload, so resetting it on every refresh
  // dropped the populated list and swapped it for the skeleton — on pull to
  // refresh, on the toolbar button, and after all ten post-mutation reloads.
  func loadInbox() async {
    if inbox.value == nil { inbox = .loading }
    do {
      inbox = .loaded(try await api.chats().chats)
    } catch {
      if inbox.value == nil {
        inbox = .failed(ProductError.from(error, area: .chats).reason)
      }
    }
  }

  func loadActivity() async {
    if activity.value == nil { activity = .loading }
    do {
      activity = .loaded(try await api.chatActivity(limit: 100).activities)
    } catch {
      if activity.value == nil {
        activity = .failed(ProductError.from(error, area: .chats).reason)
      }
    }
  }

  func markActivityRead(_ activities: [ChatActivity]) async {
    let unreadIDs = activities.filter { $0.readAt == nil }.map(\.id)
    guard !unreadIDs.isEmpty else { return }
    do {
      _ = try await api.markChatActivityRead(activityIDs: unreadIDs)
      if let existing = activity.value {
        activity = .loaded(existing.map { item in
          unreadIDs.contains(item.id) ? item.markingRead() : item
        })
      }
    } catch {
      // Reading a conversation remains available if notification state is delayed.
    }
  }

  func loadMessages(for chatID: String) async {
    if messagesByChat[chatID]?.value == nil { messagesByChat[chatID] = .loading }
    do {
      messagesByChat[chatID] = .loaded(try await api.messages(
        chatID: chatID,
        limit: 100,
        before: nil
      ).messages)
    } catch {
      if messagesByChat[chatID]?.value == nil {
        messagesByChat[chatID] = .failed(ProductError.from(error, area: .chats).reason)
      }
    }
  }

  func loadMembers(for chatID: String) async {
    membersByChat[chatID] = .loading
    do {
      membersByChat[chatID] = .loaded(try await api.chatMembers(chatID: chatID).members)
    } catch {
      membersByChat[chatID] = .failed(ProductError.from(error, area: .chats).reason)
    }
  }

  func loadPreference(for chatID: String) async {
    preferencesByChat[chatID] = .loading
    do {
      preferencesByChat[chatID] = .loaded(try await api.chatPreference(chatID: chatID).preference)
    } catch {
      preferencesByChat[chatID] = .failed(ProductError.from(error, area: .chats).reason)
    }
  }

  func send(
    in chatID: String,
    replyToID: String? = nil,
    mentionUserIDs: [String] = []
  ) async {
    guard !isSending.contains(chatID) else { return }
    let text = (composerByChat[chatID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    isSending.insert(chatID)
    sendErrorByChat[chatID] = nil
    defer { isSending.remove(chatID) }
    do {
      let sent = try await api.sendMessageV3(
        chatID: chatID,
        caption: text,
        mediaFileIDs: [],
        replyToID: replyToID,
        mentionUserIDs: Array(Set(mentionUserIDs)).prefix(25).map { $0 }
      )
      composerByChat[chatID] = ""
      insert(sent.message, in: chatID)
      await loadInbox()
    } catch {
      sendErrorByChat[chatID] = ProductError.from(error, area: .chats).reason
    }
  }

  func sendImage(in chatID: String, imageData: Data, replyToID: String? = nil, isViewOnce: Bool = false) async {
    guard !isSending.contains(chatID) else { return }
    isSending.insert(chatID)
    sendErrorByChat[chatID] = nil
    defer { isSending.remove(chatID) }
    do {
      let sent = try await api.sendImageMessage(
        chatID: chatID,
        imageData: imageData,
        replyToID: replyToID,
        isViewOnce: isViewOnce
      )
      insert(sent.message, in: chatID)
      await loadInbox()
    } catch {
      sendErrorByChat[chatID] = ProductError.from(error, area: .chats).reason
    }
  }

  func sendVoiceMessage(in chatID: String, audioData: Data, replyToID: String? = nil) async {
    guard !isSending.contains(chatID) else { return }
    isSending.insert(chatID)
    sendErrorByChat[chatID] = nil
    defer { isSending.remove(chatID) }
    do {
      let sent = try await api.sendVoiceMessage(
        chatID: chatID,
        audioData: audioData,
        replyToID: replyToID
      )
      insert(sent.message, in: chatID)
      await loadInbox()
    } catch {
      sendErrorByChat[chatID] = ProductError.from(error, area: .chats).reason
    }
  }

  func clearChat(chatID: String) async -> Bool {
    do {
      _ = try await api.clearChatMessages(chatID: chatID)
      // Clear local memory list of messages
      if var subject = messagesByChat[chatID] {
        subject = .loaded([])
        messagesByChat[chatID] = subject
      }
      await loadInbox()
      return true
    } catch {
      return false
    }
  }

  func readViewOnceMessage(chatID: String, messageID: String) async {
    do {
      _ = try await api.readViewOnceMessage(chatID: chatID, messageID: messageID)
      await loadMessages(for: chatID)
    } catch {
      print("Failed to mark view once read: \(error)")
    }
  }

  func updatePreference(
    chatID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String? = nil
  ) async {
    do {
      let result = try await api.updateChatPreference(
        chatID: chatID,
        isMuted: isMuted,
        isArchived: isArchived,
        mutedUntil: mutedUntil
      )
      preferencesByChat[chatID] = .loaded(result.preference)
      await loadInbox()
    } catch {
      preferencesByChat[chatID] = .failed(ProductError.from(error, area: .chats).reason)
    }
  }

  func updateGroup(chatID: String, name: String) async -> Bool {
    do {
      _ = try await api.updateChatGroup(chatID: chatID, name: name, avatar: nil)
      await loadInbox()
      return true
    } catch {
      return false
    }
  }

  func searchPeople(_ query: String) async -> [ChatPerson] {
    (try? await api.searchChatPeople(query: query).people) ?? []
  }

  func createDirectChat(with userID: String) async -> ChatThread? {
    do {
      let chat = try await api.createDirectChat(userID: userID).chat
      await loadInbox()
      return chat
    } catch {
      return nil
    }
  }

  func createGroupChat(name: String, memberIDs: [String]) async -> ChatThread? {
    do {
      let chat = try await api.createGroupChat(name: name, memberIDs: memberIDs).chat
      await loadInbox()
      return chat
    } catch {
      return nil
    }
  }

  func updateMemberRole(chatID: String, userID: String, role: String) async -> Bool {
    do {
      _ = try await api.updateChatMemberRole(chatID: chatID, userID: userID, role: role)
      await loadMembers(for: chatID)
      return true
    } catch {
      return false
    }
  }

  func removeMember(chatID: String, userID: String) async -> Bool {
    do {
      _ = try await api.removeChatMember(chatID: chatID, userID: userID)
      await loadMembers(for: chatID)
      return true
    } catch {
      return false
    }
  }

  func addMember(chatID: String, userID: String, role: String = "member") async -> Bool {
    do {
      _ = try await api.addChatMember(chatID: chatID, userID: userID, role: role)
      await loadMembers(for: chatID)
      return true
    } catch {
      return false
    }
  }

  func react(to message: ChatMessage, key: String?) async {
    do {
      let result = try await api.setMessageReaction(
        chatID: message.dmId,
        messageID: message.id,
        reactionKey: key
      )
      guard var items = messagesByChat[message.dmId]?.value,
            let index = items.firstIndex(where: { $0.id == message.id }) else { return }
      items[index] = items[index].replacingReactions(result.reactions)
      messagesByChat[message.dmId] = .loaded(items)
    } catch {
      sendErrorByChat[message.dmId] = ProductError.from(error, area: .chats).reason
    }
  }

  /// Telegram-style "Delete for me": hide locally without changing anyone else's copy.
  func delete(_ message: ChatMessage) async {
    hiddenMessageIDs.insert(message.id)
    persistVisibilityPreferences()
  }

  func deletePermanent(_ message: ChatMessage) async {
    do {
      _ = try await api.deleteMessage(chatID: message.dmId, messageID: message.id)
      if var items = messagesByChat[message.dmId]?.value {
        items.removeAll { $0.id == message.id }
        messagesByChat[message.dmId] = .loaded(items)
      }
      hiddenMessageIDs.remove(message.id)
      hiddenSentMessageIDs.remove(message.id)
      persistVisibilityPreferences()
      await loadInbox()
    } catch {
      sendErrorByChat[message.dmId] = ProductError.from(error, area: .chats).reason
    }
  }

  func deleteChat(_ chatID: String) async -> Bool {
    do {
      _ = try await api.deleteChat(chatID: chatID)
      messagesByChat[chatID] = nil
      preferencesByChat[chatID] = nil
      membersByChat[chatID] = nil
      if var threads = inbox.value {
        threads.removeAll { $0.id == chatID }
        inbox = .loaded(threads)
      }
      return true
    } catch {
      sendErrorByChat[chatID] = ProductError.from(error, area: .chats).reason
      return false
    }
  }

  func hideSent(_ message: ChatMessage) async {
    hiddenSentMessageIDs.insert(message.id)
    persistVisibilityPreferences()
  }

  func editMessage(id: String, chatID: String, newContent: String) async {
    let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    do {
      let result = try await api.editMessage(
        chatID: chatID,
        messageID: id,
        content: content
      )
      replace(result.message, in: chatID)
    } catch {
      sendErrorByChat[chatID] = ProductError.from(error, area: .chats).reason
    }
  }

  func setPinned(_ message: ChatMessage, isPinned: Bool) async {
    do {
      let result = try await api.setMessagePinned(
        chatID: message.dmId,
        messageID: message.id,
        isPinned: isPinned
      )
      replace(result.message, in: message.dmId)
    } catch {
      sendErrorByChat[message.dmId] = ProductError.from(error, area: .chats).reason
    }
  }

  func forward(_ message: ChatMessage, to targetChatID: String) async -> Bool {
    do {
      let result = try await api.forwardMessage(
        chatID: message.dmId,
        messageID: message.id,
        targetChatID: targetChatID
      )
      if messagesByChat[targetChatID]?.value != nil {
        insert(result.message, in: targetChatID)
      }
      await loadInbox()
      return true
    } catch {
      sendErrorByChat[message.dmId] = ProductError.from(error, area: .chats).reason
      return false
    }
  }

  private func insert(_ message: ChatMessage, in chatID: String) {
    let current = messagesByChat[chatID]?.value ?? []
    messagesByChat[chatID] = .loaded(Self.merging(current, message))
  }

  private func replace(_ message: ChatMessage, in chatID: String) {
    guard var items = messagesByChat[chatID]?.value,
          let index = items.firstIndex(where: { $0.id == message.id }) else { return }
    items[index] = message
    messagesByChat[chatID] = .loaded(items)
  }

  private func persistVisibilityPreferences() {
    UserDefaults.standard.set(Array(hiddenMessageIDs), forKey: Self.hiddenMessagesKey)
    UserDefaults.standard.set(Array(hiddenSentMessageIDs), forKey: Self.hiddenSentKey)
  }

  private static func merging(_ messages: [ChatMessage], _ incoming: ChatMessage) -> [ChatMessage] {
    var merged = messages.filter { $0.id != incoming.id }
    merged.append(incoming)
    return merged.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
  }
}

enum ChatsV3Tab: String, CaseIterable, Identifiable, Sendable {
  case inbox
  case mentions
  case archive

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .inbox: "chats.title"
    case .mentions: "chat.mentions"
    case .archive: "chat.archive"
    }
  }

  var symbol: String {
    switch self {
    case .inbox: "bubble.left.and.bubble.right"
    case .mentions: "at"
    case .archive: "archivebox"
    }
  }
}
