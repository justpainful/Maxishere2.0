import Foundation
import Network
import Observation

@MainActor
@Observable
final class SessionStore {
  private let api: any MaxService
  private let tokenStore: any SessionTokenStore

  var user: MaxUser?
  var preferences: MobilePreferences?
  var capabilities: MobileBootstrapResponse.Capabilities?
  var phase: LoadState<MaxUser> = .idle
  var loginEmail = ""
  var loginPassword = ""

  init(api: any MaxService, tokenStore: any SessionTokenStore) {
    self.api = api
    self.tokenStore = tokenStore
  }

  var isAuthenticated: Bool { user != nil }

  func restore() async {
    guard (try? tokenStore.loadToken()) != nil else {
      phase = .idle
      return
    }

    phase = .loading
    do {
      let response = try await api.bootstrap()
      apply(response)
    } catch {
      // A stale or revoked local token must not trap the app in an endless
      // failed-bootstrap loop on every launch.
      if error.isAuthenticationFailure {
        clearLocalSession()
        phase = .idle
      } else {
        phase = .failed(ProductError.from(error, area: .account).reason)
      }
    }
  }

  func signIn(email: String, password: String) async {
    phase = .loading
    do {
      _ = try await api.login(email: email, password: password)
      let bootstrap = try await api.bootstrap()
      apply(bootstrap)
      loginPassword = ""
    } catch {
      // Login may have stored a token before the bootstrap contract is
      // validated. Never retain an unverified session.
      clearLocalSession()
      phase = .failed(ProductError.from(error, area: .account).reason)
    }
  }

  func signOut() async {
    // The API client also clears local credentials in a defer block, but the
    // store keeps the local state correct even when the network is unavailable.
    try? await api.logout()
    clearLocalSession()
    phase = .idle
  }

  func reset() {
    clearLocalSession()
    phase = .idle
    loginEmail = ""
  }

  private func apply(_ response: MobileBootstrapResponse) {
    user = response.user
    preferences = response.preferences
    capabilities = response.capabilities
    phase = .loaded(response.user)
  }

  private func clearLocalSession() {
    try? tokenStore.clearToken()
    user = nil
    preferences = nil
    capabilities = nil
    loginPassword = ""
  }
}

@MainActor
@Observable
final class HomeStore {
  private let api: any MaxService

  var overview: LoadState<MobileHomeResponse> = .idle
  var filteredFeed: LoadState<[MaxMediaItem]> = .idle
  var query = MediaQuery()
  var selectedMode = "shuffle"

  init(api: any MaxService) {
    self.api = api
  }

  func reset() {
    overview = .idle
    filteredFeed = .idle
    query = MediaQuery()
    selectedMode = "shuffle"
  }

  func loadOverview() async {
    overview = .loading
    do {
      let response = try await api.home()
      selectedMode = response.defaultMode
      overview = .loaded(response)
      await loadFeed()
    } catch {
      let reason = ProductError.from(error, area: .vault).reason
      overview = .failed(reason)
      filteredFeed = .failed(reason)
    }
  }

  func loadFeed() async {
    filteredFeed = .loading
    do {
      query.mode = selectedMode
      filteredFeed = .loaded(try await api.media(query: query).items)
    } catch {
      filteredFeed = .failed(ProductError.from(error, area: .vault).reason)
    }
  }

  func toggleFavorite(_ item: MaxMediaItem) async {
    do {
      _ = try await api.setFavorite(fileID: item.id, favorite: !item.isFavorite)
      await loadOverview()
    } catch {
      filteredFeed = .failed(ProductError.from(error, area: .vault).reason)
    }
  }

  func saveHistory(_ item: MaxMediaItem, position: Double) async {
    do {
      _ = try await api.saveHistory(fileID: item.id, position: position)
    } catch {
      // Persisting playback should not block the session.
    }
  }
}

@MainActor
@Observable
final class LibraryStore {
  private let api: any MaxService

  var phase: LoadState<MobileLibraryResponse> = .idle
  var catalogPhase: LoadState<[MaxMediaItem]> = .idle
  var personalPhase: LoadState<[MaxMediaItem]> = .idle
  var catalogPageState: LoadState<Bool> = .idle
  var workspaceMediaByID: [String: LoadState<[MaxMediaItem]>] = [:]
  var workspacePageStateByID: [String: LoadState<Bool>] = [:]
  var collectionMutation: LoadState<String> = .idle
  var trashPhase: LoadState<[TrashedMedia]> = .idle
  var trashPageState: LoadState<Bool> = .idle
  private(set) var currentUserID: String?

  private var catalogNextOffset: Int?
  private var trashNextCursor: String?
  private var workspaceNextOffsetByID: [String: Int] = [:]

  init(api: any MaxService) {
    self.api = api
  }

  func reset() {
    phase = .idle
    catalogPhase = .idle
    personalPhase = .idle
    catalogPageState = .idle
    workspaceMediaByID = [:]
    workspacePageStateByID = [:]
    collectionMutation = .idle
    trashPhase = .idle
    trashPageState = .idle
    catalogNextOffset = nil
    trashNextCursor = nil
    workspaceNextOffsetByID = [:]
    currentUserID = nil
  }

  var trashedItems: [TrashedMedia] { trashPhase.value ?? [] }
  var hasMoreTrash: Bool { trashNextCursor != nil }

  var catalogItems: [MaxMediaItem] {
    catalogPhase.value ?? []
  }

  var personalItems: [MaxMediaItem] {
    personalPhase.value ?? []
  }

