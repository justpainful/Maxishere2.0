import Foundation

actor MaxAPIClient: MaxService {
  private var configuration: MaxConfiguration
  private var authenticatedUserID: String?
  private let tokenStore: any SessionTokenStore
  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private var refreshTask: Task<SessionCredentials, Error>?

  init(
    configuration: MaxConfiguration,
    tokenStore: any SessionTokenStore,
    session: URLSession = .shared
  ) {
    self.configuration = configuration
    self.tokenStore = tokenStore
    self.session = session
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    self.encoder = JSONEncoder()
  }

  func updateConfiguration(_ config: MaxConfiguration) async {
    self.configuration = config
  }

  func bootstrap() async throws -> MobileBootstrapResponse {
    let response: MaxV2Bootstrap = try await request(path: "/api/v2/bootstrap")
    authenticatedUserID = response.user.id
    return Self.bootstrapResponse(response)
  }


  func login(email: String, password: String) async throws -> MobileLoginResponse {
    var loginRequest = try makeRequest(path: "/api/v2/auth/login", method: "POST")
    loginRequest.setValue(nil, forHTTPHeaderField: "Authorization")
    loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    loginRequest.httpBody = try encoder.encode(
      LoginRequest(
        identity: email,
        password: password,
        deviceName: "Max for iPhone",
        platform: "ios",
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      )
    )
    let (data, response) = try await session.data(for: loginRequest)
    try validate(response: response, data: data)
    let sessionResponse = try decoder.decode(MaxV2Session.self, from: data)
    try tokenStore.saveCredentials(
      SessionCredentials(
        accessToken: sessionResponse.accessToken,
        refreshToken: sessionResponse.refreshToken
      )
    )
    let user = sessionResponse.user.domainModel
    authenticatedUserID = user.id
    return MobileLoginResponse(
      success: true,
      session: .init(token: sessionResponse.accessToken, transport: "bearer", tokenType: "Bearer"),
      user: user
    )
  }

  func logout() async throws {
    // Signing out locally is safety-critical. It must succeed even when a
    // remote revoke request fails because the device may be offline.
    defer {
      authenticatedUserID = nil
      try? tokenStore.clearToken()
    }
    try await requestNoContent(path: "/api/v2/auth/logout", method: "POST")
  }

  func home() async throws -> MobileHomeResponse {
    let page = try await media(query: .init())
    return MobileHomeResponse(
      success: true,
      defaultMode: "browse",
      shuffle: page.items.shuffled(),
      browse: page.items,
      filters: [:]
    )
  }

  func media(query: MediaQuery = .init()) async throws -> MobileMediaListResponse {
    let page: MaxV2CursorPage<MaxV2Media> = try await request(
      path: "/api/v2/media\(query.queryString)"
    )
    return MobileMediaListResponse(
      success: true,
      mode: query.mode,
      items: page.items.map(\.domainModel),
      pagination: .init(
        limit: min(max(query.limit, 1), 100),
        offset: max(query.offset, 0),
        nextOffset: page.nextCursor == nil ? nil : max(query.offset, 0) + page.items.count,
        total: page.total
      )
    )
  }

  func library() async throws -> MobileLibraryResponse {
    let media = try await allMedia()
    let spaces: MaxV2CursorPage<MaxV2Space> = try await request(path: "/api/v2/spaces")
    let collections: MaxV2CursorPage<MaxV2Collection> = try await request(
      path: "/api/v2/collections"
    )
    let items = media.map(\.domainModel)
    return MobileLibraryResponse(
      success: true,
      personalStorage: .init(
        usedBytes: items.reduce(0) { $0 + $1.sizeBytes },
        itemCount: items.count
      ),
      workspaces: spaces.items.map {
        WorkspaceSummary(
          id: $0.id,
          name: $0.name,
          ownerId: nil,
          coverUrl: nil,
          description: nil,
          spaceType: "space",
          itemCount: nil
        )
      },
      collections: collections.items.map {
        CollectionSummary(
          id: $0.id,
          name: $0.name,
          userId: nil,
          coverUrlFileId: nil,
          itemCount: nil
        )
      },
      // `favorite` is the flag the heart writes, here and on the desktop. It used
      // to share the job with a separate watch-later flag surfaced as `isSaved`,
      // and filtering on that one — which iOS never set — is why liking a video
      // left this shelf empty. Backend migration 00011 merged them.
      saved: items.filter(\.isFavorite),
      downloads: .init(scope: "device", usedBytes: 0, items: [])
    )
  }

  func addToCollection(
    fileID: String,
    collectionID: String
  ) async throws -> MobileCollectionMutationResponse {
    try await request(
      path: "/api/v2/collections/\(encodedPathSegment(collectionID))/items",
      method: "POST",
      body: CollectionItemRequest(fileId: fileID)
    )
  }

  func currentUserID() async -> String? {
    authenticatedUserID
  }

  func profile() async throws -> MobileProfileResponse {
    let user: MaxV2User = try await request(path: "/api/v2/me")
    let media = try await allMedia()
    let spaces: MaxV2CursorPage<MaxV2Space> = try await request(path: "/api/v2/spaces")
    return Self.profileResponse(
      user: user.domainModel,
      media: media.map(\.domainModel),
      spaces: spaces.items
    )
  }

  func updateProfile(_ patch: ProfileUpdateRequest) async throws -> MobileProfileResponse {
    let _: MaxV2Profile = try await request(
      path: "/api/v2/me",
      method: "PATCH",
      body: LiveProfileUpdateRequest(
        displayName: patch.displayName,
        username: patch.username,
        bio: patch.bio
      )
    )
    return try await profile()
  }

  func uploadProfileImage(fileURL: URL, kind: ProfileImageKind) async throws -> URL {
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
          let fileSize = values.fileSize,
          fileSize > 0,
          fileSize <= 10 * 1_024 * 1_024 else {
      throw MaxAPIError.invalidProfileImage
    }

    let uploaded = try await uploadMultipart(
      fileURL: fileURL,
      mimeType: Self.imageMIMEType(for: fileURL),
      spaceID: nil,
      fileName: fileURL.lastPathComponent
    )
    guard let uploadedMediaID = uploaded.fileId else { throw MaxAPIError.invalidResponse }
    let _: MaxV2Profile = try await request(
      path: "/api/v2/me",
      method: "PATCH",
      body: ProfileMediaPatch(
        avatarMediaId: kind == .avatar ? uploadedMediaID : nil,
        coverMediaId: kind == .cover ? uploadedMediaID : nil
      )
    )
    // Upload completion deliberately returns only durable media metadata. The
    // signed display URL belongs to the profile response after the media ID has
    // been attached; requiring a URL from completion caused every avatar/cover
    // upload to report "Upload Failed" after the object had already uploaded.
    let updated: MaxV2User = try await request(path: "/api/v2/me")
    guard let resolved = (kind == .avatar ? updated.avatarUrl : updated.coverUrl) else {
      throw MaxAPIError.invalidResponse
    }
    return resolved
  }

  func chats() async throws -> MobileChatListResponse {
    // The API caps a page at 100 regardless of what is asked for, so follow its
    // cursor instead of requesting a fictional 5000 and silently truncating.
    var cursor: String?
    var conversations: [MaxV2Conversation] = []
    repeat {
      let suffix = cursor.map { "&cursor=\(encodedQueryValue($0))" } ?? ""
      let page: MaxV2CursorPage<MaxV2Conversation> = try await request(
        path: "/api/v2/conversations?limit=100\(suffix)"
      )
      conversations.append(contentsOf: page.items)
      cursor = page.items.isEmpty ? nil : page.nextCursor
    } while cursor != nil
    return MobileChatListResponse(
      success: true,
      chats: conversations.map(\.domainModel)
    )
  }

  func realtimeTicket() async throws -> MaxV2RealtimeTicket {
    try await request(path: "/api/v2/realtime/tickets", method: "POST")
  }

  func searchChatPeople(query: String) async throws -> MobileChatPeopleResponse {
    var components = URLComponents()
    components.queryItems = [URLQueryItem(name: "q", value: query)]
    let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
    return try await request(path: "/api/v2/conversations/people\(queryString)")
  }

  func createDirectChat(userID: String) async throws -> MobileChatCreateResponse {
    let conversation: MaxV2Conversation = try await request(
      path: "/api/v2/conversations/direct",
      method: "POST",
      body: DirectConversationRequest(userId: userID)
    )
    return MobileChatCreateResponse(
      success: true,
      operationId: nil,
      chat: conversation.domainModel
    )
  }

  func createGroupChat(
    name: String,
    memberIDs: [String]
  ) async throws -> MobileChatCreateResponse {
    let conversation: MaxV2Conversation = try await request(
      path: "/api/v2/conversations/groups",
      method: "POST",
      body: GroupConversationRequest(title: name, memberIds: memberIDs)
    )
    return MobileChatCreateResponse(
      success: true,
      operationId: nil,
      chat: conversation.domainModel
    )
  }

  func messages(
    chatID: String,
    limit: Int = 100,
    before: String? = nil
  ) async throws -> MobileMessagesResponse {
    // The server clamps to 100 and says nothing about it. Asking for more made
    // the client believe it had the whole thread and never paginate.
    let safeLimit = min(max(limit, 1), 100)
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "limit", value: String(safeLimit)),
      URLQueryItem(name: "before", value: before)
    ].filter { $0.value != nil }
    let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
    let page: MaxV2CursorPage<MaxV2Message> = try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages\(query)"
    )
    return MobileMessagesResponse(
      success: true,
      messages: page.items.map { $0.domainModel(conversationID: chatID) }
    )
  }

  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String? = nil
  ) async throws -> MobileMessageSendResponse {
    try await sendMessage(
      chatID: chatID,
      caption: caption,
      mediaFileIDs: mediaFileIDs,
      replyToID: replyToID,
      clientMessageID: UUID().uuidString.lowercased()
    )
  }

  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    clientMessageID: String
  ) async throws -> MobileMessageSendResponse {
    let message: MaxV2Message = try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages",
      method: "POST",
      body: SendMessageRequest(
        body: caption,
        attachmentIds: mediaFileIDs,
        replyToId: replyToID,
        clientMessageId: clientMessageID
      )
    )
    return MobileMessageSendResponse(
      success: true,
      operationId: nil,
      message: message.domainModel(conversationID: chatID)
    )
  }

  func saveHistory(fileID: String, position: Double) async throws -> EmptySuccess {
    try await requestNoContent(
      path: "/api/v2/media/\(encodedPathSegment(fileID))/history",
      method: "PUT",
      body: PlaybackHistoryRequest(positionSeconds: position, completed: false)
    )
  }

  func setFavorite(fileID: String, favorite: Bool) async throws -> EmptySuccess {
    try await requestNoContent(
      path: "/api/v2/media/\(encodedPathSegment(fileID))/favorite",
      method: "PUT",
      body: FavoriteRequest(favorite: favorite)
    )
  }

  func trashedMedia(cursor: String?) async throws -> TrashedMediaPage {
    var path = "/api/v2/media/trash"
    if let cursor, !cursor.isEmpty {
      path += "?cursor=\(encodedQueryValue(cursor))"
    }
    let page: MaxV2CursorPage<MaxV2Media> = try await request(path: path)
    return TrashedMediaPage(
      items: page.items.map(\.trashedModel),
      nextCursor: page.nextCursor
    )
  }

  func trashMedia(fileID: String) async throws -> EmptySuccess {
    try await requestNoContent(
      path: "/api/v2/media/\(encodedPathSegment(fileID))",
      method: "DELETE"
    )
    return EmptySuccess(success: true)
  }

  func restoreMedia(fileID: String) async throws -> EmptySuccess {
    try await requestNoContent(
      path: "/api/v2/media/\(encodedPathSegment(fileID))/restore",
      method: "POST"
    )
    return EmptySuccess(success: true)
  }

  func purgeMedia(fileID: String) async throws -> EmptySuccess {
    try await requestNoContent(
      path: "/api/v2/media/\(encodedPathSegment(fileID))/permanent",
      method: "DELETE"
    )
    return EmptySuccess(success: true)
  }

  func requestAccess(fileID: String, messageID: String?) async throws -> EmptySuccess {
    try await request(
      path: "/api/v2/access-requests",
      method: "POST",
      body: AccessRequestBody(fileId: fileID, messageId: messageID)
    )
  }

  func accessRequests() async throws -> MobileAccessRequestsResponse {
    try await request(path: "/api/v2/access-requests")
  }

  func decideAccessRequest(
    id: String,
    decision: String
  ) async throws -> MobileAccessDecisionResponse {
    try await request(
      path: "/api/v2/access-requests/\(encodedPathSegment(id))",
      method: "POST",
      body: AccessDecisionRequest(decision: decision)
    )
  }

  func uploadMultipart(
    fileURL: URL,
    mimeType: String,
    spaceID: String?,
    fileName: String? = nil,
    progress: @escaping @Sendable (TransferProgress) -> Void = { _ in }
  ) async throws -> MobileUploadRegisterResponse {
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize > 0 else {
      throw MaxAPIError.invalidResponse
    }
    let upload: MaxV2UploadSession = try await request(
      path: "/api/v2/uploads",
      method: "POST",
      body: UploadSessionRequest(
        fileName: fileName ?? fileURL.lastPathComponent,
        mimeType: mimeType,
        sizeBytes: fileSize,
        spaceId: spaceID
      ),
      headers: ["Idempotency-Key": UUID().uuidString.lowercased()]
    )
    guard !upload.provider.isEmpty,
          !upload.objectKey.isEmpty,
          !upload.uploadId.isEmpty,
          upload.partSizeBytes > 0,
          upload.partSizeBytes <= 32 * 1_024 * 1_024 else {
      throw MaxAPIError.invalidResponse
    }
    let requiredPartCount = Int(ceil(Double(fileSize) / Double(upload.partSizeBytes)))
    guard upload.parts.count >= requiredPartCount else { throw MaxAPIError.invalidResponse }

    let source = try FileHandle(forReadingFrom: fileURL)
    defer { try? source.close() }
    var completedParts: [CompleteUploadRequest.Part] = []
    var transferred: Int64 = 0
    for part in upload.parts.prefix(requiredPartCount) {
      guard part.partNumber > 0,
            Self.isLocalUploadURL(part.url) else {
        throw MaxAPIError.invalidURL
      }
      let offset = UInt64(part.partNumber - 1) * UInt64(upload.partSizeBytes)
      try source.seek(toOffset: offset)
      let remaining = max(fileSize - Int(offset), 0)
      let partLength = min(upload.partSizeBytes, remaining)
      let partData = try source.read(upToCount: partLength) ?? Data()
      guard partData.count == partLength else { throw MaxAPIError.invalidResponse }

      var partRequest = URLRequest(url: part.url)
      partRequest.httpMethod = "PUT"
      partRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
      let (partResponseData, partResponse) = try await session.upload(
        for: partRequest,
        from: partData
      )
      guard let http = partResponse as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let etag = http.value(forHTTPHeaderField: "ETag"),
            !etag.isEmpty else {
        _ = partResponseData
        throw MaxAPIError.server(
          status: (partResponse as? HTTPURLResponse)?.statusCode ?? 0,
          message: String(localized: "error.api.request_failed")
        )
      }
      completedParts.append(.init(partNumber: part.partNumber, etag: etag))
      transferred += Int64(partLength)
      progress(.init(bytesTransferred: transferred, totalBytes: Int64(fileSize)))
    }

    let completed: MaxV2Media = try await request(
      path: "/api/v2/uploads/\(encodedPathSegment(upload.id))/complete",
      method: "POST",
      body: CompleteUploadRequest(parts: completedParts)
    )
    return MobileUploadRegisterResponse(
      success: true,
      fileId: completed.id,
      filePath: completed.mediaUrl?.absoluteString,
      fileType: completed.kind,
      sizeBytes: completed.sizeBytes,
      operationId: upload.id
    )
  }

  func searchMessages(
    chatID: String,
    query: String,
    limit: Int = 50
  ) async throws -> MobileMessagesResponse {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))
    ]
    let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
    return try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/search\(queryString)"
    )
  }

  func pinnedMessages(chatID: String) async throws -> MobileMessagesResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/pinned"
    )
  }

  func editMessage(
    chatID: String,
    messageID: String,
    content: String
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages/"
        + encodedPathSegment(messageID),
      method: "PUT",
      body: EditMessageRequest(content: content)
    )
  }

  func deleteMessage(
    chatID: String,
    messageID: String
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages/"
        + encodedPathSegment(messageID),
      method: "DELETE"
    )
  }

  func setMessagePinned(
    chatID: String,
    messageID: String,
    isPinned: Bool
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages/"
        + encodedPathSegment(messageID) + "/pin",
      method: isPinned ? "POST" : "DELETE"
    )
  }

  func setMessageReaction(
    chatID: String,
    messageID: String,
    reactionKey: String?
  ) async throws -> MobileChatReactionMutationResponse {
    let path = "/api/v2/conversations/\(encodedPathSegment(chatID))/messages/"
      + encodedPathSegment(messageID) + "/reaction"
    if let reactionKey {
      return try await request(
        path: path,
        method: "POST",
        body: ChatReactionRequest(reactionKey: reactionKey)
      )
    }
    return try await request(path: path, method: "DELETE")
  }

  func chatPreference(chatID: String) async throws -> MobileChatPreferenceResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/preference"
    )
  }

  func updateChatPreference(
    chatID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String?
  ) async throws -> MobileChatPreferenceMutationResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/preference",
      method: "PUT",
      body: ChatPreferenceRequest(
        isMuted: isMuted,
        isArchived: isArchived,
        mutedUntil: mutedUntil
      )
    )
  }

  func chatMembers(chatID: String) async throws -> MobileChatMembersResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/members"
    )
  }

  func createChatPoll(
    chatID: String,
    question: String,
    options: [String],
    allowMultipleVotes: Bool
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/polls",
      method: "POST",
      body: ChatPollRequest(
        question: question,
        options: options,
        allowMultipleVotes: allowMultipleVotes
      )
    )
  }

  func setChatPollVote(
    chatID: String,
    pollID: String,
    optionID: String,
    selected: Bool
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/polls/"
        + encodedPathSegment(pollID) + "/votes/" + encodedPathSegment(optionID),
      method: selected ? "POST" : "DELETE"
    )
  }

  func forwardMessage(
    chatID: String,
    messageID: String,
    targetChatID: String
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages/"
        + encodedPathSegment(messageID) + "/forward",
      method: "POST",
      body: ForwardMessageRequest(targetChatId: targetChatID)
    )
  }

  func markChatRead(chatID: String) async throws -> EmptySuccess {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/read",
      method: "POST",
      body: EmptyRequest()
    )
  }

  func chatActivity(limit: Int = 50) async throws -> MobileChatActivityResponse {
    let safeLimit = min(max(limit, 1), 100)
    return try await request(path: "/api/v2/conversations/activity?limit=\(safeLimit)")
  }

  func markChatActivityRead(activityIDs: [String]) async throws -> MobileChatActivityReadResponse {
    try await request(
      path: "/api/v2/conversations/activity",
      method: "POST",
      body: ChatActivityReadRequest(activityIds: activityIDs)
    )
  }

  func sendMessageV3(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?,
    mentionUserIDs: [String]
  ) async throws -> MobileMessageSendResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/messages",
      method: "POST",
      body: SendMessageV3Request(
        content: caption,
        mediaFileIds: mediaFileIDs,
        replyToId: replyToID,
        mentionUserIds: mentionUserIDs
      )
    )
  }

  func updateChatGroup(
    chatID: String,
    name: String?,
    avatar: String?
  ) async throws -> MobileChatGroupMutationResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))",
      method: "PUT",
      body: ChatGroupPatchRequest(groupName: name, groupAvatar: avatar)
    )
  }

  func addChatMember(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/members",
      method: "POST",
      body: ChatMemberAddRequest(userId: userID, role: role)
    )
  }

  func updateChatMemberRole(
    chatID: String,
    userID: String,
    role: String
  ) async throws -> MobileChatMemberMutationResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/members/"
        + encodedPathSegment(userID),
      method: "PUT",
      body: ChatMemberRoleRequest(role: role)
    )
  }

  func removeChatMember(chatID: String, userID: String) async throws -> MobileChatMemberMutationResponse {
    try await request(
      path: "/api/v2/conversations/\(encodedPathSegment(chatID))/members/"
        + encodedPathSegment(userID),
      method: "DELETE"
    )
  }

  func ratings(fileID: String) async throws -> MobileRatingsResponse {
    try await request(
      path: "/api/v2/media/\(encodedPathSegment(fileID))/ratings"
    )
  }

  func ratedMedia() async throws -> MobileRatedMediaResponse {
    let media = try await allMedia()
    var items: [RatedMediaEntry] = []
    for item in media {
      let subjects = try await ratings(fileID: item.id).subjects
      guard subjects.contains(where: { $0.score != nil }) else { continue }
      items.append(RatedMediaEntry(media: item.domainModel, subjects: subjects))
    }
    return MobileRatedMediaResponse(success: true, items: items)
  }

  func setRating(
    fileID: String,
    targetUserID: String,
    score: Int
  ) async throws -> MobileRatingMutationResponse {
    let path = "/api/v2/media/\(encodedPathSegment(fileID))/rating"
    if score == 0 {
      _ = try await requestNoContent(
        path: path,
        method: "DELETE",
        body: RatingTargetRequest(targetUserId: targetUserID)
      )
    } else {
      _ = try await requestNoContent(
        path: path,
        method: "PUT",
        body: RatingRequest(
          score: min(max(score, 1), 10),
          targetUserId: targetUserID
        )
      )
    }
    return MobileRatingMutationResponse(
      success: true,
      subjectUserId: targetUserID,
      score: score == 0 ? nil : min(max(score, 1), 10),
      cleared: score == 0,
      operationId: nil
    )
  }

  func downloadFile(
    from remoteURL: URL,
    progress: @escaping @Sendable (TransferProgress) -> Void = { _ in }
  ) async throws -> DownloadedTemporaryFile {
    guard MaxConfiguration.isValidRemoteMediaURL(remoteURL) else {
      throw MaxAPIError.invalidURL
    }

    let downloadURL = Self.downloadURL(for: remoteURL, relativeTo: configuration.baseURL)
    var request = URLRequest(url: downloadURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 120
    request.setValue("application/octet-stream, */*", forHTTPHeaderField: "Accept")
    if isSameOrigin(downloadURL, configuration.baseURL),
       let token = try tokenStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
       !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let result = try await URLSessionTransferSupport.download(
      session: session,
      request: request,
      progress: progress
    )
    guard (200..<300).contains(result.statusCode) else {
      let data = Self.readPrefix(from: result.url, maximumBytes: 4_096)
      try? FileManager.default.removeItem(at: result.url)
      let message = Self.safeServerMessage(
        from: data,
        fallback: String(localized: "error.api.download_failed")
      )
      if result.statusCode == 401 || result.statusCode == 403 {
        throw MaxAPIError.unauthorized(status: result.statusCode, message: message)
      }
      throw MaxAPIError.server(status: result.statusCode, message: message)
    }
    return result
  }

  private static func downloadURL(for remoteURL: URL, relativeTo baseURL: URL) -> URL {
    guard remoteURL.host?.lowercased() == baseURL.host?.lowercased(),
          remoteURL.path.hasPrefix("/api/media/") else { return remoteURL }
    var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.removeAll { $0.name == "download" }
    queryItems.append(URLQueryItem(name: "download", value: "1"))
    components?.queryItems = queryItems
    return components?.url ?? remoteURL
  }

  func preflightMediaStream(url: URL) async throws {
    guard MaxConfiguration.isValidRemoteMediaURL(url) else {
      throw MaxAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
    request.setValue("video/*, audio/*, image/*;q=0.8, */*;q=0.1", forHTTPHeaderField: "Accept")
    request.setValue(
      configuration.baseURL.absoluteString,
      forHTTPHeaderField: "X-Max-Public-Origin"
    )
    // No Authorization header. The point of this request is to prove that the
    // exact request AVFoundation is about to issue will succeed, and
    // AVURLAsset(url:) sends no headers at all. Authenticating here validated a
    // different request than the one that actually plays, so the preflight could
    // pass while playback failed. The storage route authenticates through the
    // presigned query string, not a bearer token.

    do {
      let (data, response) = try await session.data(for: request)
      try validate(response: response, data: data)
      guard let http = response as? HTTPURLResponse,
            http.statusCode == 200 || http.statusCode == 206 else {
        throw MaxAPIError.invalidResponse
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Every failure propagates. Swallowing all but 401/403 discarded the only
      // diagnostic that existed: a 404 for an object that was never uploaded, or
      // an expired signature, was logged and ignored, so the player always
      // reported AVFoundation's generic "not playable" and Retry re-ran the
      // identical failing request forever.
      let diagnostic = error as NSError
      print("Preflight check failed (\(diagnostic.domain):\(diagnostic.code))")
      throw error
    }
  }

  private static func bootstrapResponse(_ response: MaxV2Bootstrap) -> MobileBootstrapResponse {
    let features = response.capabilities.features
    return MobileBootstrapResponse(
      success: true,
      user: response.user.domainModel,
      preferences: MobilePreferences(
        synced: .init(
          homeMode: "browse",
          filters: [:],
          libraryLayout: "grid",
          lastWorkspaceId: nil,
          lastCollectionId: nil,
          playerDefaults: ["autoplay": .bool(response.settings.autoplay)],
          dismissedTips: []
        ),
        localOnly: ["locale": response.settings.locale]
      ),
      capabilities: .init(
        rootTabs: ["home", "vault", "shared", "chats", "profile"],
        pushNotifications: features["notifications"] ?? false,
        voiceCalls: false,
        videoCalls: false,
        watchParties: false,
        manualDownloads: true,
        mediaReferenceMessages: features["messageAttachments"] ?? true,
        requestAccess: features["accessRequests"] ?? false,
        ratingScale: .init(min: 1, max: 5, clearValue: 0)
      )
    )
  }

  private static func profileResponse(
    user: MaxUser,
    media: [MaxMediaItem],
    spaces: [MaxV2Space]
  ) -> MobileProfileResponse {
    let viewed = media.filter { $0.lastPosition > 0 }
    return MobileProfileResponse(
      success: true,
      user: user,
      stats: .init(
        ratedFiles: media.filter { $0.rating != nil }.count,
        totalViewed: viewed.count,
        totalWatchSeconds: Int(viewed.reduce(0) { $0 + $1.lastPosition })
      ),
      storage: .init(
        usedBytes: media.reduce(0) { $0 + $1.sizeBytes },
        fileCount: media.count
      ),
      workspaces: spaces.map {
        WorkspaceSummary(
          id: $0.id,
          name: $0.name,
          ownerId: nil,
          coverUrl: nil,
          description: nil,
          spaceType: "space",
          itemCount: nil
        )
      },
      favorites: media.filter(\.isFavorite),
      personal: .init(
        stickyNotes: [],
        fileFavoritePins: [],
        // Built from the media list, which already carries the caller's own
        // score per item. Hardcoding an empty array here is why the profile's
        // Ratings shelf read "No ratings yet" for a user who had rated plenty.
        personalRatings: media
          .filter { $0.rating != nil }
          .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
          .map {
            ProfileRating(
              fileId: $0.id,
              name: $0.title,
              score: $0.rating.map { Double($0) },
              createdAt: $0.uploadedAt
            )
          },
        catalogFavorites: [],
        catalogRatings: [],
        showcaseCards: []
      )
    )
  }

  private func request<Response: Decodable>(
    path: String,
    method: String = "GET"
  ) async throws -> Response {
    let request = try makeRequest(path: path, method: method)
    let data = try await execute(request)
    return try decoder.decode(Response.self, from: data)
  }

  private func request<Response: Decodable, Body: Encodable>(
    path: String,
    method: String,
    body: Body,
    headers: [String: String] = [:]
  ) async throws -> Response {
    var request = try makeRequest(path: path, method: method)
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (field, value) in headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    let data = try await execute(request)
    return try decoder.decode(Response.self, from: data)
  }

  private func requestNoContent(path: String, method: String) async throws {
    let request = try makeRequest(path: path, method: method)
    _ = try await execute(request)
  }

  private func requestNoContent<Body: Encodable>(
    path: String,
    method: String,
    body: Body
  ) async throws -> EmptySuccess {
    var request = try makeRequest(path: path, method: method)
    request.httpBody = try encoder.encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    _ = try await execute(request)
    return EmptySuccess(success: true)
  }

  private func execute(_ request: URLRequest, allowRefresh: Bool = true) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    if allowRefresh,
       (response as? HTTPURLResponse)?.statusCode == 401,
       let refreshToken = try tokenStore.loadRefreshToken(),
       !refreshToken.isEmpty {
      let credentials = try await refreshCredentials(refreshToken: refreshToken)
      var retry = request
      retry.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
      let (retryData, retryResponse) = try await session.data(for: retry)
      try validate(response: retryResponse, data: retryData)
      return retryData
    }
    try validate(response: response, data: data)
    return data
  }

  /// Refresh tokens are strictly single-use and the server treats a replay as a
  /// breach, revoking the whole token family. Actors are re-entrant across
  /// `await`, so the launch fan-out produced N simultaneous 401s, N refreshes
  /// with the same stale token, and a forced logout. Everyone now waits on one
  /// in-flight refresh.
  private func refreshCredentials(refreshToken: String) async throws -> SessionCredentials {
    if let inFlight = refreshTask {
      return try await inFlight.value
    }
    let task = Task<SessionCredentials, Error> { [self] in
      try await performRefresh(refreshToken: refreshToken)
    }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  private func performRefresh(refreshToken: String) async throws -> SessionCredentials {
    var request = try makeRequest(path: "/api/v2/auth/refresh", method: "POST")
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
    let (data, response) = try await session.data(for: request)
    do {
      try validate(response: response, data: data)
    } catch {
      // A rejected refresh token is poisoned for good. Keeping it would replay
      // the same family revocation on the next launch.
      if error.isAuthenticationFailure { try? tokenStore.clearToken() }
      throw error
    }
    let sessionResponse = try decoder.decode(MaxV2Session.self, from: data)
    let credentials = SessionCredentials(
      accessToken: sessionResponse.accessToken,
      refreshToken: sessionResponse.refreshToken
    )
    try tokenStore.saveCredentials(credentials)
    return credentials
  }

  private func makeRequest(path: String, method: String) throws -> URLRequest {
    guard path.hasPrefix("/"),
          !path.hasPrefix("//"),
          let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL,
          MaxConfiguration.isValidRemoteMediaURL(url),
          isSameOrigin(url, configuration.baseURL) else {
      throw MaxAPIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 45
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    // Reverse proxies such as quick Cloudflare tunnels may present their
    // upstream localhost origin to Next.js. The server uses this validated
    // hint only when building URLs returned to this client.
    request.setValue(
      configuration.baseURL.absoluteString,
      forHTTPHeaderField: "X-Max-Public-Origin"
    )
    if let token = try tokenStore.loadToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
       !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw MaxAPIError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let message = Self.safeServerMessage(
        from: data,
        fallback: String(localized: "error.api.request_failed")
      )
      if http.statusCode == 401 || http.statusCode == 403 {
        throw MaxAPIError.unauthorized(status: http.statusCode, message: message)
      }
      throw MaxAPIError.server(status: http.statusCode, message: message)
    }
  }

  private func encodedPathSegment(_ value: String) -> String {
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
    return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
  }

  private func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
      && lhs.host?.lowercased() == rhs.host?.lowercased()
      && effectivePort(for: lhs) == effectivePort(for: rhs)
  }

  private func effectivePort(for url: URL) -> Int? {
    if let port = url.port { return port }
    switch url.scheme?.lowercased() {
    case "https", "wss": return 443
    case "http", "ws": return 80
    default: return nil
    }
  }

  /// Internal rather than private so the ChatsV3 transport can share it instead
  /// of keeping a second, weaker parser that showed users raw JSON.
  static func safeServerMessage(from data: Data, fallback: String) -> String {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let error = object["error"] as? [String: Any],
         let message = error["message"] as? String,
         !message.isEmpty {
        return message
      }
      for key in ["message", "error", "detail"] {
        if let value = object[key] as? String, !value.isEmpty {
          return value
        }
      }
    }
    let text = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty || text.count > 240 ? fallback : text
  }

  private static func imageMIMEType(for fileURL: URL) -> String {
    switch fileURL.pathExtension.lowercased() {
    case "png": "image/png"
    case "heic", "heif": "image/heic"
    case "webp": "image/webp"
    default: "image/jpeg"
    }
  }

  private static func profileImageURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
    if let absolute = URL(string: rawValue),
       let scheme = absolute.scheme?.lowercased(),
       scheme == "https" || scheme == "http" {
      return absolute
    }
    guard rawValue.hasPrefix("/"), !rawValue.hasPrefix("//") else { return nil }
    return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
  }

  private static func isLocalUploadURL(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "http" || scheme == "https"
  }

  private static func readPrefix(from url: URL, maximumBytes: Int) -> Data {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
    defer { try? handle.close() }
    return (try? handle.read(upToCount: maximumBytes)) ?? Data()
  }

  /// The API deliberately caps an individual page at 100 items. Follow its
  /// cursor here for summary screens, which otherwise silently stopped at the
  /// first page when they requested an oversized limit.
  private func allMedia() async throws -> [MaxV2Media] {
    var cursor: String?
    var all: [MaxV2Media] = []
    repeat {
      let suffix = cursor.map { "&cursor=\(encodedQueryValue($0))" } ?? ""
      let page: MaxV2CursorPage<MaxV2Media> = try await request(
        path: "/api/v2/media?limit=100\(suffix)"
      )
      all.append(contentsOf: page.items)
      cursor = page.nextCursor
    } while cursor != nil
    return all
  }

  private func encodedQueryValue(_ value: String) -> String {
    var components = URLComponents()
    components.queryItems = [URLQueryItem(name: "cursor", value: value)]
    return components.percentEncodedQuery?
      .replacingOccurrences(of: "cursor=", with: "") ?? value
  }
}

