// Hand-maintained transport types for the v2 API. Keep in step with
// contracts/openapi.yaml — this file is NOT generated, and the previous
// "DO NOT EDIT" header invited a regeneration that would have deleted every
// field the app depends on.

import Foundation

struct MaxV2User: Codable, Hashable, Sendable {
  let id: String
  let email: String?
  let username: String?
  let displayName: String
  let avatarUrl: URL?
  let coverUrl: URL?
  let bio: String?
  let role: String?
  let accessLevel: Int?
}

struct MaxV2Session: Codable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: String
  let user: MaxV2User
}

struct MaxV2Profile: Codable, Sendable {
  let id: String
  let username: String
  let displayName: String
  let bio: String
  let avatarMediaId: String?
  let coverMediaId: String?
}

struct MaxV2Bootstrap: Codable, Sendable {
  let user: MaxV2User
  let capabilities: MaxV2Capabilities
  let settings: MaxV2Settings
}

struct MaxV2Capabilities: Codable, Sendable {
  let apiVersion: String
  let productName: String
  let realtime: Bool
  let pluginCatalog: Bool
  let pluginCodeExecution: Bool
  let features: [String: Bool]
}

struct MaxV2Settings: Codable, Sendable {
  let locale: String
  let autoplay: Bool
  let notificationPreferences: [String: JSONValue]
  let privacy: [String: JSONValue]
  let updatedAt: String
}

struct MaxV2CursorPage<Item: Codable & Sendable>: Codable, Sendable {
  let items: [Item]
  let nextCursor: String?
  /// How many items match the query in total, not just on this page.
  ///
  /// Optional so a server that predates the field still decodes; a summary that
  /// counts the page instead reports the page size, which is how every total in
  /// the app came to read "100".
  let total: Int?
}

struct MaxV2Media: Codable, Hashable, Sendable {
  let id: String
  let name: String
  let mimeType: String
  let kind: String
  let sizeBytes: Int
  let processingState: String
  let createdAt: String
  let durationSeconds: Double?
  /// Source pixel dimensions, used to lay a tile out at the shape of its media
  /// instead of cropping it into a fixed frame.
  let width: Int?
  let height: Int?
  let mediaUrl: URL?
  let thumbnailUrl: URL?
  let rating: Int?
  let favorite: Bool?
  let isSaved: Bool?
  let lastPositionSeconds: Double
  let lastViewedAt: String?
  let isPrivate: Bool?
  let downloadable: Bool?
  // Present only when listing trashed media (GET /media/trash). Optional so the
  // ordinary media list, which omits them, keeps decoding unchanged.
  let deletedAt: String?
  let purgeAfter: String?
}

struct MaxV2Conversation: Codable, Hashable, Sendable {
  let id: String
  let kind: String
  let title: String?
  let createdAt: String
  let updatedAt: String
  let ownerId: String?
  let partnerId: String?
  let avatarUrl: URL?
  let lastMessage: String?
  let lastMessageAt: String?
  let unreadCount: Int?
  let isMuted: Bool?
  let isArchived: Bool?
  let mutedUntil: String?
}

struct MaxV2Message: Codable, Hashable, Sendable {
  let id: String
  let conversationId: String
  let senderId: String
  let senderName: String?
  let senderAvatarUrl: URL?
  let body: String
  // Optional so a server that still emits `null` for this collection cannot make
  // the whole message — and therefore the whole page — fail to decode.
  let attachmentIds: [String]?
  let viewOnce: Bool
  let mediaUrl: String?
  let mediaType: String?
  let mediaName: String?
  let dmMediaId: String?
  let isEdited: Bool?
  let isDeleted: Bool?
  let isPinned: Bool?
  let editedAt: String?
  let replyToId: String?
  let createdAt: String
  let attachments: [ChatAttachment]?
  let reactions: [ChatReaction]?
  let readReceipts: [ChatReadReceipt]?
  let replyPreview: ChatReplyPreview?
  let forwardedFrom: ChatForwardedOrigin?
}

struct MaxV2UploadSession: Codable, Sendable {
  struct Part: Codable, Sendable {
    let partNumber: Int
    let url: URL
  }