  var hasMoreCatalog: Bool { catalogNextOffset != nil }

  func load(currentUserID: String? = nil) async {
    if let currentUserID, !currentUserID.isEmpty {
      self.currentUserID = currentUserID
    } else if self.currentUserID == nil {
      self.currentUserID = await api.currentUserID()
    }

    phase = .loading
    catalogPhase = .loading
    personalPhase = .loading

    var query = MediaQuery()
    query.mode = "browse"
    query.limit = 100
    query.offset = 0

    async let metadataRequest = api.library()
    async let catalogRequest = api.media(query: query)

    do {
      phase = .loaded(try await metadataRequest)
    } catch {
      phase = .failed(ProductError.from(error, area: .library).reason)
    }

    do {
      let response = try await catalogRequest
      catalogNextOffset = response.pagination.nextOffset
      applyCatalog(response.items)
      catalogPageState = .loaded(response.pagination.nextOffset != nil)
    } catch {
      let message = ProductError.from(error, area: .library).reason
      catalogPhase = .failed(message)
      personalPhase = .failed(message)
      catalogPageState = .failed(message)
    }
  }

  func setCurrentUserID(_ userID: String?) {
    currentUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
    applyPersonalFilter(to: catalogItems)
  }

  func loadMoreCatalog() async {
    guard let offset = catalogNextOffset, !catalogPageState.isLoading else { return }
    catalogPageState = .loading

    var query = MediaQuery()
    query.mode = "browse"
    query.limit = 100
    query.offset = offset

    do {
      let response = try await api.media(query: query)
      let merged = Self.merging(catalogItems, with: response.items)
      catalogNextOffset = response.pagination.nextOffset
      applyCatalog(merged)
      catalogPageState = .loaded(response.pagination.nextOffset != nil)
    } catch {
      catalogPageState = .failed(ProductError.from(error, area: .library).reason)
    }
  }

  /// Exhausts the remaining catalog pages for operations whose semantics span
  /// the whole collection (currently Shuffle). Normal browsing remains
  /// incremental so the first page appears immediately.
  func loadRemainingCatalogPages() async {
    var previousCount = catalogItems.count
    while catalogNextOffset != nil {
      await loadMoreCatalog()
      guard catalogItems.count > previousCount,
            catalogPageState.errorMessage == nil else { return }
      previousCount = catalogItems.count
    }
  }

  // MARK: - Trash

  enum PurgeOutcome: Sendable, Equatable { case purged, inUse, failed }

  func loadTrash(reset: Bool = true) async {
    if reset {
      trashPhase = .loading
      trashNextCursor = nil
    }
    do {
      let page = try await api.trashedMedia(cursor: reset ? nil : trashNextCursor)
      trashNextCursor = page.nextCursor
      trashPhase = .loaded(reset ? page.items : trashedItems + page.items)
      trashPageState = .loaded(page.nextCursor != nil)
    } catch {
      let message = ProductError.from(error, area: .library).reason
      if reset { trashPhase = .failed(message) }
      trashPageState = .failed(message)
    }
  }

  func loadMoreTrash() async {
    guard trashNextCursor != nil, !trashPageState.isLoading else { return }
    trashPageState = .loading
    await loadTrash(reset: false)
  }