private struct LoginRequest: Encodable {
  let identity: String
  let password: String
  let deviceName: String
  let platform: String
  let appVersion: String?
}

private struct RefreshRequest: Encodable { let refreshToken: String }

private struct UploadSessionRequest: Encodable {
  let fileName: String
  let mimeType: String
  let sizeBytes: Int
  let spaceId: String?
}

private struct CompleteUploadRequest: Encodable {
  struct Part: Encodable {
    let partNumber: Int
    let etag: String
  }

  let parts: [Part]
}

private struct SendMessageRequest: Encodable {
  let body: String
  let attachmentIds: [String]
  let replyToId: String?
  let clientMessageId: String
}
private struct SendMessageV3Request: Encodable {
  let content: String
  let mediaFileIds: [String]
  let replyToId: String?
  let mentionUserIds: [String]
}
private struct ChatActivityReadRequest: Encodable { let activityIds: [String] }
private struct ChatGroupPatchRequest: Encodable {
  let groupName: String?
  let groupAvatar: String?
}
private struct ChatMemberAddRequest: Encodable {
  let userId: String
  let role: String
}
private struct ChatMemberRoleRequest: Encodable { let role: String }

private struct LiveProfileUpdateRequest: Encodable {
  let displayName: String?
  let username: String?
  let bio: String?
}

