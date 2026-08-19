import SwiftUI

@main
struct MaxApp: App {
  @State private var appModel = MaxAppModel()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Configure a generous disk cache so AsyncImage thumbnails survive
    // across scrolls and app re-launches without hitting the network again.
    URLCache.shared = URLCache(
      memoryCapacity: 30 * 1024 * 1024,   // 30 MB in-memory
      diskCapacity: 200 * 1024 * 1024,    // 200 MB on-disk
      diskPath: "MaxThumbnailCache"
    )
  }

  var body: some Scene {
    WindowGroup {
      MaxThemeHost(theme: appModel.preferencesStore.theme) {
        MaxRootView()
          .environment(appModel)
          .environment(\.locale, appModel.preferencesStore.locale)
          .environment(\.layoutDirection, appModel.preferencesStore.layoutDirection)
      }
      .preferredColorScheme(appModel.preferencesStore.theme.forcedColorScheme)
      .task { await appModel.bootstrapIfNeeded() }
      .onChange(of: scenePhase) { _, phase in
        appModel.handleScenePhase(phase)
      }
    }
  }
}

@MainActor
@Observable
final class MaxAppModel {
  let apiClient: any MaxService
  let sessionStore: SessionStore
  let homeStore: HomeStore
  let libraryStore: LibraryStore
  let chatStore: ChatStore
  let chatsV3Store: ChatsV3Store
  let transferStore: TransferStore
  let profileStore: ProfileStore
  let ratingStore: RatingStore
  let networkMonitor: NetworkMonitor
  let preferencesStore: AppPreferencesStore
  let doubleLockStore: DoubleLockStore
  let memoriesStore: MemoriesStore
  let memoriesPhotoClient: any DevicePhotoLibraryClient
  let releaseStore: ReleaseAnnouncementStore

  let isDemoMode: Bool
  let isUITestMode: Bool
  let uiTestStartsAuthenticated: Bool
  private let demoService: DemoMaxService?

  var previousTab: AppTab? = nil
  var selectedTab: AppTab {
    willSet {
      if selectedTab != newValue {
        previousTab = selectedTab
      }
    }
    didSet { preferencesStore.lastRootTab = selectedTab.rawValue }
  }
  var isMemoriesEnabled: Bool {
    MemoriesFeatureAccess.isEnabled(for: sessionStore.user)
  }
  var activeSheet: MaxSheet?
  var activePlayer: MaxMediaItem?
  private var activePlayerQueue: [MaxMediaItem] = []
  private var activePlayerCatalogKind: MaxLibraryKindFilter?
  private var activePlayerCatalogSearch = ""
  private var activePlayerCatalogSort: MaxLibrarySort = .recent
  var isMemoriesPresented = false
  var didBootstrap = false
  var configurationError: String?

