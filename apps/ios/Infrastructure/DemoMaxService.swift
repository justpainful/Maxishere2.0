import Foundation

/// A deterministic in-process implementation used by UI automation, previews, and the explicit
/// Demo launch mode. It never creates a URLSession and every mutation remains inside this actor.
actor DemoMaxService: MaxService {
  private let original: DemoSnapshot
  private var snapshot: DemoSnapshot
  private var isAuthenticated = false
  private var messageSequence = 100
  private var chatPreferences: [String: ChatThreadPreference] = [:]

  init(snapshot: DemoSnapshot = .original) {
    self.original = snapshot
    self.snapshot = snapshot
  }

  func updateConfiguration(_ configuration: MaxConfiguration) async {
    // Demo Mode intentionally ignores server configuration and can never switch to a live origin.
  }

  func reset() {
    snapshot = original
    isAuthenticated = false
    messageSequence = 100
    chatPreferences = [:]
    try? FileManager.default.removeItem(at: Self.demoProfileMediaRoot())
  }

  func bootstrap() async throws -> MobileBootstrapResponse {
    guard isAuthenticated else { throw DemoServiceError.notAuthenticated }
    return snapshot.bootstrap
  }

  func login(email: String, password: String) async throws -> MobileLoginResponse {
    isAuthenticated = true
    return MobileLoginResponse(
      success: true,
      session: .init(token: "demo-session", transport: "local", tokenType: "Demo"),
      user: snapshot.primaryUser
    )
  }

  func logout() async throws {
    isAuthenticated = false
  }

  func home() async throws -> MobileHomeResponse {
    try requireAuthentication()
    return MobileHomeResponse(
      success: true,
      defaultMode: "browse",
      shuffle: Array(snapshot.media.reversed()),
      browse: snapshot.media,
      filters: ["demo": .bool(true)]
    )
  }

  func media(query: MediaQuery) async throws -> MobileMediaListResponse {
    try requireAuthentication()
    var items = snapshot.media
    let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
    if !search.isEmpty {
      items = items.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
    if let kind = query.kind { items = items.filter { $0.kind == kind } }
    if query.saved { items = items.filter(\.isSaved) }
    if query.unwatched { items = items.filter { !$0.hasProgress } }
    if query.unrated { items = items.filter { $0.rating == nil } }
    if let workspaceID = query.workspaceId {
      items = items.filter { $0.workspace?.id == workspaceID }
    }
    let start = min(max(query.offset, 0), items.count)
    let end = min(start + min(max(query.limit, 1), 100), items.count)
    let page = Array(items[start..<end])
    return MobileMediaListResponse(
      success: true,
      mode: query.mode,
      items: page,
      pagination: .init(
        limit: query.limit,
        offset: start,
        nextOffset: end < items.count ? end : nil
      )
    )
  }

  func library() async throws -> MobileLibraryResponse {
    try requireAuthentication()
    return MobileLibraryResponse(
      success: true,
      personalStorage: .init(
        usedBytes: snapshot.media.reduce(0) { $0 + $1.sizeBytes },
        itemCount: snapshot.media.count
      ),
      workspaces: snapshot.workspaces,
      collections: snapshot.collections,
      saved: snapshot.media.filter(\.isFavorite),
      downloads: DownloadSummary(scope: "demo-device", usedBytes: 0, items: [])
    )
  }

  func addToCollection(
    fileID: String,
    collectionID: String
  ) async throws -> MobileCollectionMutationResponse {
    try requireAuthentication()
    guard snapshot.media.contains(where: { $0.id == fileID }),
          snapshot.collections.contains(where: { $0.id == collectionID }) else {
      throw DemoServiceError.notFound
    }
    return MobileCollectionMutationResponse(
      success: true,
      collectionId: collectionID,
      fileId: fileID,
      added: true,
      operationId: "demo-collection-\(collectionID)-\(fileID)"
    )
  }

  func currentUserID() async -> String? {
    isAuthenticated ? snapshot.primaryUser.id : nil
  }

  func profile() async throws -> MobileProfileResponse {
    try requireAuthentication()
    return makeProfile()
  }

  func updateProfile(_ patch: ProfileUpdateRequest) async throws -> MobileProfileResponse {
    try requireAuthentication()
    let old = snapshot.primaryUser
    let displayName = Self.normalized(patch.displayName, fallback: old.displayName, maximum: 80)
    let username = Self.normalized(patch.username, fallback: old.username ?? "maxdemo", maximum: 40)
    let bio = Self.normalized(patch.bio, fallback: old.bio ?? "", maximum: 240)
    snapshot.primaryUser = MaxUser(
      id: old.id,
      email: old.email,
      username: username,
      displayName: displayName,
      avatarUrl: patch.avatarUrl ?? old.avatarUrl,
      coverUrl: patch.coverUrl ?? old.coverUrl,
      bio: bio,
      role: old.role,
      accessLevel: old.accessLevel
    )
    snapshot.bootstrap = snapshot.bootstrap.replacingUser(snapshot.primaryUser)
    return makeProfile()
  }

  func uploadProfileImage(fileURL: URL, kind: ProfileImageKind) async throws -> URL {
    try requireAuthentication()
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
          let fileSize = values.fileSize,
          fileSize > 0,
          fileSize <= 10 * 1_024 * 1_024 else {
      throw DemoServiceError.invalidProfileImage
    }
    let directory = try Self.demoProfileMediaDirectory()
    let fileExtension = fileURL.pathExtension.isEmpty ? "jpg" : fileURL.pathExtension.lowercased()
    let destination = directory.appendingPathComponent("\(kind.rawValue).\(fileExtension)")
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: fileURL, to: destination)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: destination.path
    )
    return destination
  }

  func chats() async throws -> MobileChatListResponse {
    try requireAuthentication()
    let threads = snapshot.threads.map { thread -> ChatThread in
      let latest = snapshot.messagesByChat[thread.id]?.last
      let preference = chatPreferences[thread.id]
      return ChatThread(
        id: thread.id,
        title: thread.title,
        isGroup: thread.isGroup,
        ownerId: thread.ownerId,
        partnerId: thread.partnerId,
        avatarUrl: thread.avatarUrl,
        lastMessage: latest?.content ?? thread.lastMessage,
        lastMessageAt: latest?.createdAt ?? thread.lastMessageAt,
        unreadCount: thread.unreadCount,
        isMuted: preference?.isMuted ?? thread.isMuted,
        isArchived: preference?.isArchived ?? thread.isArchived,
        mutedUntil: preference?.mutedUntil ?? thread.mutedUntil
      )
    }
    return MobileChatListResponse(success: true, chats: threads)
  }

  func realtimeTicket() async throws -> MaxV2RealtimeTicket {
    throw URLError(.unsupportedURL)
  }

  func searchChatPeople(query: String) async throws -> MobileChatPeopleResponse {
    try requireAuthentication()
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let people = [snapshot.secondUser, snapshot.demoBot].compactMap { user -> ChatPerson? in
      guard normalized.isEmpty
        || user.displayName.localizedCaseInsensitiveContains(normalized)
        || (user.username?.localizedCaseInsensitiveContains(normalized) == true) else { return nil }
      return ChatPerson(
        id: user.id,
        displayName: user.displayName,
        username: user.username,
        avatarUrl: user.avatarUrl
      )
    }
    return MobileChatPeopleResponse(success: true, people: people)
  }

  func createDirectChat(userID: String) async throws -> MobileChatCreateResponse {
    try requireAuthentication()
    guard let person = [snapshot.secondUser, snapshot.demoBot].first(where: { $0.id == userID })
    else { throw DemoServiceError.notFound }
    if let existing = snapshot.threads.first(where: { !$0.isGroup && $0.partnerId == userID }) {
      return MobileChatCreateResponse(success: true, operationId: "demo-reopen", chat: existing)
    }
    let chat = ChatThread(
      id: "demo-direct-\(userID)",
      title: person.displayName,
      isGroup: false,
      ownerId: nil,
      partnerId: person.id,
      avatarUrl: person.avatarUrl,
      lastMessage: "",
      lastMessageAt: nil,
      unreadCount: 0
    )
    snapshot.threads.insert(chat, at: 0)
    snapshot.messagesByChat[chat.id] = []
    return MobileChatCreateResponse(success: true, operationId: "demo-direct", chat: chat)
  }

  func createGroupChat(
    name: String,
    memberIDs: [String]
  ) async throws -> MobileChatCreateResponse {
    try requireAuthentication()
    let allowed = Set([snapshot.secondUser.id, snapshot.demoBot.id])
    guard !memberIDs.isEmpty, memberIDs.allSatisfy(allowed.contains) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let chat = ChatThread(
      id: "demo-group-\(messageSequence)",
      title: name,
      isGroup: true,
      ownerId: snapshot.primaryUser.id,
      partnerId: nil,
      avatarUrl: nil,
      lastMessage: "",
      lastMessageAt: nil,
      unreadCount: 0
    )
    snapshot.threads.insert(chat, at: 0)
    snapshot.messagesByChat[chat.id] = []
    return MobileChatCreateResponse(success: true, operationId: "demo-group", chat: chat)
  }

  func messages(
    chatID: String,
    limit: Int,
    before: String?
  ) async throws -> MobileMessagesResponse {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    var messages = snapshot.messagesByChat[chatID] ?? []
    if let before { messages = messages.filter { ($0.createdAt ?? "") < before } }
    messages = Array(messages.suffix(min(max(limit, 1), 500)))
    return MobileMessagesResponse(success: true, messages: messages)
  }

  func searchMessages(
    chatID: String,
    query: String,
    limit: Int
  ) async throws -> MobileMessagesResponse {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = (snapshot.messagesByChat[chatID] ?? []).filter {
      ($0.content ?? "").localizedCaseInsensitiveContains(normalized)
    }
    return MobileMessagesResponse(
      success: true,
      messages: Array(matches.suffix(min(max(limit, 1), 100)))
    )
  }

  func pinnedMessages(chatID: String) async throws -> MobileMessagesResponse {
    MobileMessagesResponse(
      success: true,
      messages: (snapshot.messagesByChat[chatID] ?? []).filter { $0.isPinned == true }
    )
  }

  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let timestamp = Self.timestamp(sequence: messageSequence)
    let content = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoing = ChatMessage(
      id: "demo-message-\(messageSequence)",
      dmId: chatID,
      senderId: snapshot.primaryUser.id,
      content: content.isEmpty ? nil : content,
      mediaUrl: mediaFileIDs.isEmpty ? nil : "demo://video",
      mediaType: mediaFileIDs.isEmpty ? nil : "video",
      dmMediaId: mediaFileIDs.first,
      mediaName: mediaFileIDs.isEmpty ? nil : "Aurora Passage.mp4",
      isEdited: false,
      isDeleted: false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: replyToID,
      createdAt: timestamp,
      mediaReferences: nil,
      sender: .init(
        id: snapshot.primaryUser.id,
        displayName: snapshot.primaryUser.displayName,
        avatarUrl: snapshot.primaryUser.avatarUrl
      ),
      replyPreview: replyPreview(chatID: chatID, messageID: replyToID)
    )
    snapshot.messagesByChat[chatID, default: []].append(outgoing)

    if snapshot.threads.first(where: { $0.id == chatID })?.partnerId == snapshot.demoBot.id {
      try await Task.sleep(for: .milliseconds(240))
      if mediaFileIDs.isEmpty {
        appendBotReply(chatID: chatID, kind: .normal)
      } else {
        appendBotReply(chatID: chatID, kind: .videoReceived)
        try await Task.sleep(for: .milliseconds(360))
        appendBotReply(chatID: chatID, kind: .videoOpenedAndSaved)
      }
    }
    return MobileMessageSendResponse(
      success: true,
      operationId: "demo-op-\(messageSequence)",
      message: outgoing
    )
  }

  func editMessage(
    chatID: String,
    messageID: String,
    content: String
  ) async throws -> MobileMessageSendResponse {
    try requireAuthentication()
    guard var messages = snapshot.messagesByChat[chatID],
          let index = messages.firstIndex(where: {
            $0.id == messageID && $0.senderId == snapshot.primaryUser.id && !$0.isDeleted
          }) else {
      throw DemoServiceError.notFound
    }
    let old = messages[index]
    let updated = old.replacing(content: content, isEdited: true)
    messages[index] = updated
    snapshot.messagesByChat[chatID] = messages
    return MobileMessageSendResponse(success: true, operationId: "demo-edit", message: updated)
  }

  func deleteMessage(
    chatID: String,
    messageID: String
  ) async throws -> MobileMessageSendResponse {
    try requireAuthentication()
    guard var messages = snapshot.messagesByChat[chatID],
          let index = messages.firstIndex(where: {
            $0.id == messageID && $0.senderId == snapshot.primaryUser.id
          }) else {
      throw DemoServiceError.notFound
    }
    let deleted = messages[index].tombstone()
    messages[index] = deleted
    snapshot.messagesByChat[chatID] = messages
    return MobileMessageSendResponse(success: true, operationId: "demo-delete", message: deleted)
  }

  func setMessagePinned(
    chatID: String,
    messageID: String,
    isPinned: Bool
  ) async throws -> MobileMessageSendResponse {
    guard var messages = snapshot.messagesByChat[chatID],
          let index = messages.firstIndex(where: { $0.id == messageID }) else {
      throw DemoServiceError.notFound
    }
    messages[index] = messages[index].replacing(isPinned: isPinned)
    snapshot.messagesByChat[chatID] = messages
    return MobileMessageSendResponse(
      success: true,
      operationId: "demo-pin-\(messageID)",
      message: messages[index]
    )
  }

  func setMessageReaction(
    chatID: String,
    messageID: String,
    reactionKey: String?
  ) async throws -> MobileChatReactionMutationResponse {
    guard var messages = snapshot.messagesByChat[chatID],
          let index = messages.firstIndex(where: { $0.id == messageID }) else {
      throw DemoServiceError.notFound
    }
    let previous = messages[index].reactions?.first(where: { $0.reactedByMe })?.key
    var reactions = (messages[index].reactions ?? []).map {
      ChatReaction(
        key: $0.key,
        count: max(0, $0.count - ($0.reactedByMe ? 1 : 0)),
        reactedByMe: false,
        userIds: $0.userIds.filter { $0 != snapshot.primaryUser.id }
      )
    }.filter { $0.count > 0 }
    if let reactionKey {
      if let reactionIndex = reactions.firstIndex(where: { $0.key == reactionKey }) {
        let existing = reactions[reactionIndex]
        reactions[reactionIndex] = ChatReaction(
          key: existing.key,
          count: existing.count + 1,
          reactedByMe: true,
          userIds: existing.userIds + [snapshot.primaryUser.id]
        )
      } else {
        reactions.append(ChatReaction(
          key: reactionKey,
          count: 1,
          reactedByMe: true,
          userIds: [snapshot.primaryUser.id]
        ))
      }
    }
    messages[index] = messages[index].replacing(reactions: reactions)
    snapshot.messagesByChat[chatID] = messages
    return MobileChatReactionMutationResponse(
      success: true,
      dmId: chatID,
      messageId: messageID,
      reactionKey: reactionKey,
      previousReactionKey: previous,
      reactions: reactions
    )
  }

  func chatPreference(chatID: String) async throws -> MobileChatPreferenceResponse {
    guard let thread = snapshot.threads.first(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    if let preference = chatPreferences[chatID] {
      return MobileChatPreferenceResponse(success: true, preference: preference)
    }
    return MobileChatPreferenceResponse(
      success: true,
      preference: ChatThreadPreference(
        dmId: chatID,
        userId: snapshot.primaryUser.id,
        isMuted: thread.isMuted == true,
        isArchived: thread.isArchived == true,
        mutedUntil: thread.mutedUntil,
        updatedAt: nil
      )
    )
  }

  func updateChatPreference(
    chatID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String?
  ) async throws -> MobileChatPreferenceMutationResponse {
    let previousResponse = try await chatPreference(chatID: chatID)
    let previous = previousResponse.preference
    let preference = ChatThreadPreference(
      dmId: chatID,
      userId: snapshot.primaryUser.id,
      isMuted: isMuted,
      isArchived: isArchived,
      mutedUntil: mutedUntil,
      updatedAt: ISO8601DateFormatter().string(from: Date())
    )
    chatPreferences[chatID] = preference
    return MobileChatPreferenceMutationResponse(
      success: true,
      preference: preference,
      previous: previous
    )
  }

  func chatMembers(chatID: String) async throws -> MobileChatMembersResponse {
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    return MobileChatMembersResponse(success: true, members: [])
  }

  func createChatPoll(
    chatID: String,
    question: String,
    options: [String],
    allowMultipleVotes: Bool
  ) async throws -> MobileMessageSendResponse {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let poll = ChatPoll(
      id: "demo-poll-\(messageSequence)",
      question: question,
      allowMultipleVotes: allowMultipleVotes,
      isClosed: false,
      createdBy: snapshot.primaryUser.id,
      createdAt: Self.timestamp(sequence: messageSequence),
      options: options.enumerated().map { index, text in
        ChatPollOption(
          id: "demo-poll-\(messageSequence)-option-\(index)",
          text: text,
          voteCount: 0,
          votedByMe: false
        )
      }
    )
    let message = ChatMessage(
      id: "demo-message-\(messageSequence)",
      dmId: chatID,
      senderId: snapshot.primaryUser.id,
      content: nil,
      mediaUrl: nil,
      mediaType: nil,
      dmMediaId: nil,
      mediaName: nil,
      isEdited: false,
      isDeleted: false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: nil,
      createdAt: poll.createdAt,
      mediaReferences: nil,
      sender: ChatMessageActor(
        id: snapshot.primaryUser.id,
        displayName: snapshot.primaryUser.displayName,
        avatarUrl: snapshot.primaryUser.avatarUrl
      ),
      poll: poll
    )
    snapshot.messagesByChat[chatID, default: []].append(message)
    return MobileMessageSendResponse(success: true, operationId: "demo-poll", message: message)
  }

  func setChatPollVote(
    chatID: String,
    pollID: String,
    optionID: String,
    selected: Bool
  ) async throws -> MobileMessageSendResponse {
    guard var messages = snapshot.messagesByChat[chatID],
          let messageIndex = messages.firstIndex(where: { $0.poll?.id == pollID }),
          let poll = messages[messageIndex].poll,
          poll.options.contains(where: { $0.id == optionID }) else {
      throw DemoServiceError.notFound
    }
    let updatedOptions = poll.options.map { option -> ChatPollOption in
      let shouldSelect = option.id == optionID ? selected
        : (poll.allowMultipleVotes ? option.votedByMe : false)
      let oldContribution = option.votedByMe ? 1 : 0
      let newContribution = shouldSelect ? 1 : 0
      return ChatPollOption(
        id: option.id,
        text: option.text,
        voteCount: max(0, option.voteCount - oldContribution + newContribution),
        votedByMe: shouldSelect
      )
    }
    let updatedPoll = ChatPoll(
      id: poll.id,
      question: poll.question,
      allowMultipleVotes: poll.allowMultipleVotes,
      isClosed: poll.isClosed,
      createdBy: poll.createdBy,
      createdAt: poll.createdAt,
      options: updatedOptions
    )
    messages[messageIndex] = messages[messageIndex].replacing(poll: updatedPoll)
    snapshot.messagesByChat[chatID] = messages
    return MobileMessageSendResponse(
      success: true,
      operationId: "demo-poll-vote",
      message: messages[messageIndex]
    )
  }

  func forwardMessage(
    chatID: String,
    messageID: String,
    targetChatID: String
  ) async throws -> MobileMessageSendResponse {
    guard let source = snapshot.messagesByChat[chatID]?.first(where: { $0.id == messageID }),
          snapshot.threads.contains(where: { $0.id == targetChatID }) else {
      throw DemoServiceError.notFound
    }
    let forwarded = source.forwarded(
      id: "demo-forward-\(UUID().uuidString)",
      chatID: targetChatID,
      senderID: snapshot.primaryUser.id
    )
    snapshot.messagesByChat[targetChatID, default: []].append(forwarded)
    return MobileMessageSendResponse(
      success: true,
      operationId: "demo-forward-operation",
      message: forwarded
    )
  }

  func markChatRead(chatID: String) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func ratings(fileID: String) async throws -> MobileRatingsResponse {
    try requireAuthentication()
    guard snapshot.media.contains(where: { $0.id == fileID }) else {
      throw DemoServiceError.notFound
    }
    return MobileRatingsResponse(success: true, subjects: snapshot.ratings[fileID] ?? [])
  }

  func ratedMedia() async throws -> MobileRatedMediaResponse {
    try requireAuthentication()
    let entries = snapshot.media.compactMap { media -> RatedMediaEntry? in
      let subjects = snapshot.ratings[media.id] ?? []
      guard subjects.contains(where: { $0.score != nil }) else { return nil }
      return RatedMediaEntry(media: media, subjects: subjects)
    }
    return MobileRatedMediaResponse(success: true, items: entries)
  }

  func setRating(
    fileID: String,
    targetUserID: String,
    score: Int
  ) async throws -> MobileRatingMutationResponse {
    try requireAuthentication()
    guard (0...5).contains(score), var subjects = snapshot.ratings[fileID],
          let index = subjects.firstIndex(where: { $0.user.id == targetUserID }),
          subjects[index].canEdit else {
      throw DemoServiceError.invalidRating
    }
    let old = subjects[index]
    subjects[index] = RatingSubject(
      user: old.user,
      score: score == 0 ? nil : score,
      updatedAt: Self.timestamp(sequence: messageSequence + score),
      canEdit: old.canEdit
    )
    snapshot.ratings[fileID] = subjects
    return MobileRatingMutationResponse(
      success: true,
      subjectUserId: targetUserID,
      score: score == 0 ? nil : score,
      cleared: score == 0,
      operationId: "demo-rating-\(fileID)-\(targetUserID)-\(score)"
    )
  }

  func saveHistory(fileID: String, position: Double) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func setFavorite(fileID: String, favorite: Bool) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func requestAccess(fileID: String, messageID: String?) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func accessRequests() async throws -> MobileAccessRequestsResponse {
    try requireAuthentication()
    return MobileAccessRequestsResponse(
      success: true,
      incoming: snapshot.accessRequests,
      outgoing: []
    )
  }

  func decideAccessRequest(
    id: String,
    decision: String
  ) async throws -> MobileAccessDecisionResponse {
    try requireAuthentication()
    guard let index = snapshot.accessRequests.firstIndex(where: { $0.id == id }) else {
      throw DemoServiceError.notFound
    }
    let old = snapshot.accessRequests[index]
    let updated = AccessRequest(
      id: old.id,
      fileId: old.fileId,
      requesterUserId: old.requesterUserId,
      ownerUserId: old.ownerUserId,
      messageId: old.messageId,
      note: old.note,
      // "approved"/"denied" are the only values the server accepts, so the demo
      // backend has to match them or Approve in demo mode records a denial.
      status: decision == "approved" ? "approved" : "denied",
      shareId: decision == "approved" ? "demo-share" : nil,
      createdAt: old.createdAt,
      decidedAt: Self.timestamp(sequence: messageSequence),
      decidedBy: snapshot.primaryUser.id,
      fileName: old.fileName,
      requesterName: old.requesterName
    )
    snapshot.accessRequests[index] = updated
    return MobileAccessDecisionResponse(success: true, request: updated, alreadyDecided: false)
  }

  func uploadMultipart(
    fileURL: URL,
    mimeType: String,
    spaceID: String?,
    fileName: String?,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> MobileUploadRegisterResponse {
    try requireAuthentication()
    let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size])
      as? NSNumber)?.int64Value ?? 1
    progress(.init(bytesTransferred: size / 2, totalBytes: size))
    try await Task.sleep(for: .milliseconds(120))
    progress(.init(bytesTransferred: size, totalBytes: size))
    return MobileUploadRegisterResponse(
      success: true,
      fileId: "demo-upload-\(messageSequence + 1)",
      filePath: nil,
      fileType: mimeType,
      sizeBytes: Int(size),
      operationId: "demo-upload-op"
    )
  }

  func downloadFile(
    from remoteURL: URL,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> DownloadedTemporaryFile {
    try requireAuthentication()
    let bytes = Data("MAX DEMO OFFLINE MEDIA\n".utf8)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("max-demo-download-\(UUID().uuidString).mp4")
    progress(.init(bytesTransferred: Int64(bytes.count / 2), totalBytes: Int64(bytes.count)))
    try bytes.write(to: url, options: [.atomic, .completeFileProtection])
    progress(.init(bytesTransferred: Int64(bytes.count), totalBytes: Int64(bytes.count)))
    return DownloadedTemporaryFile(
      url: url,
      statusCode: 200,
      expectedContentLength: Int64(bytes.count),
      suggestedFilename: url.lastPathComponent,
      contentType: "video/mp4"
    )
  }

  func preflightMediaStream(url: URL) async throws {
    try requireAuthentication()
  }

  private func requireAuthentication() throws {
    guard isAuthenticated else { throw DemoServiceError.notAuthenticated }
  }

  private func makeProfile() -> MobileProfileResponse {
    MobileProfileResponse(
      success: true,
      user: snapshot.primaryUser,
      stats: .init(ratedFiles: 3, totalViewed: 18, totalWatchSeconds: 18_900),
      storage: .init(
        usedBytes: snapshot.media.reduce(0) { $0 + $1.sizeBytes },
        fileCount: snapshot.media.count
      ),
      workspaces: snapshot.workspaces,
      favorites: snapshot.media.filter(\.isFavorite),
      personal: .init(
        stickyNotes: [],
        fileFavoritePins: snapshot.media.filter(\.isFavorite).map {
          ProfileFavoritePin(fileId: $0.id, createdAt: "2026-07-14T08:00:00Z")
        },
        personalRatings: snapshot.ratings.compactMap { fileID, subjects in
          guard let score = subjects.first(where: {
            $0.user.id == snapshot.primaryUser.id
          })?.score else { return nil }
          return ProfileRating(
            fileId: fileID,
            name: snapshot.media.first(where: { $0.id == fileID })?.title,
            score: Double(score),
            createdAt: "2026-07-14T08:00:00Z"
          )
        },
        catalogFavorites: [],
        catalogRatings: [],
        showcaseCards: []
      )
    )
  }

  private func replyPreview(chatID: String, messageID: String?) -> ChatReplyPreview? {
    guard let messageID,
          let message = snapshot.messagesByChat[chatID]?.first(where: { $0.id == messageID })
    else { return nil }
    return ChatReplyPreview(
      id: message.id,
      sender: message.sender,
      content: message.isDeleted ? nil : message.content,
      mediaType: message.isDeleted ? nil : message.mediaType,
      isDeleted: message.isDeleted
    )
  }

  private func appendBotReply(chatID: String, kind: DemoBotReplyKind) {
    messageSequence += 1
    let reply = ChatMessage(
      id: "demo-bot-message-\(messageSequence)",
      dmId: chatID,
      senderId: snapshot.demoBot.id,
      content: kind.message,
      mediaUrl: nil,
      mediaType: nil,
      dmMediaId: nil,
      mediaName: nil,
      isEdited: false,
      isDeleted: false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: nil,
      createdAt: Self.timestamp(sequence: messageSequence),
      mediaReferences: nil,
      sender: .init(
        id: snapshot.demoBot.id,
        displayName: snapshot.demoBot.displayName,
        avatarUrl: snapshot.demoBot.avatarUrl
      )
    )
    snapshot.messagesByChat[chatID, default: []].append(reply)
  }

  private static func normalized(_ value: String?, fallback: String, maximum: Int) -> String {
    guard let value else { return fallback }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : String(trimmed.prefix(maximum))
  }

  private static func timestamp(sequence: Int) -> String {
    String(format: "2026-07-14T10:%02d:%02dZ", (sequence / 60) % 60, sequence % 60)
  }

  private static func demoProfileMediaDirectory() throws -> URL {
    let directory = demoProfileMediaRoot()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    return directory
  }

  private static func demoProfileMediaRoot() -> URL {
    let root = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return root.appendingPathComponent("MaxDemoProfileMedia", isDirectory: true)
  }
}