  /// Moves an item to Trash and optimistically removes it from the browse
  /// catalog. Returns false if the server rejected the delete.
  @discardableResult
  func trash(_ item: MaxMediaItem) async -> Bool {
    do {
      _ = try await api.trashMedia(fileID: item.id)
      applyCatalog(catalogItems.filter { $0.id != item.id })
      if case .loaded(var items) = trashPhase {
        let purgeAfter = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        items.insert(TrashedMedia(media: item, deletedAt: Date(), purgeAfter: purgeAfter), at: 0)
        trashPhase = .loaded(items)
      }
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func restore(_ item: TrashedMedia) async -> Bool {
    do {
      _ = try await api.restoreMedia(fileID: item.id)
      removeFromTrash(item.id)
      return true
    } catch {
      return false
    }
  }

  func purge(_ item: TrashedMedia) async -> PurgeOutcome {
    do {
      _ = try await api.purgeMedia(fileID: item.id)
      removeFromTrash(item.id)
      return .purged
    } catch {
      if case let MaxAPIError.server(status, _) = error, status == 409 {
        return .inUse
      }
      return .failed
    }
  }

  private func removeFromTrash(_ id: String) {
    if case .loaded(let items) = trashPhase {
      trashPhase = .loaded(items.filter { $0.id != id })
    }
  }

  func loadWorkspaceMedia(workspaceID: String, reset: Bool = true) async {
    let trimmedID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedID.isEmpty else {
      workspaceMediaByID[workspaceID] = .failed(
        String(localized: "error.workspace.missing_id")
      )
      return
    }
    guard workspacePageStateByID[trimmedID]?.isLoading != true else { return }

    let offset = reset ? 0 : (workspaceNextOffsetByID[trimmedID] ?? 0)
    if reset {
      workspaceMediaByID[trimmedID] = .loading
    }
    workspacePageStateByID[trimmedID] = .loading

    var query = MediaQuery()
    query.mode = "browse"
    query.workspaceId = trimmedID
    query.limit = 100
    query.offset = offset

    do {
      let response = try await api.media(query: query)
      let existing = reset ? [] : (workspaceMediaByID[trimmedID]?.value ?? [])
      let merged = Self.merging(existing, with: response.items)
      workspaceMediaByID[trimmedID] = .loaded(merged)
      if let nextOffset = response.pagination.nextOffset {
        workspaceNextOffsetByID[trimmedID] = nextOffset
      } else {
        workspaceNextOffsetByID[trimmedID] = nil
      }
      workspacePageStateByID[trimmedID] = .loaded(response.pagination.nextOffset != nil)
    } catch {
      let message = ProductError.from(error, area: .library).reason
      if reset {
        workspaceMediaByID[trimmedID] = .failed(message)
      }
      workspacePageStateByID[trimmedID] = .failed(message)
    }
  }

  func loadMoreWorkspaceMedia(workspaceID: String) async {
    let trimmedID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard workspaceNextOffsetByID[trimmedID] != nil else { return }
    await loadWorkspaceMedia(workspaceID: trimmedID, reset: false)
  }

  @discardableResult
  func add(fileID: String, toCollectionID collectionID: String) async -> Bool {
    guard !fileID.isEmpty, !collectionID.isEmpty else { return false }
    collectionMutation = .loading
    do {
      let response = try await api.addToCollection(
        fileID: fileID,
        collectionID: collectionID
      )
      collectionMutation = .loaded(response.collectionId)
      await load(currentUserID: currentUserID)
      return true
    } catch {
      collectionMutation = .failed(
        ProductError.from(error, area: .library).reason
      )
      return false
    }
  }

  private func applyCatalog(_ items: [MaxMediaItem]) {
    catalogPhase = .loaded(items)
    applyPersonalFilter(to: items)
  }

  /// Flips one item's favorite flag in place without a reload, so an open player
  /// whose queue is derived from the catalog never sees the list momentarily
  /// empty (which reset playback to a black frame).
  func applyFavoriteChange(itemID: String, isFavorite: Bool) {
    guard case .loaded(let items) = catalogPhase else { return }
    let updated = items.map { $0.id == itemID ? $0.withFavorite(isFavorite) : $0 }
    applyCatalog(updated)
    applySavedShelf(from: updated, changedID: itemID, isFavorite: isFavorite)
  }

  /// Keeps the Saved shelf in step with a like made anywhere else in the app.
  ///
  /// `LibraryView` only loads once per session, so without this a video liked in
  /// the player did not appear under Saved until the user pulled to refresh — the
  /// same symptom as the shelf reading the wrong flag entirely.
  private func applySavedShelf(from items: [MaxMediaItem], changedID: String, isFavorite: Bool) {
    guard case .loaded(let library) = phase else { return }
    var saved = library.saved.filter { $0.id != changedID }
    if isFavorite, let item = items.first(where: { $0.id == changedID }) {
      saved.insert(item, at: 0)
    }
    phase = .loaded(
      MobileLibraryResponse(
        success: library.success,
        personalStorage: library.personalStorage,
        workspaces: library.workspaces,
        collections: library.collections,
        saved: saved,
        downloads: library.downloads
      )
    )
  }

  private func applyPersonalFilter(to items: [MaxMediaItem]) {
    guard let currentUserID, !currentUserID.isEmpty else {
      personalPhase = .failed(String(localized: "error.account.identity_unavailable"))
      return
    }
    personalPhase = .loaded(items.filter { $0.uploader.id == currentUserID })
  }

  private static func merging(
    _ existing: [MaxMediaItem],
    with incoming: [MaxMediaItem]
  ) -> [MaxMediaItem] {
    var seen = Set<String>()
    return (existing + incoming).filter { seen.insert($0.id).inserted }
  }
}

@MainActor
@Observable
final class ChatStore {
  private let api: any MaxService
  private let tokenStore: any SessionTokenStore
  private let realtimeEnabled: Bool

  var threads: LoadState<[ChatThread]> = .idle
  var messagesByChat: [String: LoadState<[ChatMessage]>] = [:]
  var searchResultsByChat: [String: LoadState<[ChatMessage]>] = [:]
  var pinnedMessagesByChat: [String: LoadState<[ChatMessage]>] = [:]
  var preferencesByChat: [String: LoadState<ChatThreadPreference>] = [:]
  var membersByChat: [String: LoadState<[ChatGroupMember]>] = [:]
  var peopleSearch: LoadState<[ChatPerson]> = .idle
  var createChatError: String?
  var messagePageStateByChat: [String: MessagePageState] = [:]
  var accessRequests: LoadState<MobileAccessRequestsResponse> = .idle
  /// The mentions / activity feed. It used to live in a second chat store that
  /// nothing reachable rendered, which also made the app fetch the conversation
  /// list twice on every refresh.
  var activity: LoadState<[ChatActivity]> = .idle
  var selectedThreadID: String?
  var draftsByChat: [String: String] = [:]
  var sendStateByChat: [String: ChatSendState] = [:]
  var isRealtimeConnected = false
  var typingUserIDByChat: [String: String] = [:]

  private var unscopedDraft = ""
  private var messageLoadsInFlight = Set<String>()
  private var realtimeThreadID: String?
  private var realtimeSocket: URLSessionWebSocketTask?
  private var realtimeTask: Task<Void, Never>?
  private var typingStopTask: Task<Void, Never>?

  init(
    api: any MaxService,
    tokenStore: any SessionTokenStore,
    realtimeEnabled: Bool
  ) {
    self.api = api
    self.tokenStore = tokenStore
    self.realtimeEnabled = realtimeEnabled
  }

  func reset() {
    stopRealtime()
    threads = .idle
    messagesByChat = [:]
    searchResultsByChat = [:]
    pinnedMessagesByChat = [:]
    preferencesByChat = [:]
    membersByChat = [:]
    peopleSearch = .idle
    createChatError = nil
    messagePageStateByChat = [:]
    accessRequests = .idle
    activity = .idle
    selectedThreadID = nil
    draftsByChat = [:]
    sendStateByChat = [:]
    typingUserIDByChat = [:]
    unscopedDraft = ""
    messageLoadsInFlight = []
  }

  var composerText: String {
    get {
      guard let selectedThreadID else { return unscopedDraft }
      return draftsByChat[selectedThreadID] ?? ""
    }
    set {
      guard let selectedThreadID else {
        unscopedDraft = newValue
        return
      }
      draftsByChat[selectedThreadID] = newValue
    }
  }

  func draft(for threadID: String) -> String {
    draftsByChat[threadID] ?? ""
  }

  func setDraft(_ draft: String, for threadID: String) {
    let previous = draftsByChat[threadID] ?? ""
    draftsByChat[threadID] = draft
    guard realtimeThreadID == threadID else { return }
    let wasEmpty = previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if wasEmpty && !isEmpty { sendTyping(true, in: threadID) }
    typingStopTask?.cancel()
    guard !isEmpty else {
      sendTyping(false, in: threadID)
      return
    }
    typingStopTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      self?.sendTyping(false, in: threadID)
    }
  }

  func startRealtime(for threadID: String) {
    guard realtimeEnabled, realtimeThreadID != threadID else { return }
    stopRealtime()
    realtimeThreadID = threadID
    realtimeTask = Task { [weak self] in
      await self?.runRealtime(for: threadID)
    }
  }

  func stopRealtime() {
    typingStopTask?.cancel()
    typingStopTask = nil
    realtimeTask?.cancel()
    realtimeTask = nil
    realtimeSocket?.cancel(with: .goingAway, reason: nil)
    realtimeSocket = nil
    realtimeThreadID = nil
    isRealtimeConnected = false
    typingUserIDByChat = [:]
  }

  private func runRealtime(for threadID: String) async {
    var retryDelay = 1.0
    let viewerID = await api.currentUserID()
    while !Task.isCancelled, realtimeThreadID == threadID {
      do {
        let socket = try await makeRealtimeSocket()
        realtimeSocket = socket
        socket.resume()

        while !Task.isCancelled, realtimeThreadID == threadID {
          let message = try await socket.receive()
          let data: Data
          switch message {
          case .data(let value): data = value
          case .string(let value): data = Data(value.utf8)
          @unknown default: continue
          }
          guard let envelope = try? JSONDecoder().decode(
            ChatRealtimeEnvelope.self,
            from: data
          ) else {
            continue
          }
          retryDelay = 1
          await handleRealtimeEvent(envelope, threadID: threadID, viewerID: viewerID)
        }
      } catch is CancellationError {
        break
      } catch {
        isRealtimeConnected = false
      }
      realtimeSocket?.cancel(with: .goingAway, reason: nil)
      realtimeSocket = nil
      isRealtimeConnected = false
      guard !Task.isCancelled, realtimeThreadID == threadID else { break }
      try? await Task.sleep(for: .seconds(retryDelay))
      retryDelay = min(retryDelay * 2, 12)
    }
  }

  private func handleRealtimeEvent(
    _ envelope: ChatRealtimeEnvelope,
    threadID: String,
    viewerID: String?
  ) async {
    // Only conversation-scoped events carry an id. `realtime.ready` and
    // `presence.updated` carry none and must not be filtered away.
    if let conversationID = envelope.data?.conversationId,
       conversationID.caseInsensitiveCompare(threadID) != .orderedSame {
      return
    }

    switch envelope.type {
    case ChatRealtimeEventType.ready:
      // Only a frame that actually decoded proves this socket delivers. Setting
      // the flag on `resume()` let a mute socket suppress the polling fallback,
      // which is what made the chat look completely inert.
      isRealtimeConnected = true

    case ChatRealtimeEventType.typingUpdated:
      guard let userID = envelope.data?.userId else { return }
      // The conversation fan-out includes the actor, so without this the user
      // watches themselves type.
      guard userID.caseInsensitiveCompare(viewerID ?? "") != .orderedSame else { return }
      typingUserIDByChat[threadID] = envelope.data?.typing == true ? userID : nil

    case ChatRealtimeEventType.presenceUpdated:
      return

    case ChatRealtimeEventType.messageCreated:
      await refreshMessages(for: threadID)
      await markRead(threadID)
      await loadThreads(loadSelectedMessages: false)

    case ChatRealtimeEventType.readUpdated:
      await refreshMessages(for: threadID)

    default:
      // An unrecognised type is still a sign the conversation changed.
      await refreshMessages(for: threadID)
    }
  }

  private func makeRealtimeSocket() async throws -> URLSessionWebSocketTask {
    let ticket = try await api.realtimeTicket()
    let baseURL = MaxConfiguration.fromBundle().baseURL
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }
    components.scheme = baseURL.scheme?.lowercased() == "https" ? "wss" : "ws"
    components.path = "/api/v2/realtime/connect"
    components.queryItems = [URLQueryItem(name: "ticket", value: ticket.ticket)]
    guard let url = components.url else { throw URLError(.badURL) }
    return URLSession.shared.webSocketTask(with: url)
  }