private struct ProfileMediaPatch: Encodable {
  let avatarMediaId: String?
  let coverMediaId: String?

  private enum CodingKeys: String, CodingKey {
    case avatarMediaId
    case coverMediaId
  }

  // Omit the untouched property rather than encoding it as null: the API uses
  // null as an explicit request to clear that profile image.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if let avatarMediaId {
      try container.encode(avatarMediaId, forKey: .avatarMediaId)
    }
    if let coverMediaId {
      try container.encode(coverMediaId, forKey: .coverMediaId)
    }
  }
}

private struct EditMessageRequest: Encodable { let content: String }
private struct ForwardMessageRequest: Encodable { let targetChatId: String }
private struct ChatReactionRequest: Encodable { let reactionKey: String }
private struct ChatPreferenceRequest: Encodable {
  let isMuted: Bool
  let isArchived: Bool
  let mutedUntil: String?
}
private struct ChatPollRequest: Encodable {
  let question: String
  let options: [String]
  let allowMultipleVotes: Bool
}
private struct DirectConversationRequest: Encodable { let userId: String }
private struct GroupConversationRequest: Encodable { let title: String; let memberIds: [String] }
private struct RatingRequest: Encodable {
  let score: Int
  let targetUserId: String
}
private struct RatingTargetRequest: Encodable { let targetUserId: String }
private struct CollectionItemRequest: Encodable { let fileId: String }
private struct PlaybackHistoryRequest: Encodable {
  let positionSeconds: Double
  let completed: Bool
}
private struct FavoriteRequest: Encodable { let favorite: Bool }
private struct AccessRequestBody: Encodable { let fileId: String; let messageId: String? }
private struct AccessDecisionRequest: Encodable { let decision: String }
private struct EmptyRequest: Encodable {}

