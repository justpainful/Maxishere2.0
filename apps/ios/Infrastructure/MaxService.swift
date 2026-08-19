import Foundation

/// The single product-data boundary used by both the live app and the fully local Demo Mode.
/// Feature stores depend on this contract so selecting Demo Mode happens before any live client
/// or persistent production session is created.
protocol MaxService: Sendable {
  func updateConfiguration(_ configuration: MaxConfiguration) async

  func bootstrap() async throws -> MobileBootstrapResponse
  func login(email: String, password: String) async throws -> MobileLoginResponse
  func logout() async throws

  func home() async throws -> MobileHomeResponse
  func media(query: MediaQuery) async throws -> MobileMediaListResponse
  func library() async throws -> MobileLibraryResponse
  func addToCollection(
    fileID: String,
    collectionID: String
  ) async throws -> MobileCollectionMutationResponse
  func currentUserID() async -> String?

  func profile() async throws -> MobileProfileResponse
  func updateProfile(_ patch: ProfileUpdateRequest) async throws -> MobileProfileResponse
  func uploadProfileImage(fileURL: URL, kind: ProfileImageKind) async throws -> URL

  func chats() async throws -> MobileChatListResponse
  func realtimeTicket() async throws -> MaxV2RealtimeTicket
  func searchChatPeople(query: String) async throws -> MobileChatPeopleResponse
  func createDirectChat(userID: String) async throws -> MobileChatCreateResponse
  func createGroupChat(
    name: String,
    memberIDs: [String]
  ) async throws -> MobileChatCreateResponse
  func messages(
    chatID: String,
    limit: Int,
    before: String?
  ) async throws -> MobileMessagesResponse
  func searchMessages(
    chatID: String,
    query: String,
    limit: Int
  ) async throws -> MobileMessagesResponse
  func pinnedMessages(chatID: String) async throws -> MobileMessagesResponse
  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?
  ) async throws -> MobileMessageSendResponse
  /// Same as `sendMessage` but with a caller-supplied idempotency key, so a retry
  /// of a send that actually reached the server updates the original row instead
  /// of inserting a duplicate.
  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    clientMessageID: String
  ) async throws -> MobileMessageSendResponse
  func editMessage(
    chatID: String,
    messageID: String,
    content: String
  ) async throws -> MobileMessageSendResponse
  func deleteMessage(
    chatID: String,
    messageID: String
  ) async throws -> MobileMessageSendResponse
  func setMessagePinned(
    chatID: String,
    messageID: String,
    isPinned: Bool
  ) async throws -> MobileMessageSendResponse
  func setMessageReaction(
    chatID: String,
    messageID: String,
    reactionKey: String?
  ) async throws -> MobileChatReactionMutationResponse
  func chatPreference(chatID: String) async throws -> MobileChatPreferenceResponse
  func updateChatPreference(
    chatID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String?
  ) async throws -> MobileChatPreferenceMutationResponse
  func chatMembers(chatID: String) async throws -> MobileChatMembersResponse
  func createChatPoll(
    chatID: String,
    question: String,
    options: [String],
    allowMultipleVotes: Bool
  ) async throws -> MobileMessageSendResponse
  func setChatPollVote(
    chatID: String,
    pollID: String,
    optionID: String,
    selected: Bool
  ) async throws -> MobileMessageSendResponse
  func forwardMessage(
    chatID: String,
    messageID: String,
    targetChatID: String
  ) async throws -> MobileMessageSendResponse
  func markChatRead(chatID: String) async throws -> EmptySuccess
  func chatActivity(limit: Int) async throws -> MobileChatActivityResponse
  func markChatActivityRead(activityIDs: [String]) async throws -> MobileChatActivityReadResponse
  func sendMessageV3(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    mentionUserIDs: [String]
  ) async throws -> MobileMessageSendResponse
  func updateChatGroup(
    chatID: String,
    name: String?,
    avatar: String?
  ) async throws -> MobileChatGroupMutationResponse
  func addChatMember(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse
  func updateChatMemberRole(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse
  func removeChatMember(chatID: String, userID: String) async throws -> MobileChatMemberMutationResponse
  func deleteChat(chatID: String) async throws -> EmptySuccess
  func sendImageMessage(
    chatID: String,
    imageData: Data,
    replyToID: String?,
    isViewOnce: Bool
  ) async throws -> MobileMessageSendResponse
  func sendVoiceMessage(
    chatID: String,
    audioData: Data,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse
  func clearChatMessages(chatID: String) async throws -> EmptySuccess
  func readViewOnceMessage(chatID: String, messageID: String) async throws -> EmptySuccess

  func ratings(fileID: String) async throws -> MobileRatingsResponse
  func ratedMedia() async throws -> MobileRatedMediaResponse
  func setRating(
    fileID: String,
    targetUserID: String,
    score: Int
  ) async throws -> MobileRatingMutationResponse
  func saveHistory(fileID: String, position: Double) async throws -> EmptySuccess
  func setFavorite(fileID: String, favorite: Bool) async throws -> EmptySuccess

  func trashedMedia(cursor: String?) async throws -> TrashedMediaPage
  func trashMedia(fileID: String) async throws -> EmptySuccess
  func restoreMedia(fileID: String) async throws -> EmptySuccess
  func purgeMedia(fileID: String) async throws -> EmptySuccess

  func requestAccess(fileID: String, messageID: String?) async throws -> EmptySuccess
  func accessRequests() async throws -> MobileAccessRequestsResponse
  func decideAccessRequest(
    id: String,
    decision: String
  ) async throws -> MobileAccessDecisionResponse

  func uploadMultipart(
    fileURL: URL,
    mimeType: String,
    spaceID: String?,
    fileName: String?,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> MobileUploadRegisterResponse
  func downloadFile(
    from remoteURL: URL,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> DownloadedTemporaryFile

  /// Verifies that AVPlayer can obtain a ranged byte response from the exact
  /// media URL before attempting to construct an AVURLAsset.
  func preflightMediaStream(url: URL) async throws
}

extension MaxService {
  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    clientMessageID: String
  ) async throws -> MobileMessageSendResponse {
    try await sendMessage(
      chatID: chatID,
      caption: caption,
      mediaFileIDs: mediaFileIDs,
      replyToID: replyToID
    )
  }

  func searchChatPeople(query: String) async throws -> MobileChatPeopleResponse {
    MobileChatPeopleResponse(success: true, people: [])
  }

  func createDirectChat(userID: String) async throws -> MobileChatCreateResponse {
    throw URLError(.unsupportedURL)
  }

  func createGroupChat(
    name: String,
    memberIDs: [String]
  ) async throws -> MobileChatCreateResponse {
    throw URLError(.unsupportedURL)
  }

  func searchMessages(
    chatID: String,
    query: String,
    limit: Int
  ) async throws -> MobileMessagesResponse {
    let response = try await messages(chatID: chatID, limit: 500, before: nil)
    let matches = response.messages.filter {
      ($0.content ?? "").localizedCaseInsensitiveContains(query)
    }
    return MobileMessagesResponse(success: true, messages: Array(matches.suffix(limit)))
  }

  func pinnedMessages(chatID: String) async throws -> MobileMessagesResponse {
    let response = try await messages(chatID: chatID, limit: 500, before: nil)
    return MobileMessagesResponse(
      success: true,
      messages: response.messages.filter { $0.isPinned == true }
    )
  }

  func setMessageReaction(
    chatID: String,
    messageID: String,
    reactionKey: String?
  ) async throws -> MobileChatReactionMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func chatPreference(chatID: String) async throws -> MobileChatPreferenceResponse {
    throw URLError(.unsupportedURL)
  }

  func updateChatPreference(
    chatID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String?
  ) async throws -> MobileChatPreferenceMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func chatMembers(chatID: String) async throws -> MobileChatMembersResponse {
    MobileChatMembersResponse(success: true, members: [])
  }

  func createChatPoll(
    chatID: String,
    question: String,
    options: [String],
    allowMultipleVotes: Bool
  ) async throws -> MobileMessageSendResponse {
    throw URLError(.unsupportedURL)
  }

  func setChatPollVote(
    chatID: String,
    pollID: String,
    optionID: String,
    selected: Bool
  ) async throws -> MobileMessageSendResponse {
    throw URLError(.unsupportedURL)
  }

  func chatActivity(limit: Int) async throws -> MobileChatActivityResponse {
    MobileChatActivityResponse(success: true, activities: [])
  }

  func markChatActivityRead(activityIDs: [String]) async throws -> MobileChatActivityReadResponse {
    MobileChatActivityReadResponse(success: true, markedCount: 0)
  }

  func sendMessageV3(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    mentionUserIDs: [String]
  ) async throws -> MobileMessageSendResponse {
    try await sendMessage(
      chatID: chatID,
      caption: caption,
      mediaFileIDs: mediaFileIDs,
      replyToID: replyToID
    )
  }

  func updateChatGroup(
    chatID: String,
    name: String?,
    avatar: String?
  ) async throws -> MobileChatGroupMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func addChatMember(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func updateChatMemberRole(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func removeChatMember(chatID: String, userID: String) async throws -> MobileChatMemberMutationResponse {
    throw URLError(.unsupportedURL)
  }

  func deleteChat(chatID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func sendImageMessage(
    chatID: String,
    imageData: Data,
    replyToID: String?,
    isViewOnce: Bool
  ) async throws -> MobileMessageSendResponse {
    throw URLError(.unsupportedURL)
  }
  func sendVoiceMessage(
    chatID: String,
    audioData: Data,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    throw URLError(.unsupportedURL)
  }
  func clearChatMessages(chatID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func readViewOnceMessage(chatID: String, messageID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  // Trash defaults keep non-live conformers (e.g. Demo Mode) compiling. The live
  // client overrides all four with real /api/v2 calls.
  func trashedMedia(cursor: String?) async throws -> TrashedMediaPage {
    TrashedMediaPage(items: [], nextCursor: nil)
  }
  func trashMedia(fileID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func restoreMedia(fileID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func purgeMedia(fileID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
}
