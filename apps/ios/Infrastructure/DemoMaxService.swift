import Foundation

/// A deterministic in-process implementation used by UI automation, previews, and the explicit
/// Demo launch mode. It never creates a URLSession and every mutation remains inside this actor.
actor DemoMaxService: MaxService {
  private let original: DemoSnapshot
  private var snapshot: DemoSnapshot
  private var isAuthenticated = false
  private var messageSequence = 100
  private var chatPreferences: [String: ChatThreadPreference] = [:]
  private var chatTTLByThread: [String: Int] = [:]
  private var clipsByMedia: [String: [MediaClip]] = [:]
  private var markersByMedia: [String: [MediaMarker]] = [:]
  private var scheduledByChat: [String: [ScheduledMessage]] = [:]
  private var heatmapByMedia: [String: [Double]] = [:]
  private var stickerRows: [MaxSticker] = []
  private var shareLinkRows: [MaxShareLink] = []
  private var storyRows: [MaxStory] = []
  private var draftByThread: [String: String] = [:]
  private var invitesByThread: [String: [MaxGroupInvite]] = [:]

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
    chatTTLByThread = [:]
    clipsByMedia = [:]
    markersByMedia = [:]
    scheduledByChat = [:]
    heatmapByMedia = [:]
    stickerRows = []
    shareLinkRows = []
    storyRows = []
    draftByThread = [:]
    invitesByThread = [:]
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

  func peerProfileStats(userID: String) async throws -> MaxV2PeerStats {
    try requireAuthentication()
    // Plausible, fixed figures: demo mode is for showing the shape of a screen,
    // and numbers that wander every launch make it hard to tell a layout bug
    // from a data one.
    return MaxV2PeerStats(
      joinedAt: "2026-03-12T09:00:00Z",
      role: "member",
      uploads: 42,
      uploadBytes: 3_221_225_472,
      photos: 8,
      videos: 34,
      ratedCount: 17,
      averageScore: 8.2,
      favoriteCount: 12,
      sharedChats: 2,
      lastUploadAt: "2026-08-20T18:30:00Z"
    )
  }

  func peerProfile(userID: String) async throws -> MaxV2Profile {
    try requireAuthentication()
    // The demo world has synthetic people; any id resolves to a plausible page.
    let person = [snapshot.secondUser, snapshot.demoBot].first(where: { $0.id == userID })
    return MaxV2Profile(
      id: userID,
      username: person?.username ?? "demo",
      displayName: person?.displayName ?? "Demo User",
      bio: "Exploring Max in demo mode.",
      avatarMediaId: nil,
      coverMediaId: nil,
      avatarUrl: person?.avatarUrl,
      coverUrl: nil
    )
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
        mutedUntil: preference?.mutedUntil ?? thread.mutedUntil,
        messageTtlSeconds: chatTTLByThread[thread.id] ?? thread.messageTtlSeconds
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

  func setChatTTL(chatID: String, ttlSeconds: Int?) async throws -> EmptySuccess {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    if let ttlSeconds {
      chatTTLByThread[chatID] = ttlSeconds
    } else {
      chatTTLByThread[chatID] = nil
    }
    return EmptySuccess(success: true)
  }

  func setVoiceTranscript(
    chatID: String,
    messageID: String,
    mediaID: String,
    transcript: String
  ) async throws -> EmptySuccess {
    try requireAuthentication()
    guard snapshot.messagesByChat[chatID]?.contains(where: { $0.id == messageID }) == true else {
      throw DemoServiceError.notFound
    }
    // Demo voice notes carry no attachment rows to update; success is enough
    // for the flow the UI exercises.
    return EmptySuccess(success: true)
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

  // MARK: - Clips & markers (kept in memory, works fully offline)

  func allClips() async throws -> [MediaClip] {
    try requireAuthentication()
    return clipsByMedia.values.flatMap { $0 }.sorted { $0.createdAt > $1.createdAt }
  }

  func mediaClips(mediaID: String) async throws -> [MediaClip] {
    try requireAuthentication()
    return clipsByMedia[mediaID] ?? []
  }

  func createClip(
    mediaID: String,
    title: String,
    startSeconds: Double,
    endSeconds: Double
  ) async throws -> MediaClip {
    try requireAuthentication()
    guard snapshot.media.contains(where: { $0.id == mediaID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let clip = MediaClip(
      id: "demo-clip-\(messageSequence)",
      mediaId: mediaID,
      ownerId: snapshot.primaryUser.id,
      title: title,
      startSeconds: min(startSeconds, endSeconds),
      endSeconds: max(startSeconds, endSeconds),
      createdAt: Self.timestamp(sequence: messageSequence)
    )
    clipsByMedia[mediaID, default: []].append(clip)
    return clip
  }

  func deleteClip(clipID: String) async throws -> EmptySuccess {
    try requireAuthentication()
    for (mediaID, clips) in clipsByMedia {
      clipsByMedia[mediaID] = clips.filter { $0.id != clipID }
    }
    return EmptySuccess(success: true)
  }

  func mediaMarkers(mediaID: String) async throws -> [MediaMarker] {
    try requireAuthentication()
    return markersByMedia[mediaID] ?? []
  }

  func createMarker(
    mediaID: String,
    atSeconds: Double,
    label: String
  ) async throws -> MediaMarker {
    try requireAuthentication()
    guard snapshot.media.contains(where: { $0.id == mediaID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let marker = MediaMarker(
      id: "demo-marker-\(messageSequence)",
      mediaId: mediaID,
      atSeconds: max(atSeconds, 0),
      label: label,
      createdAt: Self.timestamp(sequence: messageSequence)
    )
    markersByMedia[mediaID, default: []].append(marker)
    return marker
  }

  func deleteMarker(markerID: String) async throws -> EmptySuccess {
    try requireAuthentication()
    for (mediaID, markers) in markersByMedia {
      markersByMedia[mediaID] = markers.filter { $0.id != markerID }
    }
    return EmptySuccess(success: true)
  }

  func mediaItem(id: String) async throws -> MaxMediaItem {
    try requireAuthentication()
    guard let item = snapshot.media.first(where: { $0.id == id }) else {
      throw DemoServiceError.notFound
    }
    return item
  }

  // MARK: - Saved Messages & scheduling (kept in memory, works fully offline)

  func savedMessages() async throws -> MobileChatCreateResponse {
    try requireAuthentication()
    let savedID = "demo-saved-messages"
    if let existing = snapshot.threads.first(where: { $0.id == savedID }) {
      return MobileChatCreateResponse(success: true, operationId: "demo-saved", chat: existing)
    }
    let chat = ChatThread(
      id: savedID,
      title: "",
      isGroup: false,
      ownerId: snapshot.primaryUser.id,
      partnerId: nil,
      avatarUrl: nil,
      lastMessage: "",
      lastMessageAt: nil,
      unreadCount: 0
    )
    snapshot.threads.insert(chat, at: 0)
    snapshot.messagesByChat[chat.id] = []
    return MobileChatCreateResponse(success: true, operationId: "demo-saved", chat: chat)
  }

  func scheduleMessage(
    chatID: String,
    body: String,
    clientMessageID: String,
    sendAt: String
  ) async throws -> ScheduledMessage {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let scheduled = ScheduledMessage(
      id: "demo-scheduled-\(messageSequence)",
      conversationId: chatID,
      body: body,
      sendAt: sendAt,
      createdAt: Self.timestamp(sequence: messageSequence)
    )
    scheduledByChat[chatID, default: []].append(scheduled)
    return scheduled
  }

  func scheduledMessages(chatID: String) async throws -> [ScheduledMessage] {
    try requireAuthentication()
    return (scheduledByChat[chatID] ?? []).sorted { $0.sendAt < $1.sendAt }
  }

  func cancelScheduledMessage(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    for (chatID, items) in scheduledByChat {
      scheduledByChat[chatID] = items.filter { $0.id != id }
    }
    return EmptySuccess(success: true)
  }

  // MARK: - Heatmap & clip export

  func sampleHeatmap(mediaID: String, bin: Int) async {
    guard isAuthenticated, (0...99).contains(bin) else { return }
    var bins = heatmapByMedia[mediaID] ?? Array(repeating: 0, count: 100)
    bins[bin] = min(bins[bin] + 0.2, 1)
    heatmapByMedia[mediaID] = bins
  }

  func heatmap(mediaID: String) async throws -> [Double] {
    try requireAuthentication()
    return heatmapByMedia[mediaID] ?? []
  }

  func exportClip(
    clipID: String,
    format: String,
    sendToConversationId: String?
  ) async throws -> EmptySuccess {
    try requireAuthentication()
    guard clipsByMedia.values.contains(where: { clips in clips.contains { $0.id == clipID } }) else {
      throw DemoServiceError.notFound
    }
    return EmptySuccess(success: true)
  }

  // MARK: - Drafts, invites, collection members, continue & wrapped
  //         (kept in memory, works fully offline)

  func updateChatDraft(chatID: String, text: String) async throws -> EmptySuccess {
    try requireAuthentication()
    draftByThread[chatID] = text
    return EmptySuccess(success: true)
  }

  func createGroupInvite(
    chatID: String,
    expiresInSeconds: Int,
    maxUses: Int?
  ) async throws -> MaxGroupInvite {
    try requireAuthentication()
    let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    let invite = MaxGroupInvite(
      id: "demo-invite-\(UUID().uuidString.lowercased())",
      token: token,
      expiresAt: ISO8601DateFormatter().string(
        from: Date().addingTimeInterval(Double(max(expiresInSeconds, 60)))
      ),
      maxUses: maxUses,
      useCount: 0,
      revokedAt: nil,
      createdAt: ISO8601DateFormatter().string(from: Date()),
      link: "https://demo.max.local/join/\(token)"
    )
    invitesByThread[chatID, default: []].insert(invite, at: 0)
    return invite
  }

  func groupInvites(chatID: String) async throws -> [MaxGroupInvite] {
    try requireAuthentication()
    return invitesByThread[chatID] ?? []
  }

  func revokeGroupInvite(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    guard invitesByThread.values.contains(where: { rows in rows.contains { $0.id == id } }) else {
      throw DemoServiceError.notFound
    }
    for (chatID, rows) in invitesByThread {
      invitesByThread[chatID] = rows.filter { $0.id != id }
    }
    return EmptySuccess(success: true)
  }

  func invitePreview(token: String) async throws -> MaxInvitePreview {
    try requireAuthentication()
    guard let chatID = invitesByThread.first(where: { _, rows in
      rows.contains { $0.token == token }
    })?.key else {
      throw DemoServiceError.notFound
    }
    let thread = try await chats().chats.first { $0.id == chatID }
    return MaxInvitePreview(
      conversationId: chatID,
      title: thread?.displayTitle ?? "Demo group",
      avatarUrl: thread?.avatarUrl,
      memberCount: 3,
      alreadyMember: true
    )
  }

  func acceptInvite(token: String) async throws -> MaxInviteAcceptResponse {
    try requireAuthentication()
    guard let chatID = invitesByThread.first(where: { _, rows in
      rows.contains { $0.token == token }
    })?.key else {
      throw DemoServiceError.notFound
    }
    return MaxInviteAcceptResponse(success: true, conversationId: chatID)
  }

  func collectionMembers(collectionID: String) async throws -> [MaxCollectionMember] {
    try requireAuthentication()
    return [
      MaxCollectionMember(
        userId: snapshot.primaryUser.id,
        displayName: snapshot.primaryUser.displayName,
        username: snapshot.primaryUser.username ?? "demo",
        role: "owner",
        createdAt: Self.timestamp(sequence: 0)
      )
    ]
  }

  func addCollectionMember(
    collectionID: String,
    userID: String,
    role: String
  ) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func removeCollectionMember(
    collectionID: String,
    userID: String
  ) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func removeCollectionMedia(
    collectionID: String,
    mediaID: String
  ) async throws -> EmptySuccess {
    try requireAuthentication()
    return EmptySuccess(success: true)
  }

  func continueWatching() async throws -> [MaxContinueItem] {
    try requireAuthentication()
    return snapshot.media
      .filter { $0.kind.lowercased() == "video" && $0.lastPosition > 0 }
      .prefix(3)
      .map { item in
        MaxContinueItem(
          mediaId: item.id,
          name: item.title,
          kind: item.kind,
          posterUrl: item.thumbnailUrl,
          positionSeconds: item.lastPosition,
          durationSeconds: item.duration,
          viewedAt: item.lastViewedAt ?? Self.timestamp(sequence: 0)
        )
      }
  }

  func wrapped() async throws -> MaxWrapped {
    try requireAuthentication()
    let viewed = snapshot.media.filter { $0.lastPosition > 0 }
    return MaxWrapped(
      year: Calendar.current.component(.year, from: Date()),
      watchSeconds: Int(viewed.reduce(0) { $0 + $1.lastPosition }),
      itemsWatched: viewed.count,
      ratingsGiven: snapshot.media.filter { $0.rating != nil }.count,
      favoritesAdded: snapshot.media.filter(\.isFavorite).count,
      uploads: snapshot.media.count,
      busiestMonth: 8,
      topRewatched: try await rewatched()
    )
  }

  // MARK: - Stickers & share links (kept in memory, works fully offline)

  func stickers() async throws -> [MaxSticker] {
    try requireAuthentication()
    // Favorites first, then newest — matching the server's ordering.
    return stickerRows.sorted { lhs, rhs in
      if lhs.favorite != rhs.favorite { return lhs.favorite }
      return lhs.createdAt > rhs.createdAt
    }
  }

  func createSticker(
    imageData: Data,
    mimeType: String,
    emoji: String?
  ) async throws -> MaxSticker {
    try requireAuthentication()
    guard !imageData.isEmpty else { throw DemoServiceError.notFound }
    messageSequence += 1
    let sticker = MaxSticker(
      id: "demo-sticker-\(messageSequence)",
      mediaId: "demo-sticker-media-\(messageSequence)",
      emoji: emoji,
      favorite: false,
      url: nil,
      createdAt: Self.timestamp(sequence: messageSequence)
    )
    stickerRows.append(sticker)
    return sticker
  }

  func deleteSticker(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    stickerRows.removeAll { $0.id == id }
    return EmptySuccess(success: true)
  }

  func favoriteSticker(id: String, favorite: Bool) async throws -> EmptySuccess {
    try requireAuthentication()
    guard let index = stickerRows.firstIndex(where: { $0.id == id }) else {
      throw DemoServiceError.notFound
    }
    let existing = stickerRows[index]
    stickerRows[index] = MaxSticker(
      id: existing.id,
      mediaId: existing.mediaId,
      emoji: existing.emoji,
      favorite: favorite,
      url: existing.url,
      createdAt: existing.createdAt
    )
    return EmptySuccess(success: true)
  }

  func sendSticker(
    chatID: String,
    stickerID: String,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    try requireAuthentication()
    guard snapshot.threads.contains(where: { $0.id == chatID }),
          let sticker = stickerRows.first(where: { $0.id == stickerID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let attachment = ChatAttachment(
      mediaId: sticker.mediaId,
      kind: "sticker",
      mimeType: "image/jpeg",
      name: "Sticker",
      sizeBytes: nil,
      url: sticker.url,
      thumbnailUrl: nil,
      durationSeconds: nil,
      width: nil,
      height: nil,
      openedAt: nil,
      transcript: nil
    )
    let outgoing = ChatMessage(
      id: "demo-message-\(messageSequence)",
      dmId: chatID,
      senderId: snapshot.primaryUser.id,
      content: nil,
      mediaUrl: nil,
      mediaType: nil,
      dmMediaId: sticker.mediaId,
      mediaName: nil,
      isEdited: false,
      isDeleted: false,
      isHardDeleted: false,
      readAt: nil,
      replyToId: replyToID,
      createdAt: Self.timestamp(sequence: messageSequence),
      mediaReferences: nil,
      sender: .init(
        id: snapshot.primaryUser.id,
        displayName: snapshot.primaryUser.displayName,
        avatarUrl: snapshot.primaryUser.avatarUrl
      ),
      replyPreview: replyPreview(chatID: chatID, messageID: replyToID),
      attachments: [attachment]
    )
    snapshot.messagesByChat[chatID, default: []].append(outgoing)
    return MobileMessageSendResponse(
      success: true,
      operationId: "demo-op-\(messageSequence)",
      message: outgoing
    )
  }

  func createShareLink(
    mediaID: String,
    expiresInSeconds: Int,
    maxViews: Int?
  ) async throws -> MaxShareLink {
    try requireAuthentication()
    guard snapshot.media.contains(where: { $0.id == mediaID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let token = "demo-token-\(messageSequence)"
    let link = MaxShareLink(
      id: "demo-share-\(messageSequence)",
      mediaId: mediaID,
      token: token,
      expiresAt: ISO8601DateFormatter().string(
        from: Date().addingTimeInterval(Double(max(expiresInSeconds, 60)))
      ),
      maxViews: maxViews,
      viewCount: 0,
      revokedAt: nil,
      createdAt: Self.timestamp(sequence: messageSequence),
      url: "https://demo.max.local/s/\(token)"
    )
    shareLinkRows.append(link)
    return link
  }

  func shareLinks(mediaID: String) async throws -> [MaxShareLink] {
    try requireAuthentication()
    return shareLinkRows.filter { $0.mediaId == mediaID && $0.revokedAt == nil }
  }

  func revokeShareLink(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    shareLinkRows.removeAll { $0.id == id }
    return EmptySuccess(success: true)
  }

  // MARK: - Stories & rewatched (kept in memory, works fully offline)

  func stories() async throws -> [MaxStoryRail] {
    try requireAuthentication()
    let formatter = ISO8601DateFormatter()
    let now = Date()
    storyRows = storyRows.filter { story in
      guard let expiry = formatter.date(from: story.expiresAt) else { return true }
      return expiry > now
    }
    guard !storyRows.isEmpty else { return [] }
    let user = snapshot.primaryUser
    return [
      MaxStoryRail(
        userId: user.id,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        mine: true,
        unseen: storyRows.filter { !$0.viewed }.count,
        stories: storyRows
      )
    ]
  }

  func postStory(mediaID: String, caption: String) async throws -> MaxStory {
    try requireAuthentication()
    guard let media = snapshot.media.first(where: { $0.id == mediaID }) else {
      throw DemoServiceError.notFound
    }
    messageSequence += 1
    let story = MaxStory(
      id: "demo-story-\(messageSequence)",
      mediaId: mediaID,
      kind: media.kind.lowercased() == "video" ? "video" : "image",
      caption: caption.isEmpty ? nil : caption,
      url: media.mediaUrl,
      posterUrl: media.thumbnailUrl,
      viewed: false,
      createdAt: Self.timestamp(sequence: messageSequence),
      expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(24 * 3600))
    )
    storyRows.append(story)
    return story
  }

  func viewStory(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    guard let index = storyRows.firstIndex(where: { $0.id == id }) else {
      throw DemoServiceError.notFound
    }
    let existing = storyRows[index]
    storyRows[index] = MaxStory(
      id: existing.id,
      mediaId: existing.mediaId,
      kind: existing.kind,
      caption: existing.caption,
      url: existing.url,
      posterUrl: existing.posterUrl,
      viewed: true,
      createdAt: existing.createdAt,
      expiresAt: existing.expiresAt
    )
    return EmptySuccess(success: true)
  }

  func deleteStory(id: String) async throws -> EmptySuccess {
    try requireAuthentication()
    storyRows.removeAll { $0.id == id }
    return EmptySuccess(success: true)
  }

  func adoptSticker(mediaID: String) async throws -> MaxSticker {
    try requireAuthentication()
    messageSequence += 1
    let sticker = MaxSticker(
      id: "demo-sticker-\(messageSequence)",
      mediaId: mediaID,
      emoji: nil,
      favorite: false,
      url: nil,
      createdAt: Self.timestamp(sequence: messageSequence)
    )
    stickerRows.append(sticker)
    return sticker
  }

  func rewatched() async throws -> [MaxRewatchedItem] {
    try requireAuthentication()
    // Derived from the demo heatmap so replaying a video in Demo Mode grows
    // the shelf, matching the live server's heat-based ranking.
    let rows = heatmapByMedia.compactMap { mediaID, bins -> MaxRewatchedItem? in
      guard let media = snapshot.media.first(where: { $0.id == mediaID }) else { return nil }
      let heat = Int((bins.reduce(0, +) * 5).rounded())
      guard heat > 0 else { return nil }
      return MaxRewatchedItem(
        mediaId: mediaID,
        name: media.title,
        kind: media.kind,
        posterUrl: media.thumbnailUrl,
        heatTotal: heat
      )
    }
    return rows.sorted { $0.heatTotal > $1.heatTotal }
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

// MARK: - Watch Together
//
// Demo Mode is a single offline device: there is no second participant, no
// realtime fan-out and no server clock to sync against, so every watch-room
// entry point stays hidden in demo (spec §11) and the service simply refuses.
extension DemoMaxService {
  func createWatchRoom(
    conversationID: String,
    mediaID: String?,
    source: WatchSource?,
    title: String?,
    emoji: String?,
    settings: WatchSettingsPatch?,
    resumeFromRoomID: String?
  ) async throws -> WatchRoom {
    throw URLError(.unsupportedURL)
  }

  func watchRoom(roomID: String) async throws -> WatchRoom {
    throw URLError(.unsupportedURL)
  }

  func activeWatchRoom(conversationID: String) async throws -> WatchRoom {
    throw URLError(.unsupportedURL)
  }

  func joinWatchRoom(roomID: String) async throws -> WatchRoom {
    throw URLError(.unsupportedURL)
  }

  func leaveWatchRoom(roomID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func sendWatchSignal(
    roomID: String,
    type: String,
    payload: JSONValue
  ) async throws -> WatchSignalResponse {
    throw URLError(.unsupportedURL)
  }

  func watchRoomState(roomID: String) async throws -> WatchCanonicalState {
    throw URLError(.unsupportedURL)
  }

  func updateWatchSettings(
    roomID: String,
    patch: WatchSettingsPatch
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func updateWatchRoomMeta(
    roomID: String,
    title: String?,
    emoji: String?
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func replaceWatchQueue(roomID: String, mediaIDs: [String]) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func addWatchQueueItem(roomID: String, mediaID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func removeWatchQueueItem(roomID: String, index: Int) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func setWatchParticipantRole(
    roomID: String,
    userID: String,
    role: String
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func kickWatchParticipant(roomID: String, userID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func transferWatchHost(roomID: String, userID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func endWatchRoom(roomID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func watchHistory(conversationID: String, limit: Int) async throws -> [WatchHistoryEntry] {
    throw URLError(.unsupportedURL)
  }

  func createWatchGuestLink(
    roomID: String,
    expiresInHours: Int?,
    maxUses: Int?
  ) async throws -> WatchGuestLink {
    throw URLError(.unsupportedURL)
  }

  func watchGuestLinks(roomID: String) async throws -> [WatchGuestLink] {
    throw URLError(.unsupportedURL)
  }

  func revokeWatchGuestLink(linkID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  func createWatchScheduled(
    conversationID: String,
    scheduledAt: String,
    title: String?,
    emoji: String?,
    mediaID: String?,
    source: WatchSource?
  ) async throws -> WatchScheduledEntry {
    throw URLError(.unsupportedURL)
  }

  func watchScheduled(conversationID: String) async throws -> [WatchScheduledEntry] {
    throw URLError(.unsupportedURL)
  }

  func deleteWatchScheduled(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
}