  init(configuration: MaxConfiguration = .fromBundle()) {
    let process = ProcessInfo.processInfo
    #if DEBUG
    let isUITestMode = process.arguments.contains("-MaxUITestMode")
      && process.environment["MAX_UI_TEST_DOUBLE_LOCK_BYPASS"] == "1"
    let uiTestStartsAuthenticated = process.environment["MAX_UI_TEST_AUTHENTICATED"] != "0"
    #else
    let isUITestMode = false
    let uiTestStartsAuthenticated = false
    #endif
    let isDemoMode = Self.demoModeRequested(process: process) || isUITestMode

    let tokenStore: any SessionTokenStore
    let service: any MaxService
    let demoService: DemoMaxService?
    let defaults: UserDefaults
    if isDemoMode {
      let localService = DemoMaxService()
      service = localService
      demoService = localService
      tokenStore = EphemeralSessionTokenStore()
      defaults = Self.demoDefaults()
    } else {
      demoService = nil
      let keychain = KeychainSessionStore(service: "app.max.iphone")
      tokenStore = keychain
      service = MaxAPIClient(configuration: configuration, tokenStore: keychain)
      defaults = .standard
    }

    let preferences = AppPreferencesStore(defaults: defaults)
    #if DEBUG
    if isUITestMode, let themeName = process.environment["MAX_UI_TEST_THEME"] {
      preferences.theme = AppTheme.persistedValue(themeName)
    }
    if isUITestMode,
       let languageName = process.environment["MAX_UI_TEST_LANGUAGE"],
       let language = AppLanguage(rawValue: languageName) {
      preferences.language = language
    }
    #endif

    self.apiClient = service
    self.sessionStore = SessionStore(api: service, tokenStore: tokenStore)
    self.homeStore = HomeStore(api: service)
    self.libraryStore = LibraryStore(api: service)
    self.chatStore = ChatStore(
      api: service,
      tokenStore: tokenStore,
      realtimeEnabled: !isDemoMode
    )
    self.chatsV3Store = ChatsV3Store(api: service)
    self.transferStore = TransferStore(
      api: service,
      storageNamespace: isDemoMode ? "MaxDemoTransfers" : "MaxTransfers",
      allowsLocalFixtureURLs: isDemoMode
    )
    self.profileStore = ProfileStore(api: service)
    self.ratingStore = RatingStore(api: service)
    self.networkMonitor = NetworkMonitor()
    self.preferencesStore = preferences
    self.doubleLockStore = DoubleLockStore()
    self.releaseStore = ReleaseAnnouncementStore()

    let memoryFiles = LocalMemoriesFileStore(
      namespace: isDemoMode ? "MaxDemoLocalMemories" : "MaxLocalMemories"
    )
    let photoClient: any DevicePhotoLibraryClient
    if isDemoMode {
      photoClient = DemoLocalMemoriesClient(files: memoryFiles)
    } else {
      photoClient = PhotoKitDevicePhotoLibraryClient(files: memoryFiles)
    }
    self.memoriesPhotoClient = photoClient
    self.memoriesStore = MemoriesStore(
      deviceClient: photoClient,
      stateStore: AppMemoryCycleStore(files: memoryFiles)
    )
    self.isDemoMode = isDemoMode
    self.isUITestMode = isUITestMode
    self.uiTestStartsAuthenticated = uiTestStartsAuthenticated
    self.demoService = demoService
    if isUITestMode,
       let initialTabEnv = ProcessInfo.processInfo.environment["MAX_UI_TEST_INITIAL_TAB"],
       let tab = AppTab(rawValue: initialTabEnv) {
      self.selectedTab = tab
    } else {
      self.selectedTab = AppTab(rawValue: preferences.lastRootTab) ?? .vault
    }

    // Wires the download-network policy signal. Without this the monitor stays
    // nil and the guard in TransferStore.download(_:) can never fire, which
    // makes the Wi-Fi-only download preference a no-op.
    transferStore.configure(networkMonitor: networkMonitor)
  }

  var presentsAuthenticatedShell: Bool { sessionStore.isAuthenticated }

  var serverURLString: String {
    isDemoMode ? "" : MaxConfiguration.fromBundle().baseURL.absoluteString
  }

  func bootstrapIfNeeded() async {
    guard !didBootstrap else { return }
    didBootstrap = true
    
    // Bootstrap dynamic plugin system and registries
    PluginStore.shared.bootstrap()
    
    // Bind proxies using the app model
    PluginStore.shared.bindProxies(
      navigation: DefaultPluginNavigationProxy(model: self),
      library: DefaultPluginLibraryProxy(model: self)
    )
    PluginSafeMode.shared.markBootstrapSuccessful()

    if !isDemoMode { networkMonitor.start() }

    #if DEBUG
    if isUITestMode,
       ProcessInfo.processInfo.environment["MAX_UI_TEST_RESET_DEMO"] == "1" {
      await resetDemoState(signInAfterReset: false)
    }
    #endif

    if isUITestMode, uiTestStartsAuthenticated {
      await signIn(email: "demo@max.local", password: "demo")
      return
    }
    guard !isDemoMode else { return }

    await sessionStore.restore()
    releaseStore.evaluateLaunch(
      isAuthenticated: sessionStore.isAuthenticated,
      userDisplayName: sessionStore.user?.displayName
    )
    suppressDisabledMemoriesAnnouncement()
    guard sessionStore.isAuthenticated else { return }
    await refreshAll()
  }