enum MaxAPIError: Error, LocalizedError, Sendable {
  case invalidURL
  case invalidResponse
  case invalidProfileImage
  case unauthorized(status: Int, message: String)
  case server(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return String(localized: "error.api.invalid_url")
    case .invalidResponse:
      return String(localized: "error.api.invalid_response")
    case .invalidProfileImage:
      return String(localized: "error.profile.image_invalid")
    case .unauthorized(_, let message), .server(_, let message):
      return message
    }
  }

  var isAuthenticationFailure: Bool {
    if case .unauthorized = self { return true }
    return false
  }
}

extension Error {
  var isAuthenticationFailure: Bool {
    (self as? MaxAPIError)?.isAuthenticationFailure ?? false
  }
}

private enum MultipartFormFile {
  static func build(
    boundary: String,
    fileURL: URL,
    mimeType: String,
    fileName: String?,
    fields: [String: String]
  ) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("max-multipart-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let output = try FileHandle(forWritingTo: url)
    defer { try? output.close() }

    for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
      try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
      let disposition = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
      try output.write(contentsOf: Data(disposition.utf8))
      try output.write(contentsOf: Data("\(value)\r\n".utf8))
    }

    let safeFileName = headerValue(fileName ?? fileURL.lastPathComponent, fallback: "upload")
    let safeMIMEType = headerValue(mimeType, fallback: "application/octet-stream")
    try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
    let disposition = "Content-Disposition: form-data; name=\"file\"; "
      + "filename=\"\(safeFileName)\"\r\n"
    try output.write(contentsOf: Data(disposition.utf8))
    try output.write(contentsOf: Data("Content-Type: \(safeMIMEType)\r\n\r\n".utf8))

    let input = try FileHandle(forReadingFrom: fileURL)
    defer { try? input.close() }
    while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
      try output.write(contentsOf: chunk)
    }

    try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    return url
  }

  private static func headerValue(_ value: String, fallback: String) -> String {
    let sanitized = value
      .replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: "\"", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? fallback : sanitized
  }
}
