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
  /// Another user's public identity (GET /api/v2/profiles/{id}).
  func peerProfile(userID: String) async throws -> MaxV2Profile
  func peerProfileStats(userID: String) async throws -> MaxV2PeerStats
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
  /// Sets or clears (nil) the conversation's disappearing-messages timer.
  func setChatTTL(chatID: String, ttlSeconds: Int?) async throws -> EmptySuccess
  /// Attaches the sender's on-device transcription to a voice-note attachment.
  func setVoiceTranscript(
    chatID: String,
    messageID: String,
    mediaID: String,
    transcript: String
  ) async throws -> EmptySuccess

  /// Every clip the caller has saved, newest first (the Clips shelf).
  func allClips() async throws -> [MediaClip]
  /// The caller's clips of one media item.
  func mediaClips(mediaID: String) async throws -> [MediaClip]
  func createClip(
    mediaID: String,
    title: String,
    startSeconds: Double,
    endSeconds: Double
  ) async throws -> MediaClip
  func deleteClip(clipID: String) async throws -> EmptySuccess
  func mediaMarkers(mediaID: String) async throws -> [MediaMarker]
  func createMarker(
    mediaID: String,
    atSeconds: Double,
    label: String
  ) async throws -> MediaMarker
  func deleteMarker(markerID: String) async throws -> EmptySuccess
  /// One media item by id (GET /api/v2/media/{id}) — resolves a clip whose
  /// media is not in any loaded catalog.
  func mediaItem(id: String) async throws -> MaxMediaItem

  /// The caller's self-conversation ("Saved Messages"), created on first use.
  func savedMessages() async throws -> MobileChatCreateResponse
  /// Writes a promise the server keeps: the body sends itself at `sendAt`
  /// (RFC3339, more than 20 seconds in the future).
  func scheduleMessage(
    chatID: String,
    body: String,
    clientMessageID: String,
    sendAt: String
  ) async throws -> ScheduledMessage
  /// The caller's pending scheduled messages for one conversation.
  func scheduledMessages(chatID: String) async throws -> [ScheduledMessage]
  func cancelScheduledMessage(id: String) async throws -> EmptySuccess

  /// Fire-and-forget re-watch sample: one bin (0...99) per ~6 s of playback.
  /// Never throws — a lost sample must never disturb playback.
  func sampleHeatmap(mediaID: String, bin: Int) async
  /// 100 normalised re-watch bins (0...1) for the scrubber's heat lane.
  func heatmap(mediaID: String) async throws -> [Double]
  /// Queues a server-side export of a clip ("mp4" or "gif"). When
  /// `sendToConversationId` is set, the worker posts the finished render into
  /// that chat automatically.
  func exportClip(
    clipID: String,
    format: String,
    sendToConversationId: String?
  ) async throws -> EmptySuccess

  /// Cross-device draft sync: stores the half-typed message on the
  /// conversation so every signed-in device offers to resume it.
  func updateChatDraft(chatID: String, text: String) async throws -> EmptySuccess

  /// Mints a shareable join link for a group conversation.
  func createGroupInvite(
    chatID: String,
    expiresInSeconds: Int,
    maxUses: Int?
  ) async throws -> MaxGroupInvite
  /// The group's existing invite links, each row carrying its full join URL.
  func groupInvites(chatID: String) async throws -> [MaxGroupInvite]
  func revokeGroupInvite(id: String) async throws -> EmptySuccess
  /// What an invite token opens onto, shown before joining.
  func invitePreview(token: String) async throws -> MaxInvitePreview
  /// Joins the conversation behind the token; the response names the
  /// conversation to open.
  func acceptInvite(token: String) async throws -> MaxInviteAcceptResponse

  /// Everyone with access to a shared collection, owner included.
  func collectionMembers(collectionID: String) async throws -> [MaxCollectionMember]
  func addCollectionMember(
    collectionID: String,
    userID: String,
    role: String
  ) async throws -> EmptySuccess
  func removeCollectionMember(
    collectionID: String,
    userID: String
  ) async throws -> EmptySuccess
  /// Removes one media item from a collection (the item itself is untouched).
  func removeCollectionMedia(
    collectionID: String,
    mediaID: String
  ) async throws -> EmptySuccess

  /// Up to three videos left partway through, newest first.
  func continueWatching() async throws -> [MaxContinueItem]
  /// The caller's private year-in-review aggregates.
  func wrapped() async throws -> MaxWrapped

  /// The caller's saved chat stickers, favorites first (server-ordered).
  func stickers() async throws -> [MaxSticker]
  /// Uploads one image (already downscaled to ≤512 px client-side) as a sticker.
  func createSticker(
    imageData: Data,
    mimeType: String,
    emoji: String?
  ) async throws -> MaxSticker
  func deleteSticker(id: String) async throws -> EmptySuccess
  func favoriteSticker(id: String, favorite: Bool) async throws -> EmptySuccess
  /// Sends a saved sticker into a conversation. The resulting message is
  /// body-less with one attachment whose kind == "sticker".
  func sendSticker(
    chatID: String,
    stickerID: String,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse

  /// Mints a public, expiring share link for one media item.
  func createShareLink(
    mediaID: String,
    expiresInSeconds: Int,
    maxViews: Int?
  ) async throws -> MaxShareLink
  /// The item's existing share links, each row carrying its full url.
  func shareLinks(mediaID: String) async throws -> [MaxShareLink]
  func revokeShareLink(id: String) async throws -> EmptySuccess

  /// Story rails for the chat inbox: mine first, unseen posters next.
  func stories() async throws -> [MaxStoryRail]
  /// Posts one of the caller's own images or videos as a 24-hour story.
  func postStory(mediaID: String, caption: String) async throws -> MaxStory
  /// Marks one story seen by the caller.
  func viewStory(id: String) async throws -> EmptySuccess
  /// Removes one of the caller's own stories.
  func deleteStory(id: String) async throws -> EmptySuccess
  /// Copies a sticker someone sent in a shared chat into the caller's tray.
  func adoptSticker(mediaID: String) async throws -> MaxSticker
  /// The caller's most re-watched media, ranked by heatmap volume.
  func rewatched() async throws -> [MaxRewatchedItem]

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

  // MARK: Watch Together (docs/design/WATCH_TOGETHER_SPEC.md §8)

  /// Opens a room on a conversation (`POST /watch/rooms`) → 201 room doc.
  /// `resumeFromRoomID` copies media/source/final_position from an ended room
  /// of the same conversation. 409 when a room already exists or the media is
  /// not visible to every member.
  func createWatchRoom(
    conversationID: String,
    mediaID: String?,
    source: WatchSource?,
    title: String?,
    emoji: String?,
    settings: WatchSettingsPatch?,
    resumeFromRoomID: String?
  ) async throws -> WatchRoom
  /// The full room doc (`GET /watch/rooms/{roomID}`): row + active
  /// participants + queue + settings + live state + activeVote — the
  /// reconnect resync source.
  func watchRoom(roomID: String) async throws -> WatchRoom
  /// The conversation's active room (`GET /watch/rooms?conversationId=`), or
  /// a 404 error when none is live.
  func activeWatchRoom(conversationID: String) async throws -> WatchRoom
  /// Joins (`POST .../join`) → room doc. 403 media-not-visible, 409 when the
  /// room is full, ended, or mid-roll join is off while playing.
  func joinWatchRoom(roomID: String) async throws -> WatchRoom
  /// Soft-exits (`POST .../leave`); the server handles host handoff inline.
  func leaveWatchRoom(roomID: String) async throws -> EmptySuccess
  /// One sync/relay signal (`POST .../signal` with `{type, payload}`, spec §6).
  /// State-mutating signals answer `{version}` for echo suppression. Rate
  /// limit: 20 signals / 5s / (user, room) → 429.
  func sendWatchSignal(
    roomID: String,
    type: String,
    payload: JSONValue
  ) async throws -> WatchSignalResponse
  /// Fast resync from the Redis hash only (`GET .../state`); 409 when the
  /// room has ended.
  func watchRoomState(roomID: String) async throws -> WatchCanonicalState
  /// Host-only settings merge (`PATCH .../settings`, spec §4). The complete
  /// merged object arrives back via `watch.settings.updated`.
  func updateWatchSettings(
    roomID: String,
    patch: WatchSettingsPatch
  ) async throws -> EmptySuccess
  /// Host-only title/emoji change (`PATCH /watch/rooms/{roomID}`) →
  /// `watch.meta.updated`.
  func updateWatchRoomMeta(
    roomID: String,
    title: String?,
    emoji: String?
  ) async throws -> EmptySuccess
  /// Controller-only full queue replace (`PUT .../queue` with `{mediaIds}`).
  func replaceWatchQueue(roomID: String, mediaIDs: [String]) async throws -> EmptySuccess
  /// Appends one item (`POST .../queue/items`); any participant when
  /// `queueCollaborative`, controllers otherwise.
  func addWatchQueueItem(roomID: String, mediaID: String) async throws -> EmptySuccess
  /// Removes by index (`DELETE .../queue/items/{index}`); controller, or the
  /// adder removing their own.
  func removeWatchQueueItem(roomID: String, index: Int) async throws -> EmptySuccess
  /// Host-only promote/demote (`POST .../participants/{userID}/role`,
  /// role is `"controller"` or `"viewer"` — never `"host"` here).
  func setWatchParticipantRole(
    roomID: String,
    userID: String,
    role: String
  ) async throws -> EmptySuccess
  /// Host-only soft kick (`POST .../kick`); the user may re-join.
  func kickWatchParticipant(roomID: String, userID: String) async throws -> EmptySuccess
  /// Host-only host transfer (`POST .../host`); the target must be active.
  func transferWatchHost(roomID: String, userID: String) async throws -> EmptySuccess
  /// Host-only end (`DELETE /watch/rooms/{roomID}`) — finalizes stats and the
  /// resume position, then publishes `watch.room.ended`.
  func endWatchRoom(roomID: String) async throws -> EmptySuccess
  /// Ended rooms newest-first (`GET /watch/history?conversationId=&limit=`).
  func watchHistory(conversationID: String, limit: Int) async throws -> [WatchHistoryEntry]
  /// Host-only guest link mint (`POST .../guest-links`) → `{id, token, url}`.
  func createWatchGuestLink(
    roomID: String,
    expiresInHours: Int?,
    maxUses: Int?
  ) async throws -> WatchGuestLink
  /// Host-only guest link listing (`GET .../guest-links`).
  func watchGuestLinks(roomID: String) async throws -> [WatchGuestLink]
  /// Revokes one guest link (`DELETE /watch/guest-links/{linkID}`).
  func revokeWatchGuestLink(linkID: String) async throws -> EmptySuccess
  /// Schedules a watch party (`POST /watch/scheduled`); `scheduledAt` is
  /// RFC3339 and must be in the future. Any member may schedule.
  func createWatchScheduled(
    conversationID: String,
    scheduledAt: String,
    title: String?,
    emoji: String?,
    mediaID: String?,
    source: WatchSource?
  ) async throws -> WatchScheduledEntry
  /// Upcoming, not-canceled entries (`GET /watch/scheduled?conversationId=`).
  func watchScheduled(conversationID: String) async throws -> [WatchScheduledEntry]
  /// Cancels one entry (`DELETE /watch/scheduled/{id}`); creator or
  /// conversation moderator.
  func deleteWatchScheduled(id: String) async throws -> EmptySuccess
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
  func setChatTTL(chatID: String, ttlSeconds: Int?) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func setVoiceTranscript(
    chatID: String,
    messageID: String,
    mediaID: String,
    transcript: String
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  // Clips & markers defaults keep minimal conformers (e.g. test doubles)
  // compiling; both the live client and Demo Mode implement the real thing.
  func allClips() async throws -> [MediaClip] { [] }
  func mediaClips(mediaID: String) async throws -> [MediaClip] { [] }
  func createClip(
    mediaID: String,
    title: String,
    startSeconds: Double,
    endSeconds: Double
  ) async throws -> MediaClip {
    throw URLError(.unsupportedURL)
  }
  func deleteClip(clipID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func mediaMarkers(mediaID: String) async throws -> [MediaMarker] { [] }
  func createMarker(
    mediaID: String,
    atSeconds: Double,
    label: String
  ) async throws -> MediaMarker {
    throw URLError(.unsupportedURL)
  }
  func deleteMarker(markerID: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func mediaItem(id: String) async throws -> MaxMediaItem {
    throw URLError(.unsupportedURL)
  }

  // Saved Messages, scheduling, heatmap and export defaults keep minimal
  // conformers (e.g. test doubles) compiling; the live client and Demo Mode
  // implement the real thing.
  func savedMessages() async throws -> MobileChatCreateResponse {
    throw URLError(.unsupportedURL)
  }
  func scheduleMessage(
    chatID: String,
    body: String,
    clientMessageID: String,
    sendAt: String
  ) async throws -> ScheduledMessage {
    throw URLError(.unsupportedURL)
  }
  func scheduledMessages(chatID: String) async throws -> [ScheduledMessage] { [] }
  func cancelScheduledMessage(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func sampleHeatmap(mediaID: String, bin: Int) async {}
  func heatmap(mediaID: String) async throws -> [Double] { [] }
  func exportClip(
    clipID: String,
    format: String,
    sendToConversationId: String?
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  /// Convenience for the plain export, which never targets a chat.
  func exportClip(clipID: String, format: String) async throws -> EmptySuccess {
    try await exportClip(clipID: clipID, format: format, sendToConversationId: nil)
  }

  // Draft-sync, invite, collection-member, continue and wrapped defaults keep
  // minimal conformers (e.g. test doubles) compiling; the live client and Demo
  // Mode implement the real thing.
  func updateChatDraft(chatID: String, text: String) async throws -> EmptySuccess {
    // Best-effort by contract: a device that cannot sync drafts still chats.
    EmptySuccess(success: true)
  }
  func createGroupInvite(
    chatID: String,
    expiresInSeconds: Int,
    maxUses: Int?
  ) async throws -> MaxGroupInvite {
    throw URLError(.unsupportedURL)
  }
  func groupInvites(chatID: String) async throws -> [MaxGroupInvite] { [] }
  func revokeGroupInvite(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func invitePreview(token: String) async throws -> MaxInvitePreview {
    throw URLError(.unsupportedURL)
  }
  func acceptInvite(token: String) async throws -> MaxInviteAcceptResponse {
    throw URLError(.unsupportedURL)
  }
  func collectionMembers(collectionID: String) async throws -> [MaxCollectionMember] { [] }
  func addCollectionMember(
    collectionID: String,
    userID: String,
    role: String
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func removeCollectionMember(
    collectionID: String,
    userID: String
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func removeCollectionMedia(
    collectionID: String,
    mediaID: String
  ) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func continueWatching() async throws -> [MaxContinueItem] { [] }
  func wrapped() async throws -> MaxWrapped {
    throw URLError(.unsupportedURL)
  }

  // Sticker and share-link defaults keep minimal conformers (e.g. test doubles)
  // compiling; the live client and Demo Mode implement the real thing.
  func stickers() async throws -> [MaxSticker] { [] }
  func createSticker(
    imageData: Data,
    mimeType: String,
    emoji: String?
  ) async throws -> MaxSticker {
    throw URLError(.unsupportedURL)
  }
  func deleteSticker(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func favoriteSticker(id: String, favorite: Bool) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func sendSticker(
    chatID: String,
    stickerID: String,
    replyToID: String?
  ) async throws -> MobileMessageSendResponse {
    throw URLError(.unsupportedURL)
  }
  func createShareLink(
    mediaID: String,
    expiresInSeconds: Int,
    maxViews: Int?
  ) async throws -> MaxShareLink {
    throw URLError(.unsupportedURL)
  }
  func shareLinks(mediaID: String) async throws -> [MaxShareLink] { [] }
  func revokeShareLink(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }

  // Story, sticker-adoption and rewatched defaults keep minimal conformers
  // (e.g. test doubles) compiling; the live client and Demo Mode implement the
  // real thing.
  func stories() async throws -> [MaxStoryRail] { [] }
  func postStory(mediaID: String, caption: String) async throws -> MaxStory {
    throw URLError(.unsupportedURL)
  }
  func viewStory(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func deleteStory(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
  func adoptSticker(mediaID: String) async throws -> MaxSticker {
    throw URLError(.unsupportedURL)
  }
  func rewatched() async throws -> [MaxRewatchedItem] { [] }

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

  // Watch Together defaults keep minimal conformers (e.g. test doubles)
  // compiling: list reads answer empty, everything else refuses — only the
  // live client implements the real thing (Demo Mode has no realtime room).
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
    []
  }
  func createWatchGuestLink(
    roomID: String,
    expiresInHours: Int?,
    maxUses: Int?
  ) async throws -> WatchGuestLink {
    throw URLError(.unsupportedURL)
  }
  func watchGuestLinks(roomID: String) async throws -> [WatchGuestLink] { [] }
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
  func watchScheduled(conversationID: String) async throws -> [WatchScheduledEntry] { [] }
  func deleteWatchScheduled(id: String) async throws -> EmptySuccess {
    throw URLError(.unsupportedURL)
  }
}