  private func sendTyping(_ isTyping: Bool, in threadID: String) {
    guard let realtimeSocket else { return }
    // The server closes the socket with a policy violation on anything that is
    // not exactly this shape, and on a conversation id it cannot parse as a
    // UUID — which is why the socket used to die on the first keystroke.
    guard UUID(uuidString: threadID) != nil else { return }
    let payload: [String: Any] = [
      "type": "typing.set",
      "conversationId": threadID,
      "typing": isTyping,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8) else { return }
    Task { try? await realtimeSocket.send(.string(text)) }
  }

  func isSending(to threadID: String) -> Bool {
    sendStateByChat[threadID]?.isSending == true
  }

  func loadThreads(loadSelectedMessages: Bool = true) async {
    // Only show the skeleton on a genuinely cold load. `.loading` carries no
    // payload, so resetting unconditionally replaced the whole conversation list
    // with a redacted placeholder on every pull-to-refresh, every archive or mute
    // swipe, and every post-send reload — the list visibly flashed away and back.
    if threads.value == nil {
      threads = .loading
    }
    do {
      let response = try await api.chats()
      threads = .loaded(response.chats)
      if selectedThreadID == nil {
        selectedThreadID = response.chats.first?.id
      }
      if loadSelectedMessages,
         let selectedThreadID,
         messagesByChat[selectedThreadID]?.value == nil {
        await loadMessages(for: selectedThreadID)
      }
    } catch {
      threads = .failed(ProductError.from(error, area: .chats).reason)
    }
  }