  func handleScenePhase(_ phase: ScenePhase) {
    switch phase {
    case .active:
      if !isDemoMode { networkMonitor.start() }
      doubleLockStore.sceneDidBecomeActive()
    case .inactive:
      doubleLockStore.sceneWillResignActive()
    case .background:
      doubleLockStore.sceneDidEnterBackground()
      PluginTakeoverCoordinator.shared.handleAppLifecycleInterrupt()
    @unknown default:
      break
    }
  }

  func signIn(email: String, password: String) async {
    await sessionStore.signIn(email: email, password: password)
    guard sessionStore.isAuthenticated else { return }
    releaseStore.evaluateAfterAuthentication(userDisplayName: sessionStore.user?.displayName)
    suppressDisabledMemoriesAnnouncement()
    await refreshAll()
  }

  private func suppressDisabledMemoriesAnnouncement() {
    guard !isMemoriesEnabled, releaseStore.activeAnnouncement?.destination == .memories else { return }
    releaseStore.dismissActiveAnnouncement()
  }

  func signInToDemo() async {
    guard isDemoMode else { return }
    await signIn(email: "demo@max.local", password: "demo")
  }

  func signOut() async {
    await sessionStore.signOut()
    MaxImageLoader.purgeSharedCache()
    // Poster frames are keyed by media id alone, so they must be dropped too or
    // the previous account's private first frames survive the sign-out.
    await MaxVideoPosterCache.shared.purge()
    homeStore.reset()
    libraryStore.reset()
    chatStore.reset()
    chatsV3Store.reset()
    transferStore.reset()
    profileStore.reset()
    ratingStore.reset()
    selectedTab = .vault
    activePlayer = nil
    activePlayerQueue = []
    activePlayerCatalogKind = nil
    activeSheet = nil
    isMemoriesPresented = false
  }

  func resetDemo() async {
    await resetDemoState(signInAfterReset: true)
  }

  private func resetDemoState(signInAfterReset: Bool) async {
    guard let demoService else { return }
    await demoService.reset()
    MaxImageLoader.purgeSharedCache()
    sessionStore.reset()
    transferStore.resetDemoStorage()
    preferencesStore.reset()
    await memoriesStore.resetLocalMemories()
    homeStore.reset()
    libraryStore.reset()
    chatStore.reset()
    chatsV3Store.reset()
    profileStore.reset()
    ratingStore.reset()
    selectedTab = .vault
    activePlayer = nil
    activePlayerQueue = []
    activePlayerCatalogKind = nil
    activeSheet = nil
    isMemoriesPresented = false
    if signInAfterReset { await signInToDemo() }
  }

  func refreshAll() async {
    guard sessionStore.isAuthenticated else { return }
    let userID = sessionStore.user?.id
    async let home: Void = homeStore.loadOverview()
    async let library: Void = libraryStore.load(currentUserID: userID)
    async let chats: Void = chatStore.loadThreads()
    // The Chats tab renders ChatsView, which reads chatStore. Warming
    // chatsV3Store here refetched the same conversation list a second time and
    // left the store the Mentions scope actually reads cold.
    async let chatActivity: Void = chatStore.loadActivity()
    async let access: Void = chatStore.loadAccessRequests()
    async let profile: Void = profileStore.load()
    _ = await (home, library, chats, chatActivity, access, profile)
  }