  let id: String
  let provider: String
  let objectKey: String
  let uploadId: String
  let partSizeBytes: Int
  let parts: [Part]
  let expiresAt: String
}

struct MaxV2RealtimeTicket: Codable, Sendable {
  let ticket: String
  let expiresAt: String
  let websocketUrl: URL?
}

struct MaxV2Space: Codable, Hashable, Sendable {
  let id: String
  let name: String
  let storageQuotaBytes: Int
  let createdAt: String
}

struct MaxV2Collection: Codable, Hashable, Sendable {
  let id: String
  let spaceId: String?
  let name: String
  let description: String
  let createdAt: String
  let updatedAt: String
}

struct MaxV2ErrorEnvelope: Codable, Sendable {
  struct Detail: Codable, Sendable {
    let code: String
    let message: String
    let requestId: String
  }

  let error: Detail
}

extension MaxV2User {
  var domainModel: MaxUser {
    MaxUser(
      id: id,
      email: email,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      coverUrl: coverUrl,
      bio: bio,
      role: role,
      accessLevel: accessLevel
    )
  }
}

extension MaxV2Media {
  var domainModel: MaxMediaItem {
    MaxMediaItem(
      id: id,
      title: name,
      kind: kind,
      sizeBytes: sizeBytes,
      duration: durationSeconds,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      videoThumbnailUrl: nil,
      uploader: .init(id: nil, name: nil, avatarUrl: nil),
      workspace: nil,
      uploadedAt: createdAt,
      rating: rating,
      isFavorite: favorite ?? false,
      isSaved: isSaved ?? false,
      lastPosition: lastPositionSeconds,
      lastViewedAt: lastViewedAt,
      isPrivate: isPrivate ?? false,
      downloadable: downloadable ?? true,
      width: width,
      height: height
    )
  }

  /// Wraps the media with its trash metadata for the Trash screen.
  var trashedModel: TrashedMedia {
    TrashedMedia(
      media: domainModel,
      deletedAt: MaxV2Media.iso8601(deletedAt),
      purgeAfter: MaxV2Media.iso8601(purgeAfter)
    )
  }

  private static func iso8601(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
  }
}

extension MaxV2Conversation {
  var domainModel: ChatThread {
    ChatThread(
      id: id,
      title: title ?? "",
      isGroup: kind == "group",
      ownerId: ownerId,
      partnerId: partnerId,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage ?? "",
      lastMessageAt: lastMessageAt ?? updatedAt,
      unreadCount: unreadCount ?? 0,
      isMuted: isMuted,
      isArchived: isArchived,
      mutedUntil: mutedUntil
    )
  }
}

extension MaxV2Message {
  func domainModel(conversationID: String) -> ChatMessage {
    let attachments = (self.attachments ?? []).isEmpty ? nil : self.attachments
    let firstAttachment = attachments?.first
    let resolvedName = senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return ChatMessage(
      id: id,
      dmId: conversationId.isEmpty ? conversationID : conversationId,
      senderId: senderId,
      content: body,
      mediaUrl: mediaUrl ?? firstAttachment?.url?.absoluteString,
      mediaType: mediaType ?? firstAttachment?.mimeType,
      dmMediaId: dmMediaId ?? firstAttachment?.mediaId,
      mediaName: mediaName ?? firstAttachment?.name,
      // The server emits `isEdited` now, but `editedAt` has always been on the
      // wire; honouring both keeps the badge working against either build.
      isEdited: isEdited ?? (editedAt != nil),
      isDeleted: isDeleted ?? false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: nil,
      // A missing sender name must stay nil so every call site keeps its own
      // fallback instead of rendering a hardcoded placeholder name.
      sender: (resolvedName?.isEmpty == false || senderAvatarUrl != nil)
        ? ChatMessageActor(
            id: senderId,
            displayName: resolvedName ?? "",
            avatarUrl: senderAvatarUrl
          )
        : nil,
      replyPreview: replyPreview,
      isPinned: isPinned,
      reactions: reactions,
      readReceipts: readReceipts,
      forwardedFrom: forwardedFrom,
      isViewOnce: viewOnce,
      isViewOnceExpired: viewOnce ? (firstAttachment?.openedAt != nil) : nil,
      attachments: attachments
    )
  }
}