  func loadMessages(
    for threadID: String,
    before: String? = nil,
    limit: Int = 100,
    silently: Bool = false
  ) async {
    // Must match the server's own cap. Asking for more made `canLoadMore` below
    // compare a 100-row page against a 500-row request and always conclude that
    // there was no older history, which is the "scrolling hits a wall" symptom.
    let safeLimit = min(max(limit, 1), 100)
    guard !messageLoadsInFlight.contains(threadID) else { return }
    messageLoadsInFlight.insert(threadID)
    defer { messageLoadsInFlight.remove(threadID) }

    if before == nil {
      if !silently { messagesByChat[threadID] = .loading }
    } else {
      messagePageStateByChat[threadID] = .loadingOlder
    }

    do {
      let response = try await api.messages(
        chatID: threadID,
        limit: safeLimit,
        before: before
      )
      let messages: [ChatMessage]
      if before == nil {
        let existing = silently ? (messagesByChat[threadID]?.value ?? []) : []
        messages = Self.mergingMessages(existing, with: response.messages)
      } else {
        let existing = messagesByChat[threadID]?.value ?? []
        messages = Self.mergingMessages(existing, with: response.messages)
      }
      messagesByChat[threadID] = .loaded(messages)
      let canLoadMore = response.messages.count == safeLimit
        && response.messages.first?.createdAt != nil
      messagePageStateByChat[threadID] = .loaded(canLoadMore: canLoadMore)
    } catch {
      let message = ProductError.from(error, area: .chats).reason
      if before == nil && !silently {
        messagesByChat[threadID] = .failed(message)
      } else if before != nil {
        messagePageStateByChat[threadID] = .failed(message)
      }
    }
  }

  func searchPeople(query: String) async {
    peopleSearch = .loading
    do {
      let response = try await api.searchChatPeople(query: query)
      peopleSearch = .loaded(response.people)
    } catch {
      peopleSearch = .failed(ProductError.from(error, area: .chats).reason)
    }
  }

  @discardableResult
  func createDirectChat(userID: String) async -> ChatThread? {
    createChatError = nil
    do {
      let response = try await api.createDirectChat(userID: userID)
      installCreatedThread(response.chat)
      return response.chat
    } catch {
      createChatError = ProductError.from(error, area: .chats).reason
      return nil
    }
  }

  @discardableResult
  func createGroupChat(name: String, memberIDs: [String]) async -> ChatThread? {
    createChatError = nil
    do {
      let response = try await api.createGroupChat(name: name, memberIDs: memberIDs)
      installCreatedThread(response.chat)
      return response.chat
    } catch {
      createChatError = ProductError.from(error, area: .chats).reason
      return nil
    }
  }

  private func installCreatedThread(_ thread: ChatThread) {
    var current = threads.value ?? []
    current.removeAll { $0.id == thread.id }
    current.insert(thread, at: 0)
    threads = .loaded(current)
    messagesByChat[thread.id] = messagesByChat[thread.id] ?? .loaded([])
    selectedThreadID = thread.id
  }

  func refreshMessages(for threadID: String) async {
    await loadMessages(for: threadID, limit: 100, silently: true)
  }

  func loadOlderMessages(for threadID: String, limit: Int = 100) async {
    guard let pageState = messagePageStateByChat[threadID],
          case .loaded(let canLoadMore) = pageState,
          canLoadMore,
          let before = messagesByChat[threadID]?.value?.first?.id else {
      return
    }
    await loadMessages(for: threadID, before: before, limit: limit)
  }