private enum DemoBotReplyKind {
  case normal
  case videoReceived
  case videoOpenedAndSaved

  var message: String {
    switch self {
    case .normal:
      "Demo reply received. Everything here stays on this device."
    case .videoReceived:
      "Video received in this local Demo chat."
    case .videoOpenedAndSaved:
      "I opened the Demo copy and saved it for this walkthrough."
    }
  }
}

enum DemoServiceError: Error, LocalizedError, Sendable {
  case notAuthenticated
  case notFound
  case invalidRating
  case invalidProfileImage

  var errorDescription: String? {
    switch self {
    case .notAuthenticated: String(localized: "error.product.session_expired.reason")
    case .notFound: String(localized: "error.product.not_found.reason")
    case .invalidRating: String(localized: "error.rating.invalid")
    case .invalidProfileImage: String(localized: "error.profile.image_invalid")
    }
  }
}

private extension MobileBootstrapResponse {
  func replacingUser(_ user: MaxUser) -> MobileBootstrapResponse {
    MobileBootstrapResponse(
      success: success,
      user: user,
      preferences: preferences,
      capabilities: capabilities
    )
  }
}

private extension ChatMessage {
  func replacing(poll: ChatPoll) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isHardDeleted: isHardDeleted,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: mediaReferences,
      sender: sender,
      replyPreview: replyPreview,
      isPinned: isPinned,
      pin: pin,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: poll,
      forwardedFrom: forwardedFrom
    )
  }

  func replacing(reactions: [ChatReaction]) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isHardDeleted: isHardDeleted,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: mediaReferences,
      sender: sender,
      replyPreview: replyPreview,
      isPinned: isPinned,
      pin: pin,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: poll,
      forwardedFrom: forwardedFrom
    )
  }

  func replacing(content: String?, isEdited: Bool) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isHardDeleted: isHardDeleted,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: mediaReferences,
      sender: sender,
      replyPreview: replyPreview,
      isPinned: isPinned,
      pin: pin,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: poll,
      forwardedFrom: forwardedFrom
    )
  }

  func tombstone() -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: nil,
      mediaUrl: nil,
      mediaType: nil,
      dmMediaId: nil,
      mediaName: nil,
      isEdited: isEdited,
      isDeleted: true,
      isHardDeleted: false,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: nil,
      sender: sender,
      replyPreview: nil,
      isPinned: false,
      pin: nil,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: nil,
      forwardedFrom: nil
    )
  }

  func replacing(isPinned: Bool) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isHardDeleted: isHardDeleted,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: mediaReferences,
      sender: sender,
      replyPreview: replyPreview,
      isPinned: isPinned,
      pin: pin,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: poll,
      forwardedFrom: forwardedFrom
    )
  }

  func forwarded(id: String, chatID: String, senderID: String) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: chatID,
      senderId: senderID,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: false,
      isDeleted: false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: nil,
      createdAt: ISO8601DateFormatter().string(from: Date()),
      mediaReferences: mediaReferences,
      sender: nil,
      replyPreview: nil,
      isPinned: false,
      pin: nil,
      reactions: nil,
      readReceipts: nil,
      forwardedFrom: ChatForwardedOrigin(
        messageId: forwardedFrom?.messageId ?? self.id,
        dmId: forwardedFrom?.dmId ?? dmId,
        senderId: forwardedFrom?.senderId ?? self.senderId,
        senderName: forwardedFrom?.senderName ?? sender?.displayName,
        forwardedAt: ISO8601DateFormatter().string(from: Date())
      )
    )
  }
}
