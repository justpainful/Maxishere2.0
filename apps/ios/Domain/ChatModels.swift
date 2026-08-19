import Foundation

/// The realtime frame the server actually sends:
/// `{"version":1,"type":"chat.message.created","data":{…},"occurredAt":"…"}`.
///
/// The previous shape expected a top-level `event` key that the server has never
/// emitted, so `try?` decoding returned nil for every frame and the socket was
/// silently mute. `occurredAt` is decoded as a String on purpose: Go marshals it
/// with nanosecond precision, which both `.deferredToDate` and `.iso8601` reject.
struct ChatRealtimeEnvelope: Decodable, Sendable {
  let version: Int?
  let type: String
  let data: ChatRealtimeData?
  let occurredAt: String?
}

struct ChatRealtimeData: Decodable, Sendable {
  // The five event types carry disjoint fields, so every one of these is optional.
  let conversationId: String?
  let userId: String?
  let typing: Bool?
  let messageId: String?
  let senderId: String?
  let status: String?
}

enum ChatRealtimeEventType {
  static let ready = "realtime.ready"
  static let messageCreated = "chat.message.created"
  static let readUpdated = "chat.read.updated"
  static let typingUpdated = "chat.typing.updated"
  static let presenceUpdated = "presence.updated"
}

struct PendingChatSend: Hashable, Sendable {
  let threadID: String
  let content: String
  let mediaFileIDs: [String]
  let replyToID: String?
  /// Reused verbatim on retry. Minting a fresh key per attempt defeated the
  /// server's `ON CONFLICT (conversation_id, sender_id, client_message_id)`
  /// de-duplication and produced a duplicate row for every retry.
  let clientMessageID: String

  init(
    threadID: String,
    content: String,
    mediaFileIDs: [String],
    replyToID: String?,
    clientMessageID: String = UUID().uuidString.lowercased()
  ) {
    self.threadID = threadID
    self.content = content
    self.mediaFileIDs = mediaFileIDs
    self.replyToID = replyToID
    self.clientMessageID = clientMessageID
  }
}

struct ChatSendFailure: Hashable, Sendable {
  let transaction: PendingChatSend
  let message: String
  let failedAt: Date
}

enum ChatSendState: Hashable, Sendable {
  case idle
  case sending(PendingChatSend)
  case failed(ChatSendFailure)

  var isSending: Bool {
    if case .sending = self { return true }
    return false
  }

  var errorMessage: String? {
    guard case .failed(let failure) = self else { return nil }
    return failure.message
  }
}

enum MessagePageState: Hashable, Sendable {
  case idle
  case loadingOlder
  case loaded(canLoadMore: Bool)
  case failed(String)

  var isLoading: Bool {
    if case .loadingOlder = self { return true }
    return false
  }

  var errorMessage: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }
}