  func searchMessages(in threadID: String, query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      searchResultsByChat[threadID] = .loaded([])
      return
    }
    searchResultsByChat[threadID] = .loading
    do {
      let response = try await api.searchMessages(
        chatID: threadID,
        query: trimmed,
        limit: 50
      )
      searchResultsByChat[threadID] = .loaded(response.messages)
    } catch {
      searchResultsByChat[threadID] = .failed(
        ProductError.from(error, area: .chats).reason
      )
    }
  }

  func loadPinnedMessages(in threadID: String) async {
    pinnedMessagesByChat[threadID] = .loading
    do {
      let response = try await api.pinnedMessages(chatID: threadID)
      pinnedMessagesByChat[threadID] = .loaded(response.messages)
    } catch {
      pinnedMessagesByChat[threadID] = .failed(
        ProductError.from(error, area: .chats).reason
      )
    }
  }

  func loadPreference(for threadID: String) async {
    preferencesByChat[threadID] = .loading
    do {
      let response = try await api.chatPreference(chatID: threadID)
      preferencesByChat[threadID] = .loaded(response.preference)
    } catch {
      preferencesByChat[threadID] = .failed(
        ProductError.from(error, area: .chats).reason
      )
    }
  }

  @discardableResult
  func updatePreference(
    for threadID: String,
    isMuted: Bool,
    isArchived: Bool,
    mutedUntil: String? = nil
  ) async -> Bool {
    do {
      let response = try await api.updateChatPreference(
        chatID: threadID,
        isMuted: isMuted,
        isArchived: isArchived,
        mutedUntil: mutedUntil
      )
      preferencesByChat[threadID] = .loaded(response.preference)
      await loadThreads(loadSelectedMessages: false)
      return true
    } catch {
      preferencesByChat[threadID] = .failed(
        ProductError.from(error, area: .chats).reason
      )
      return false
    }
  }

  func loadMembers(for threadID: String) async {
    if membersByChat[threadID]?.value == nil { membersByChat[threadID] = .loading }
    do {
      let response = try await api.chatMembers(chatID: threadID)
      membersByChat[threadID] = .loaded(response.members)
    } catch {
      if membersByChat[threadID]?.value == nil {
        membersByChat[threadID] = .failed(
          ProductError.from(error, area: .chats).reason
        )
      }
    }
  }

  // MARK: - Conversation management
  //
  // Renaming a group, managing members, clearing history and deleting a
  // conversation all exist on the server. None of them were reachable from this
  // store, so the whole admin surface was unusable from the chat the app shows.

  @discardableResult
  func renameGroup(_ threadID: String, name: String) async -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    do {
      _ = try await api.updateChatGroup(chatID: threadID, name: trimmed, avatar: nil)
      await loadThreads(loadSelectedMessages: false)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func addMember(_ userID: String, to threadID: String, role: String = "member") async -> Bool {
    do {
      _ = try await api.addChatMember(chatID: threadID, userID: userID, role: role)
      await loadMembers(for: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func updateMemberRole(_ userID: String, in threadID: String, role: String) async -> Bool {
    do {
      _ = try await api.updateChatMemberRole(chatID: threadID, userID: userID, role: role)
      await loadMembers(for: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func removeMember(_ userID: String, from threadID: String) async -> Bool {
    do {
      _ = try await api.removeChatMember(chatID: threadID, userID: userID)
      await loadMembers(for: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func clearMessages(in threadID: String) async -> Bool {
    do {
      _ = try await api.clearChatMessages(chatID: threadID)
      messagesByChat[threadID] = .loaded([])
      messagePageStateByChat[threadID] = .loaded(canLoadMore: false)
      await loadThreads(loadSelectedMessages: false)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func deleteChat(_ threadID: String) async -> Bool {
    do {
      _ = try await api.deleteChat(chatID: threadID)
      messagesByChat[threadID] = nil
      messagePageStateByChat[threadID] = nil
      preferencesByChat[threadID] = nil
      membersByChat[threadID] = nil
      pinnedMessagesByChat[threadID] = nil
      if var current = threads.value {
        current.removeAll { $0.id == threadID }
        threads = .loaded(current)
      }
      if selectedThreadID == threadID { selectedThreadID = nil }
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  /// Consumes a view-once attachment. The server stamps `openedAt`, after which
  /// it stops handing out a URL for that media at all.
  func markViewOnceRead(_ messageID: String, in threadID: String) async {
    do {
      _ = try await api.readViewOnceMessage(chatID: threadID, messageID: messageID)
      await refreshMessages(for: threadID)
    } catch {
      // The photo has already been shown; a failed consume must not raise an
      // alert over the conversation.
    }
  }

  @discardableResult
  func sendMessage(
    to threadID: String,
    content: String? = nil,
    mediaFileIDs: [String] = [],
    replyToID: String? = nil,
    clientMessageID: String = UUID().uuidString.lowercased()
  ) async -> ChatMessage? {
    guard !isSending(to: threadID) else { return nil }

    let outgoingText = (content ?? draft(for: threadID))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedFileIDs = Self.normalizedFileIDs(mediaFileIDs)
    guard normalizedFileIDs.count == mediaFileIDs.count,
          normalizedFileIDs.count <= 12 else {
      let transaction = PendingChatSend(
        threadID: threadID,
        content: outgoingText,
        mediaFileIDs: normalizedFileIDs,
        replyToID: replyToID,
        clientMessageID: clientMessageID
      )
      sendStateByChat[threadID] = .failed(
        ChatSendFailure(
          transaction: transaction,
          message: String(localized: "error.upload.invalid_file_ids"),
          failedAt: Date()
        )
      )
      return nil
    }
    guard !outgoingText.isEmpty || !normalizedFileIDs.isEmpty else { return nil }

    let transaction = PendingChatSend(
      threadID: threadID,
      content: outgoingText,
      mediaFileIDs: normalizedFileIDs,
      replyToID: replyToID,
      clientMessageID: clientMessageID
    )
    sendStateByChat[threadID] = .sending(transaction)

    do {
      let response = try await api.sendMessage(
        chatID: threadID,
        caption: outgoingText,
        mediaFileIDs: normalizedFileIDs,
        replyToID: replyToID,
        clientMessageID: clientMessageID
      )
      let existing = messagesByChat[threadID]?.value ?? []
      messagesByChat[threadID] = .loaded(
        Self.mergingMessages(existing, with: [response.message])
      )
      if draft(for: threadID).trimmingCharacters(in: .whitespacesAndNewlines) == outgoingText {
        draftsByChat[threadID] = ""
      }
      sendStateByChat[threadID] = .idle
      // Silent: a blocking reload here replaced the whole timeline with a
      // spinner every time the user pressed send.
      await refreshMessages(for: threadID)
      await loadThreads(loadSelectedMessages: false)
      // Sending is reading. The server agrees, but the list refresh above may
      // have been served before the send landed, so settle the badge here rather
      // than let the user watch their own message count itself unread.
      clearUnreadBadge(for: threadID)
      return response.message
    } catch {
      sendStateByChat[threadID] = .failed(
        ChatSendFailure(
          transaction: transaction,
          message: ProductError.from(error, area: .chats).reason,
          failedAt: Date()
        )
      )
      return nil
    }
  }

  @discardableResult
  func retrySend(to threadID: String) async -> ChatMessage? {
    guard let sendState = sendStateByChat[threadID],
          case .failed(let failure) = sendState else {
      return nil
    }
    let transaction = failure.transaction
    return await sendMessage(
      to: transaction.threadID,
      content: transaction.content,
      mediaFileIDs: transaction.mediaFileIDs,
      replyToID: transaction.replyToID,
      // Reusing the original key lets the server recognise the retry as the same
      // send instead of persisting a second copy of the message.
      clientMessageID: transaction.clientMessageID
    )
  }

  func clearSendError(for threadID: String) {
    guard sendStateByChat[threadID]?.isSending != true else { return }
    sendStateByChat[threadID] = .idle
  }

  @discardableResult
  func editMessage(
    _ messageID: String,
    in threadID: String,
    content: String
  ) async -> ChatMessage? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    do {
      let response = try await api.editMessage(
        chatID: threadID,
        messageID: messageID,
        content: trimmed
      )
      replaceMessage(response.message, in: threadID)
      return response.message
    } catch {
      sendStateByChat[threadID] = .failed(
        ChatSendFailure(
          transaction: PendingChatSend(
            threadID: threadID,
            content: trimmed,
            mediaFileIDs: [],
            replyToID: nil
          ),
          message: ProductError.from(error, area: .chats).reason,
          failedAt: Date()
        )
      )
      return nil
    }
  }

  @discardableResult
  func deleteMessage(_ messageID: String, in threadID: String) async -> Bool {
    let originalMessages = messagesByChat[threadID]?.value ?? []
    
    var updatedMessages = originalMessages
    updatedMessages.removeAll { $0.id == messageID }
    messagesByChat[threadID] = .loaded(updatedMessages)
    
    do {
      let response = try await api.deleteMessage(chatID: threadID, messageID: messageID)
      if !response.message.isHardDeleted {
        replaceMessage(response.message, in: threadID)
      }
      return true
    } catch {
      messagesByChat[threadID] = .loaded(originalMessages)
      
      sendStateByChat[threadID] = .failed(
        ChatSendFailure(
          transaction: PendingChatSend(
            threadID: threadID,
            content: "",
            mediaFileIDs: [],
            replyToID: nil
          ),
          message: ProductError.from(error, area: .chats).reason,
          failedAt: Date()
        )
      )
      return false
    }
  }

  @discardableResult
  func setPinned(
    _ isPinned: Bool,
    messageID: String,
    in threadID: String
  ) async -> Bool {
    do {
      let response = try await api.setMessagePinned(
        chatID: threadID,
        messageID: messageID,
        isPinned: isPinned
      )
      replaceMessage(response.message, in: threadID)
      await loadPinnedMessages(in: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func setReaction(
    _ reactionKey: String?,
    messageID: String,
    in threadID: String
  ) async -> Bool {
    do {
      let response = try await api.setMessageReaction(
        chatID: threadID,
        messageID: messageID,
        reactionKey: reactionKey
      )
      guard let current = messagesByChat[threadID]?.value?.first(where: {
        $0.id == messageID
      }) else {
        await refreshMessages(for: threadID)
        return true
      }
      replaceMessage(current.replacingReactions(response.reactions), in: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func createPoll(
    in threadID: String,
    question: String,
    options: [String],
    allowMultipleVotes: Bool
  ) async -> ChatMessage? {
    do {
      let response = try await api.createChatPoll(
        chatID: threadID,
        question: question,
        options: options,
        allowMultipleVotes: allowMultipleVotes
      )
      replaceMessage(response.message, in: threadID)
      await loadThreads(loadSelectedMessages: false)
      return response.message
    } catch {
      setMutationFailure(error, threadID: threadID)
      return nil
    }
  }

  @discardableResult
  func setPollVote(
    in threadID: String,
    pollID: String,
    optionID: String,
    selected: Bool
  ) async -> Bool {
    do {
      let response = try await api.setChatPollVote(
        chatID: threadID,
        pollID: pollID,
        optionID: optionID,
        selected: selected
      )
      replaceMessage(response.message, in: threadID)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  @discardableResult
  func forwardMessage(
    _ messageID: String,
    from threadID: String,
    to targetThreadID: String
  ) async -> Bool {
    do {
      let response = try await api.forwardMessage(
        chatID: threadID,
        messageID: messageID,
        targetChatID: targetThreadID
      )
      let existing = messagesByChat[targetThreadID]?.value ?? []
      messagesByChat[targetThreadID] = .loaded(
        Self.mergingMessages(existing, with: [response.message])
      )
      await loadThreads(loadSelectedMessages: false)
      return true
    } catch {
      setMutationFailure(error, threadID: threadID)
      return false
    }
  }

  func markRead(_ threadID: String) async {
    // Clear the badge locally first. The list is refreshed from several places,
    // and waiting for the round trip meant the count the user just dismissed
    // flickered back onto the row.
    clearUnreadBadge(for: threadID)
    do {
      _ = try await api.markChatRead(chatID: threadID)
    } catch {
      // Read receipts are best-effort and must not replace visible message content with an error.
    }
  }

  /// Zeroes one thread's unread count in the loaded list, leaving every other
  /// field alone.
  private func clearUnreadBadge(for threadID: String) {
    guard case .loaded(let current) = threads,
          current.contains(where: { $0.id == threadID && $0.unreadCount > 0 }) else { return }
    threads = .loaded(current.map { $0.id == threadID ? $0.markingRead() : $0 })
  }

  func loadAccessRequests() async {
    accessRequests = .loading
    do {
      accessRequests = .loaded(try await api.accessRequests())
    } catch {
      accessRequests = .failed(ProductError.from(error, area: .shared).reason)
    }
  }

  func loadActivity() async {
    // Keep the populated feed on screen while refreshing; `.loading` carries no
    // payload, so resetting unconditionally swaps the list for a skeleton.
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
      // Reading a conversation must stay available when notification state lags.
    }
  }

  var unreadActivityCount: Int {
    (activity.value ?? []).filter { $0.readAt == nil }.count
  }

  func requestAccess(for fileID: String, messageID: String?) async {
    do {
      _ = try await api.requestAccess(fileID: fileID, messageID: messageID)
      await loadAccessRequests()
    } catch {
      accessRequests = .failed(ProductError.from(error, area: .shared).reason)
    }
  }

  func decideAccessRequest(_ requestID: String, approve: Bool) async {
    do {
      _ = try await api.decideAccessRequest(
        id: requestID,
        decision: approve ? "approved" : "denied"
      )
      await loadAccessRequests()
    } catch {
      accessRequests = .failed(ProductError.from(error, area: .shared).reason)
    }
  }

  private static func normalizedFileIDs(_ fileIDs: [String]) -> [String] {
    var seen = Set<String>()
    return fileIDs.compactMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
      return trimmed
    }
  }

  private func replaceMessage(_ message: ChatMessage, in threadID: String) {
    let existing = messagesByChat[threadID]?.value ?? []
    messagesByChat[threadID] = .loaded(
      Self.mergingMessages(existing, with: [message])
    )
  }

  private func setMutationFailure(_ error: Error, threadID: String) {
    sendStateByChat[threadID] = .failed(
      ChatSendFailure(
        transaction: PendingChatSend(
          threadID: threadID,
          content: "",
          mediaFileIDs: [],
          replyToID: nil
        ),
        message: ProductError.from(error, area: .chats).reason,
        failedAt: Date()
      )
    )
  }

  private static func mergingMessages(
    _ existing: [ChatMessage],
    with incoming: [ChatMessage]
  ) -> [ChatMessage] {
    var byID: [String: ChatMessage] = [:]
    for message in existing {
      byID[message.id] = message
    }
    for message in incoming {
      byID[message.id] = message
    }
    return byID.values.sorted { lhs, rhs in
      let lhsDate = lhs.createdAt ?? ""
      let rhsDate = rhs.createdAt ?? ""
      return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
    }
  }
}

@MainActor
@Observable
final class ProfileStore {
  private let api: any MaxService
  var phase: LoadState<MobileProfileResponse> = .idle

  init(api: any MaxService) {
    self.api = api
  }

  func reset() {
    phase = .idle
  }

  func load() async {
    phase = .loading
    do {
      phase = .loaded(try await api.profile())
    } catch {
      phase = .failed(ProductError.from(error, area: .profile).reason)
    }
  }

  func update(_ patch: ProfileUpdateRequest) async -> Bool {
    do {
      phase = .loaded(try await api.updateProfile(patch))
      return true
    } catch {
      let productError = ProductError.from(
        error,
        area: .profile,
        fallback: .profileUpdateFailed
      )
      phase = .failed(productError.reason)
      return false
    }
  }

  func uploadImage(fileURL: URL, kind: ProfileImageKind) async -> URL? {
    do {
      return try await api.uploadProfileImage(fileURL: fileURL, kind: kind)
    } catch {
      let productError = ProductError.from(
        error,
        area: .profile,
        fallback: .uploadFailed
      )
      phase = .failed(productError.reason)
      return nil
    }
  }
}

@MainActor
@Observable
final class NetworkMonitor {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "app.max.network")
  private var started = false

  var isOnline = true
  var isExpensive = false
  var isConstrained = false

  func start() {
    guard !started else { return }
    started = true
    monitor.pathUpdateHandler = { [weak self] path in
      let isOnline = path.status == .satisfied
      let isExpensive = path.isExpensive
      let isConstrained = path.isConstrained
      Task { @MainActor in
        self?.isOnline = isOnline
        self?.isExpensive = isExpensive
        self?.isConstrained = isConstrained
      }
    }
    monitor.start(queue: queue)
  }

  func reset() {
    isOnline = true
    isExpensive = false
    isConstrained = false
  }
}