  @discardableResult
  func updateBaseURL(_ candidate: String) async -> Bool {
    guard !isDemoMode else {
      configurationError = String(localized: "server.demo_locked")
      return false
    }
    guard let url = MaxConfiguration.validHTTPURL(from: candidate) else {
      configurationError = String(localized: "server.invalid")
      return false
    }

    let oldConfiguration = MaxConfiguration.fromBundle()
    if oldConfiguration.baseURL == url {
      configurationError = nil
      return true
    }
    let previousSavedBaseURL = UserDefaults.standard.string(forKey: "vault_baseURL")
    if sessionStore.isAuthenticated { await signOut() }
    UserDefaults.standard.set(url.absoluteString, forKey: "vault_baseURL")

    // Read the saved value back before reporting success. The app previously
    // filtered the user's own address back out and kept calling the old server
    // while telling them the change had been applied. Compare normalized
    // origins, because `url` is already the normalized form of what they typed.
    let newConfiguration = MaxConfiguration.fromBundle()
    guard newConfiguration.baseURL == url else {
      if let previousSavedBaseURL {
        UserDefaults.standard.set(previousSavedBaseURL, forKey: "vault_baseURL")
      } else {
        UserDefaults.standard.removeObject(forKey: "vault_baseURL")
      }
      configurationError = String(localized: "server.invalid")
      return false
    }

    await apiClient.updateConfiguration(newConfiguration)
    configurationError = nil
    return true
  }

  func openPlayer(for item: MaxMediaItem) {
    activePlayerQueue = [item]
    activePlayerCatalogKind = nil
    activePlayer = item
  }

  func openPlayer(for item: MaxMediaItem, in items: [MaxMediaItem]) {
    var seen = Set<String>()
    let queue = items.filter { seen.insert($0.id).inserted }
    activePlayerQueue = queue.contains(where: { $0.id == item.id }) ? queue : [item]
    activePlayerCatalogKind = nil
    activePlayer = item
  }

  func openCatalogPlayer(
    for item: MaxMediaItem,
    kind: MaxLibraryKindFilter,
    search: String,
    sort: MaxLibrarySort
  ) {
    activePlayerCatalogKind = kind
    activePlayerCatalogSearch = search
    activePlayerCatalogSort = sort
    activePlayerQueue = catalogPlayerQueue()
    activePlayer = item
  }

  var canOpenPreviousPlayer: Bool {
    guard let activePlayer,
          let index = currentPlayerQueue.firstIndex(where: { $0.id == activePlayer.id }) else {
      return false
    }
    return index > 0
  }

  var canOpenNextPlayer: Bool {
    guard let activePlayer,
          let index = currentPlayerQueue.firstIndex(where: { $0.id == activePlayer.id }) else {
      return false
    }
    return index + 1 < currentPlayerQueue.count
      || (activePlayerCatalogKind != nil && libraryStore.hasMoreCatalog)
  }

  func openAdjacentPlayer(offset: Int) async {
    guard offset == -1 || offset == 1, let activePlayer else { return }
    var queue = currentPlayerQueue
    guard let currentIndex = queue.firstIndex(where: { $0.id == activePlayer.id }) else { return }

    if offset > 0,
       currentIndex + 1 >= queue.count,
       activePlayerCatalogKind != nil,
       libraryStore.hasMoreCatalog {
      await libraryStore.loadMoreCatalog()
      queue = currentPlayerQueue
      activePlayerQueue = queue
    }

    guard let refreshedIndex = queue.firstIndex(where: { $0.id == activePlayer.id }) else { return }
    let destination = refreshedIndex + offset

    // Deliberately not animated.
    //
    // `activePlayer` is the item of a fullScreenCover. Animating the swap made
    // SwiftUI dismiss the cover and present it again, so moving to the next video
    // played the whole modal out and back in — the viewer was thrown out of the
    // player and dropped into it again. Replacing the item without a transaction
    // keeps the cover on screen and swaps only its contents, which the player
    // itself cross-fades.
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      self.activePlayer = queue[destination]
    }
  }

  var currentPlayerQueue: [MaxMediaItem] {
    activePlayerCatalogKind == nil ? activePlayerQueue : catalogPlayerQueue()
  }

  private func catalogPlayerQueue() -> [MaxMediaItem] {
    guard let kind = activePlayerCatalogKind else { return activePlayerQueue }
    let query = activePlayerCatalogSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = libraryStore.catalogItems.filter { item in
      let matchesSearch = query.isEmpty
        || item.title.localizedCaseInsensitiveContains(query)
        || (item.uploader.name?.localizedCaseInsensitiveContains(query) ?? false)
        || (item.workspace?.name?.localizedCaseInsensitiveContains(query) ?? false)
      return matchesSearch && kind.includes(item)
    }
    return activePlayerCatalogSort.apply(to: filtered)
  }

  func openUpload(destination: UploadDestination) {
    activeSheet = .upload(destination)
  }

  func openTransfers() {
    activeSheet = .transfers
  }

  func openMemories(candidate: MemoryCandidate? = nil, fromHome: Bool = false) {
    guard isMemoriesEnabled else { return }
    releaseStore.markDestinationVisited(.memories)
    memoriesStore.prepareOpen(candidate: candidate, fromHome: fromHome)
    isMemoriesPresented = true
  }

  func openWhatsNew() {
    releaseStore.markDestinationVisited(.settings)
    activeSheet = .whatsNew
  }

  func openReleaseDestination(_ destination: ReleaseDestination) {
    releaseStore.markDestinationVisited(destination)
    activeSheet = nil
    switch destination {
    case .home:
      selectedTab = .vault
    case .library:
      selectedTab = .library
    case .create:
      selectedTab = .vault
      openUpload(destination: .personal)
    case .chats:
      selectedTab = .chats
    case .profile, .settings:
      selectedTab = .profile
    case .memories:
      guard isMemoriesEnabled else { return }
      openMemories()
    }
  }

  func openRating(for item: MaxMediaItem) {
    activeSheet = .rating(item)
  }

  func openAccessRequests() {
    activeSheet = .accessRequests
  }

  func toggleFavorite(_ item: MaxMediaItem) async {
    // Update in place instead of reloading the whole catalog: a full reload
    // briefly empties libraryStore.catalogItems, and the player's queue is
    // derived from it, so the active video reset to a black frame on every like.
    libraryStore.applyFavoriteChange(itemID: item.id, isFavorite: !item.isFavorite)
    await homeStore.toggleFavorite(item)
  }

  func persistPlayback(for item: MaxMediaItem, position: Double) async {
    await homeStore.saveHistory(item, position: position)
  }

  private static func demoModeRequested(process: ProcessInfo) -> Bool {
    if process.environment["MAX_DEMO_MODE"] == "1" { return true }
    guard let index = process.arguments.firstIndex(of: "-MAX_DEMO_MODE") else { return false }
    return process.arguments.indices.contains(index + 1)
      && process.arguments[index + 1] == "1"
  }

  private static func demoDefaults() -> UserDefaults {
    UserDefaults(suiteName: "app.max.iphone.demo") ?? UserDefaults()
  }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case vault
  case library
  case shared
  case chats
  case profile

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .vault: "tab.vault"
    case .library: "tab.library"
    case .shared: "tab.shared"
    case .chats: "tab.chats"
    case .profile: "tab.profile"
    }
  }

  var symbolName: String {
    switch self {
    case .vault: "archivebox"
    case .library: "rectangle.grid.2x2"
    case .shared: "person.2"
    case .chats: "bubble.left.and.bubble.right"
    case .profile: "person.crop.circle"
    }
  }
}

enum UploadDestination: Identifiable, Hashable {
  case personal
  case workspace(id: String, name: String)
  case chat(id: String, title: String)

  var id: String {
    switch self {
    case .personal: "personal"
    case .workspace(let id, _): "workspace-\(id)"
    case .chat(let id, _): "chat-\(id)"
    }
  }

  var spaceID: String? {
    guard case .workspace(let id, _) = self else { return nil }
    return id
  }
}

enum MaxSheet: Identifiable, Hashable {
  case rating(MaxMediaItem)
  case accessRequests
  case upload(UploadDestination)
  case transfers
  case whatsNew
  case serverSettings

  var id: String {
    switch self {
    case .rating(let item): "rating-\(item.id)"
    case .accessRequests: "access-requests"
    case .upload(let destination): "upload-\(destination.id)"
    case .transfers: "transfers"
    case .whatsNew: "whats-new"
    case .serverSettings: "server-settings"
    }
  }
}
