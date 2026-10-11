import Foundation
import XCTest
@testable import Max

@MainActor
final class ProductContractTests: XCTestCase {
  func testRootTabsAreExactlyTheFiveProductDestinations() {
    XCTAssertEqual(
      AppTab.allCases.map(\.rawValue),
      ["vault", "library", "shared", "chats", "profile"]
    )
    XCTAssertFalse(AppTab.allCases.map(\.rawValue).contains("home"))
  }

  func testMemoriesFeatureFlagOnlyAllowsConfiguredEmail() {
    let allowed = MaxUser(
      id: "allowed",
      email: " Allowed@Example.com ",
      username: nil,
      displayName: "Allowed",
      avatarUrl: nil,
      coverUrl: nil,
      bio: nil,
      role: nil,
      accessLevel: nil
    )
    let denied = MaxUser(
      id: "denied",
      email: "someone@example.com",
      username: nil,
      displayName: "Denied",
      avatarUrl: nil,
      coverUrl: nil,
      bio: nil,
      role: nil,
      accessLevel: nil
    )

    // Memories is switched off for everyone while it still crashes the app, so the
    // allowlisted account is denied too. The allowlist itself is asserted
    // separately below so that turning the feature back on cannot silently open it
    // to accounts it was never meant for.
    XCTAssertTrue(MemoriesFeatureAccess.isTemporarilyDisabled)
    XCTAssertFalse(MemoriesFeatureAccess.isEnabled(for: allowed))
    XCTAssertFalse(MemoriesFeatureAccess.isEnabled(for: denied))
    XCTAssertFalse(MemoriesFeatureAccess.isEnabled(for: nil))

    // The allowlist is a digest, so it cannot be read back as an address; pin it
    // by hash and prove the normalisation (trim + lowercase) feeds the digest.
    XCTAssertEqual(
      MemoriesFeatureAccess.enabledEmailDigest,
      "130f751840251bad6368398481a85af9abb3acc478ed9fb8fe57d6d03585d9d5"
    )
    XCTAssertEqual(
      MemoriesFeatureAccess.digest(of: " Allowed@Example.com "),
      MemoriesFeatureAccess.digest(of: "allowed@example.com")
    )
  }

  func testDemoRatingsStaySeparateAndEncodeNoAverage() async throws {
    let service = DemoMaxService()
    _ = try await service.login(email: "demo@max.local", password: "demo")

    let response = try await service.ratings(fileID: "demo-media-aurora")

    XCTAssertEqual(response.subjects.count, 2)
    XCTAssertEqual(Set(response.subjects.map(\.user.id)).count, 2)
    let data = try JSONEncoder().encode(response)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("average"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("avgScore"))
  }

  func testSelectingActiveRatingClearsOnlyThatSubject() async throws {
    let service = DemoMaxService()
    _ = try await service.login(email: "demo@max.local", password: "demo")
    let store = RatingStore(api: service)
    await store.load(fileID: "demo-media-aurora")

    let original = try XCTUnwrap(store.subjects(for: "demo-media-aurora").first)
    let selectedScore = try XCTUnwrap(original.score)
    await store.commit(
      fileID: "demo-media-aurora",
      subjectID: original.id,
      selectedScore: selectedScore
    )

    let updated = store.subjects(for: "demo-media-aurora")
    XCTAssertNil(updated.first(where: { $0.id == original.id })?.score)
    XCTAssertEqual(updated.first(where: { $0.id != original.id })?.score, 6)
  }

  func testFailedRatingMutationRollsBackOptimisticValue() async throws {
    let subject = RatingSubject(
      user: .init(id: "person-a", displayName: "Person A", avatarUrl: nil),
      score: 7,
      updatedAt: "2026-07-14T08:00:00Z",
      canEdit: true
    )
    let service = FailingRatingService(subjects: [subject])
    let store = RatingStore(api: service)
    await store.load(fileID: "file-a")

    await store.commit(fileID: "file-a", subjectID: subject.id, selectedScore: 8)

    XCTAssertEqual(store.subjects(for: "file-a").first?.score, 7)
    XCTAssertEqual(store.presentedError?.code, .ratingSaveFailed)
    let callCount = await service.setRatingCallCount
    XCTAssertEqual(callCount, 1)
  }

  func testDemoProfileEditPersistsEveryEditableIdentityField() async throws {
    let service = DemoMaxService()
    _ = try await service.login(email: "demo@max.local", password: "demo")

    let updated = try await service.updateProfile(
      ProfileUpdateRequest(
        displayName: "Max Recording",
        username: "max_recording",
        bio: "A deterministic local profile."
      )
    )

    XCTAssertEqual(updated.user.displayName, "Max Recording")
    XCTAssertEqual(updated.user.username, "max_recording")
    XCTAssertEqual(updated.user.bio, "A deterministic local profile.")
    let restored = try await service.profile()
    XCTAssertEqual(restored.user, updated.user)
  }

  func testDemoChatSupportsReplyEditAndDeleteWithoutNetworkState() async throws {
    let service = DemoMaxService()
    _ = try await service.login(email: "demo@max.local", password: "demo")

    let sent = try await service.sendMessage(
      chatID: "demo-chat-shared",
      caption: "Local reply",
      mediaFileIDs: [],
      replyToID: "demo-message-shared"
    )
    let sentMessage = sent.message
    XCTAssertEqual(sentMessage.replyToId, "demo-message-shared")
    XCTAssertEqual(sentMessage.replyPreview?.id, "demo-message-shared")

    let edited = try await service.editMessage(
      chatID: "demo-chat-shared",
      messageID: sentMessage.id,
      content: "Edited locally"
    )
    XCTAssertEqual(edited.message.content, "Edited locally")
    XCTAssertTrue(edited.message.isEdited)

    let deleted = try await service.deleteMessage(
      chatID: "demo-chat-shared",
      messageID: sentMessage.id
    )
    XCTAssertTrue(deleted.message.isDeleted)
    XCTAssertNil(deleted.message.content)
  }

  func testMemoriesStatePersistsAndResetPreservesOriginalAsset() async throws {
    let testRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaxProductContract-\(UUID().uuidString)", isDirectory: true)
    let localRoot = testRoot.appendingPathComponent("MaxLocalMemories", isDirectory: true)
    let originalURL = testRoot.appendingPathComponent("OriginalPhoto.jpg")
    try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    try Data([0x4d, 0x41, 0x58]).write(to: originalURL)
    defer { try? FileManager.default.removeItem(at: testRoot) }

    let files = LocalMemoriesFileStore(rootOverride: localRoot)
    let stateStore = AppMemoryCycleStore(files: files)
    let key = MemoryAssetKey(identifier: "photos-local-asset")
    var state = MemoriesLocalState()
    state.savedKeys = [key]
    state.hiddenKeys = [key]
    state.viewedAt = [key: Date(timeIntervalSince1970: 1_700_000_000)]
    stateStore.saveState(state)

    let store = MemoriesStore(
      deviceClient: DemoLocalMemoriesClient(files: files),
      stateStore: stateStore
    )
    XCTAssertTrue(store.savedKeys.contains(key))
    XCTAssertTrue(store.hiddenKeys.contains(key))
    XCTAssertNotNil(store.viewedAt[key])

    await store.resetLocalMemories()

    XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
    XCTAssertTrue(store.savedKeys.isEmpty)
    XCTAssertTrue(store.hiddenKeys.isEmpty)
    XCTAssertTrue(store.viewedAt.isEmpty)
  }

  func testMemoriesSavedHiddenAndViewedStatePersistIndependently() async throws {
    let testRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaxMemoryBehavior-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testRoot) }

    let files = LocalMemoriesFileStore(rootOverride: testRoot)
    let stateStore = AppMemoryCycleStore(files: files)
    let store = MemoriesStore(
      deviceClient: DemoLocalMemoriesClient(files: files),
      stateStore: stateStore
    )
    await store.activate()
    let candidate = try XCTUnwrap(store.currentSequence.first)

    store.toggleSaved(candidate)
    store.markViewed(candidate)
    store.hide(candidate)

    XCTAssertTrue(store.savedKeys.contains(candidate.key))
    XCTAssertTrue(store.hiddenKeys.contains(candidate.key))
    XCTAssertNotNil(store.viewedAt[candidate.key])

    let restored = MemoriesStore(
      deviceClient: DemoLocalMemoriesClient(files: files),
      stateStore: AppMemoryCycleStore(files: files)
    )
    XCTAssertTrue(restored.savedKeys.contains(candidate.key))
    XCTAssertTrue(restored.hiddenKeys.contains(candidate.key))
    XCTAssertNotNil(restored.viewedAt[candidate.key])
  }

  func testMemoriesRemainLocalOnlyAndUseVerticalPaging() throws {
    let memoriesSource = try Self.swiftSources(in: "Features/Memories")
    XCTAssertFalse(memoriesSource.contains("MaxAPIClient"))
    XCTAssertFalse(memoriesSource.contains("MaxService"))
    XCTAssertFalse(memoriesSource.contains("URLSession"))

    let viewerSource = try Self.appSource("Features/Memories/MemoriesViewerView.swift")
    let rootSource = try Self.appSource("Features/Memories/MemoriesFeature.swift")
    XCTAssertTrue(viewerSource.contains("ScrollView(.vertical)"))
    XCTAssertTrue(viewerSource.contains(".scrollTargetBehavior(.paging)"))
    XCTAssertTrue(viewerSource.contains(".scrollPosition(id: $selection)"))
    XCTAssertTrue(rootSource.contains("MemoriesViewerView(store: store"))
    XCTAssertFalse(rootSource.contains("MemoriesModeRail"))
    XCTAssertFalse(rootSource.contains("MemoriesLayoutPicker"))
    XCTAssertFalse(rootSource.contains("MemoriesGrid"))
  }

  func testProfileHeaderUsesResponsiveContentFlow() throws {
    let profileSource = try Self.appSource("Views/ProfileView.swift")

    XCTAssertTrue(profileSource.contains("ViewThatFits(in: .horizontal)"))
    XCTAssertTrue(profileSource.contains("@ScaledMetric(relativeTo: .title)"))
    XCTAssertFalse(profileSource.contains("ZStack(alignment: .bottomLeading)"))
    XCTAssertFalse(profileSource.contains(".frame(height: 180)"))
  }

  func testMemoriesCancelsPhotoRequestsAndBoundsVideoPlayback() throws {
    let photoClient = try Self.appSource(
      "Features/Memories/LocalPhotoLibraryClient.swift"
    )
    let mediaViews = try Self.appSource("Features/Memories/MemoriesMediaViews.swift")
    let store = try Self.appSource("Features/Memories/MemoriesStore.swift")

    XCTAssertTrue(photoClient.contains("withTaskCancellationHandler"))
    XCTAssertTrue(photoClient.contains("cancelImageRequest"))
    XCTAssertTrue(mediaViews.contains("-\\(isActive)"))
    XCTAssertTrue(mediaViews.contains("guard isActive else"))
    XCTAssertTrue(store.contains("!isIndexing"))
  }

  func testProductErrorDoesNotExposeServerSecrets() {
    let secret = "Bearer max-production-secret database=/private/internal.sqlite"
    let error = ProductError.from(
      MaxAPIError.server(status: 500, message: secret),
      area: .vault
    )
    let unsafeRequestError = ProductError(
      area: .vault,
      code: .unknown,
      title: "Safe title",
      reason: "Safe reason",
      requestID: "token/\(secret)"
    )

    XCTAssertFalse(error.reason.contains(secret))
    XCTAssertFalse(error.supportDetails.contains(secret))
    XCTAssertFalse(unsafeRequestError.supportDetails.contains(secret))
    XCTAssertFalse(unsafeRequestError.supportDetails.contains("Request:"))
  }

  func testVisibleProductNameUsesOnlyCanonicalMaxCasing() throws {
    let visibleSources = [
      try Self.appSource("Views/LoginView.swift"),
      try Self.appSource("Features/ReleaseExperience/ReleaseHeroView.swift"),
      try Self.appSource("Resources/Localizable.xcstrings"),
    ].joined(separator: "\n")

    let uppercaseVariant = "MA" + "X"
    let mixedCaseVariant = "Ma" + "X"
    XCTAssertFalse(visibleSources.contains("Text(verbatim: \"\(uppercaseVariant)\")"))
    XCTAssertFalse(visibleSources.contains("Text(\"\(mixedCaseVariant)\")"))
    XCTAssertFalse(visibleSources.contains("\(mixedCaseVariant) is now on your phone"))
    XCTAssertFalse(visibleSources.contains("\(mixedCaseVariant) الآن على جوالك"))
  }

  func testLoggedOutEntryPresentsCredentialsAsASheet() throws {
    let root = try Self.appSource("Views/MaxRootView.swift")
    let entry = try Self.appSource("Views/EntryExperienceView.swift")

    XCTAssertTrue(root.contains("EntryExperienceView()"))
    XCTAssertTrue(entry.contains(".sheet(item: $presentedSheet)"))
    XCTAssertTrue(entry.contains("LoginView()"))
    XCTAssertTrue(entry.contains("ui_entry_continue"))
  }

func testVaultMediaCardsHideFileNamesAndUseStableColumns() throws {
  let vault = try Self.appSource("Views/HomeView.swift")
  let components = try Self.appSource("Features/Library/LibraryComponents.swift")

  let continueStart = try XCTUnwrap(components.range(of: "struct MaxVaultContinueCard"))
  let cardStart = try XCTUnwrap(components.range(of: "struct MaxVaultMediaCard"))
  let rowStart = try XCTUnwrap(components.range(of: "struct MaxLibraryMediaRow"))
  let continueCard = components[continueStart.lowerBound..<cardStart.lowerBound]
  let mediaCard = components[cardStart.lowerBound..<rowStart.lowerBound]

  XCTAssertFalse(vault.contains("GridItem(.adaptive(minimum: 150"))
  XCTAssertFalse(vault.contains("personalItems.prefix(12)"))
  XCTAssertFalse(continueCard.contains("Text(verbatim: item.title)"))
  XCTAssertFalse(continueCard.contains("sourceName"))
  XCTAssertFalse(mediaCard.contains("Text(verbatim: item.title)"))
  XCTAssertFalse(mediaCard.contains("sourceName"))

  // Media tiles take the shape of their own media. A fixed square cropped every
  // portrait video to its middle, which is what read as "zoomed in", and forcing
  // one height on mixed orientations is what made the spacing look irregular.
  XCTAssertTrue(vault.contains("MaxMediaMasonry("))
  XCTAssertFalse(mediaCard.contains(".aspectRatio(1, contentMode: .fit)"))
  XCTAssertTrue(mediaCard.contains("usesContainerShape: true"))
}

  func testProfileShelvesStayFlatAndHideFileNames() throws {
    let profile = try Self.appSource("Views/ProfileView.swift")

    let favouritesStart = try XCTUnwrap(profile.range(of: "struct ProfileFavoritesSection"))
    let favouritesEnd = try XCTUnwrap(profile.range(of: "struct ProfileFavoriteRow"))
    let shelf = profile[favouritesStart.lowerBound..<favouritesEnd.lowerBound]

    // The shelf sits inside the profile's own LazyVStack. Nesting a second lazy
    // stack there lets rows draw over one another, because the inner stack
    // reports a provisional height for content it has not measured.
    XCTAssertFalse(shelf.contains("LazyVStack"))

    // Raw upload names are file system detail, not a title.
    XCTAssertFalse(profile.contains("Text(verbatim: item.title)"))
    XCTAssertTrue(profile.contains("item.displayTitle"))
  }

  func testSavedShelfIsBuiltFromTheFlagTheHeartActuallyWrites() throws {
    let client = try Self.appSource("Infrastructure/MaxAPIClient.swift")

    // The heart writes `favorite`, on every client. The shelf used to filter on
    // `isSaved` — the old watch-later flag iOS never set — which left every like
    // invisible. One flag now, so the shelf reads that one.
    XCTAssertTrue(client.contains("saved: items.filter(\\.isFavorite)"))

    // The profile's ratings shelf is derived, not stubbed out.
    XCTAssertFalse(client.contains("personalRatings: [],"))
  }

  func testPlayerSourceOmitsProhibitedControls() throws {
    let paths = [
      "Player/MaxPlayerView.swift",
      "Player/MaxPlayerChrome.swift",
      "Player/MaxPlayerPlayback.swift",
      "Player/MaxPlayerSurface.swift",
    ]
    let source = try paths.map(Self.appSource).joined(separator: "\n")
      .replacingOccurrences(of: #"//.*"#, with: "", options: .regularExpression)
      .lowercased()
    let prohibitedTokens = [
      "avplayerviewcontroller(",
      "playback_speed",
      "playback.speed",
      "player.subtitle",
      "audio_track",
      "remove_download",
      "remove_local",
      "quality_selector",
      "video_info",
    ]

    for token in prohibitedTokens {
      XCTAssertFalse(source.contains(token), "Prohibited player control token: \(token)")
    }
    XCTAssertTrue(source.contains("ui_player_play_pause"))
    XCTAssertTrue(source.contains("ui_player_dual_ratings"))
    XCTAssertTrue(source.contains("ui_player_add_to_collection"))
  }

  func testRatingDragCommitsOnlyAfterGestureEnds() throws {
    let source = try Self.appSource("Features/Ratings/DiscreteRatingControl.swift")
    let changedStart = try XCTUnwrap(source.range(of: ".onChanged"))
    let endedStart = try XCTUnwrap(source.range(of: ".onEnded"))
    let scoreFunctionStart = try XCTUnwrap(source.range(of: "private func score"))

    let changedSection = source[changedStart.lowerBound..<endedStart.lowerBound]
    let endedSection = source[endedStart.lowerBound..<scoreFunctionStart.lowerBound]
    XCTAssertFalse(changedSection.contains("onCommit("))
    XCTAssertTrue(endedSection.contains("onCommit(finalScore)"))
  }

  func testBlackCouncilThemeVerification() {
    XCTAssertEqual(AppTheme.council.rawValue, "council")
    XCTAssertEqual(AppTheme.council.forcedColorScheme, .dark)
    XCTAssertEqual(AppTheme.council.titleKey, "settings.theme.council")
    XCTAssertEqual(AppTheme.council.descriptionKey, "settings.theme.council.description")
  }

  func testMaxThemePaletteResolvesCouncilCorrectly() {
    let palette = MaxThemePalette.resolve(theme: .council, systemColorScheme: .dark)
    XCTAssertEqual(palette.selectedTheme, .council)
    XCTAssertEqual(palette.variant, .council)
    XCTAssertTrue(palette.isDark)
    XCTAssertTrue(palette.isCouncil)
  }

  func testAppPreferencesStoreGatheringState() {
    let preferences = AppPreferencesStore(defaults: .standard)
    preferences.hasShownCouncilGathering = false
    XCTAssertFalse(preferences.hasShownCouncilGathering)
    preferences.hasShownCouncilGathering = true
    XCTAssertTrue(preferences.hasShownCouncilGathering)
  }

  func testLiveMediaContractPaginatesUploadsAndPreservesProfileImages() throws {
    let api = try Self.appSource("Infrastructure/MaxAPIClient.swift")

    XCTAssertTrue(api.contains("private func allMedia() async throws"))
    XCTAssertFalse(api.contains("/api/v2/media?limit=5000"))
    XCTAssertTrue(api.contains("targetUserId"))
    XCTAssertTrue(api.contains("if let avatarMediaId"))
    XCTAssertTrue(api.contains("if let coverMediaId"))
    XCTAssertTrue(api.contains("let updated: MaxV2User = try await request"))
  }

  func testVideoFallbackAndNavigationUseRealNativeSurfaces() throws {
    let components = try Self.appSource("Views/Components.swift")
    let root = try Self.appSource("Views/MaxRootView.swift")
    let player = try Self.appSource("Player/MaxPlayerPlayback.swift")
    let shuffle = try Self.appSource("Player/MaxScrollingPlayerView.swift")

    XCTAssertTrue(components.contains("private struct MaxVideoPoster"))
    XCTAssertTrue(components.contains("maximumSize = CGSize(width: 960, height: 960)"))
    XCTAssertTrue(player.contains("AVURLAsset(url: playbackURL)"))
    XCTAssertTrue(shuffle.contains("AVURLAsset(url: url)"))
    XCTAssertFalse(root.contains("ChatsCustomTabBar"))
    XCTAssertFalse(root.contains("MaxPluginTabBar"))
    XCTAssertFalse(root.contains("activeVisualPlugin?.overlayView()"))
  }

  func testChatsUsesTheCoreThemeCanvasRatherThanOnlyTintingButtons() throws {
    let chats = try Self.appSource("Features/ChatsV3/ChatsV3App.swift")

    XCTAssertTrue(chats.contains(".maxTabContent()"))
    XCTAssertTrue(chats.contains(".scrollContentBackground(.hidden)"))
    XCTAssertTrue(chats.contains(".listRowBackground(palette.primaryContentSurface.opacity(0.88))"))
  }

  private static func appSource(_ path: String) throws -> String {
    try String(contentsOf: maxRoot.appendingPathComponent(path), encoding: .utf8)
  }

  private static func swiftSources(in directory: String) throws -> String {
    let directoryURL = maxRoot.appendingPathComponent(directory, isDirectory: true)
    return try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
      .filter { $0.pathExtension == "swift" }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
  }

  private static var maxRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}

private enum ProductContractStubError: Error {
  case unimplemented
  case ratingRejected
}

private actor FailingRatingService: MaxService {
  private let subjects: [RatingSubject]
  private(set) var setRatingCallCount = 0

  init(subjects: [RatingSubject]) {
    self.subjects = subjects
  }

  func updateConfiguration(_ configuration: MaxConfiguration) async {}
  func bootstrap() async throws -> MobileBootstrapResponse { throw unimplemented }
  func login(email: String, password: String) async throws -> MobileLoginResponse {
    throw unimplemented
  }
  func logout() async throws { throw unimplemented }
  func home() async throws -> MobileHomeResponse { throw unimplemented }
  func media(query: MediaQuery) async throws -> MobileMediaListResponse { throw unimplemented }
  func peerProfileStats(userID: String) async throws -> MaxV2PeerStats { throw unimplemented }
  func library() async throws -> MobileLibraryResponse { throw unimplemented }
  func addToCollection(
    fileID: String,
    collectionID: String
  ) async throws -> MobileCollectionMutationResponse { throw unimplemented }
  func channels() async throws -> [ChannelDoc] { throw unimplemented }
  func channel(id: String) async throws -> ChannelDoc { throw unimplemented }
  func createChannel(_ input: ChannelInput) async throws -> ChannelDoc { throw unimplemented }
  func updateChannel(id: String, input: ChannelInput) async throws -> ChannelDoc {
    throw unimplemented
  }
  func deleteChannel(id: String) async throws { throw unimplemented }
  func previewChannel(_ input: ChannelInput) async throws -> ChannelPreview { throw unimplemented }
  func tuneChannel(id: String) async throws -> ChannelDoc { throw unimplemented }
  func leaveChannel(id: String) async throws { throw unimplemented }
  func setChannelLive(id: String, live: Bool) async throws -> ChannelDoc { throw unimplemented }
  func resolveChannelMedia(id: String, ids: [String]) async throws -> [ChannelMediaRef] {
    throw unimplemented
  }
  func currentUserID() async -> String? { "person-a" }

  // The rest of MaxService, so this double conforms.
  //
  // It exists to make ONE call fail — setRating — and had fallen 94
  // requirements behind the protocol, which is what "does not conform to
  // protocol 'MaxService'" meant and why every iOS build failed. Each stub is
  // derived from the protocol's own declaration rather than hand-written, so a
  // signature cannot drift from the thing it is standing in for.
  func peerProfile(userID: String) async throws -> MaxV2Profile { throw unimplemented }
  func searchChatPeople(query: String) async throws -> MobileChatPeopleResponse { throw unimplemented }
  func createDirectChat(userID: String) async throws -> MobileChatCreateResponse { throw unimplemented }
  func createGroupChat( name: String, memberIDs: [String] ) async throws -> MobileChatCreateResponse { throw unimplemented }
  func searchMessages( chatID: String, query: String, limit: Int ) async throws -> MobileMessagesResponse { throw unimplemented }
  func pinnedMessages(chatID: String) async throws -> MobileMessagesResponse { throw unimplemented }
  func setMessageReaction( chatID: String, messageID: String, reactionKey: String? ) async throws -> MobileChatReactionMutationResponse { throw unimplemented }
  func chatPreference(chatID: String) async throws -> MobileChatPreferenceResponse { throw unimplemented }
  func updateChatPreference( chatID: String, isMuted: Bool, isArchived: Bool, mutedUntil: String? ) async throws -> MobileChatPreferenceMutationResponse { throw unimplemented }
  func chatMembers(chatID: String) async throws -> MobileChatMembersResponse { throw unimplemented }
  func createChatPoll( chatID: String, question: String, options: [String], allowMultipleVotes: Bool ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func setChatPollVote( chatID: String, pollID: String, optionID: String, selected: Bool ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func chatActivity(limit: Int) async throws -> MobileChatActivityResponse { throw unimplemented }
  func markChatActivityRead(activityIDs: [String]) async throws -> MobileChatActivityReadResponse { throw unimplemented }
  func sendMessageV3( chatID: String, caption: String, mediaFileIDs: [String], replyToID: String?, mentionUserIDs: [String] ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func updateChatGroup( chatID: String, name: String?, avatar: String? ) async throws -> MobileChatGroupMutationResponse { throw unimplemented }
  func addChatMember( chatID: String, userID: String, role: String ) async throws -> MobileChatMemberMutationResponse { throw unimplemented }
  func updateChatMemberRole( chatID: String, userID: String, role: String ) async throws -> MobileChatMemberMutationResponse { throw unimplemented }
  func removeChatMember(chatID: String, userID: String) async throws -> MobileChatMemberMutationResponse { throw unimplemented }
  func deleteChat(chatID: String) async throws -> EmptySuccess { throw unimplemented }
  func sendImageMessage( chatID: String, imageData: Data, replyToID: String?, isViewOnce: Bool ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func sendVoiceMessage( chatID: String, audioData: Data, replyToID: String? ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func clearChatMessages(chatID: String) async throws -> EmptySuccess { throw unimplemented }
  func readViewOnceMessage(chatID: String, messageID: String) async throws -> EmptySuccess { throw unimplemented }
  func setChatTTL(chatID: String, ttlSeconds: Int?) async throws -> EmptySuccess { throw unimplemented }
  func setVoiceTranscript( chatID: String, messageID: String, mediaID: String, transcript: String ) async throws -> EmptySuccess { throw unimplemented }
  func allClips() async throws -> [MediaClip] { throw unimplemented }
  func mediaClips(mediaID: String) async throws -> [MediaClip] { throw unimplemented }
  func createClip( mediaID: String, title: String, startSeconds: Double, endSeconds: Double ) async throws -> MediaClip { throw unimplemented }
  func deleteClip(clipID: String) async throws -> EmptySuccess { throw unimplemented }
  func mediaMarkers(mediaID: String) async throws -> [MediaMarker] { throw unimplemented }
  func createMarker( mediaID: String, atSeconds: Double, label: String ) async throws -> MediaMarker { throw unimplemented }
  func deleteMarker(markerID: String) async throws -> EmptySuccess { throw unimplemented }
  func mediaItem(id: String) async throws -> MaxMediaItem { throw unimplemented }
  func savedMessages() async throws -> MobileChatCreateResponse { throw unimplemented }
  func scheduleMessage( chatID: String, body: String, clientMessageID: String, sendAt: String ) async throws -> ScheduledMessage { throw unimplemented }
  func scheduledMessages(chatID: String) async throws -> [ScheduledMessage] { throw unimplemented }
  func cancelScheduledMessage(id: String) async throws -> EmptySuccess { throw unimplemented }
  func sampleHeatmap(mediaID: String, bin: Int) async {}
  func heatmap(mediaID: String) async throws -> [Double] { throw unimplemented }
  func exportClip( clipID: String, format: String, sendToConversationId: String? ) async throws -> EmptySuccess { throw unimplemented }
  func updateChatDraft(chatID: String, text: String) async throws -> EmptySuccess { throw unimplemented }
  func createGroupInvite( chatID: String, expiresInSeconds: Int, maxUses: Int? ) async throws -> MaxGroupInvite { throw unimplemented }
  func groupInvites(chatID: String) async throws -> [MaxGroupInvite] { throw unimplemented }
  func revokeGroupInvite(id: String) async throws -> EmptySuccess { throw unimplemented }
  func invitePreview(token: String) async throws -> MaxInvitePreview { throw unimplemented }
  func acceptInvite(token: String) async throws -> MaxInviteAcceptResponse { throw unimplemented }
  func collectionMembers(collectionID: String) async throws -> [MaxCollectionMember] { throw unimplemented }
  func addCollectionMember( collectionID: String, userID: String, role: String ) async throws -> EmptySuccess { throw unimplemented }
  func removeCollectionMember( collectionID: String, userID: String ) async throws -> EmptySuccess { throw unimplemented }
  func removeCollectionMedia( collectionID: String, mediaID: String ) async throws -> EmptySuccess { throw unimplemented }
  func continueWatching() async throws -> [MaxContinueItem] { throw unimplemented }
  func wrapped() async throws -> MaxWrapped { throw unimplemented }
  func stickers() async throws -> [MaxSticker] { throw unimplemented }
  func createSticker( imageData: Data, mimeType: String, emoji: String? ) async throws -> MaxSticker { throw unimplemented }
  func deleteSticker(id: String) async throws -> EmptySuccess { throw unimplemented }
  func favoriteSticker(id: String, favorite: Bool) async throws -> EmptySuccess { throw unimplemented }
  func sendSticker( chatID: String, stickerID: String, replyToID: String? ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func createShareLink( mediaID: String, expiresInSeconds: Int, maxViews: Int? ) async throws -> MaxShareLink { throw unimplemented }
  func shareLinks(mediaID: String) async throws -> [MaxShareLink] { throw unimplemented }
  func revokeShareLink(id: String) async throws -> EmptySuccess { throw unimplemented }
  func stories() async throws -> [MaxStoryRail] { throw unimplemented }
  func postStory(mediaID: String, caption: String) async throws -> MaxStory { throw unimplemented }
  func viewStory(id: String) async throws -> EmptySuccess { throw unimplemented }
  func deleteStory(id: String) async throws -> EmptySuccess { throw unimplemented }
  func adoptSticker(mediaID: String) async throws -> MaxSticker { throw unimplemented }
  func rewatched() async throws -> [MaxRewatchedItem] { throw unimplemented }
  func trashedMedia(cursor: String?) async throws -> TrashedMediaPage { throw unimplemented }
  func trashMedia(fileID: String) async throws -> EmptySuccess { throw unimplemented }
  func restoreMedia(fileID: String) async throws -> EmptySuccess { throw unimplemented }
  func purgeMedia(fileID: String) async throws -> EmptySuccess { throw unimplemented }
  func createWatchRoom( conversationID: String, mediaID: String?, source: WatchSource?, title: String?, emoji: String?, settings: WatchSettingsPatch?, resumeFromRoomID: String? ) async throws -> WatchRoom { throw unimplemented }
  func watchRoom(roomID: String) async throws -> WatchRoom { throw unimplemented }
  func activeWatchRoom(conversationID: String) async throws -> WatchRoom { throw unimplemented }
  func joinWatchRoom(roomID: String) async throws -> WatchRoom { throw unimplemented }
  func leaveWatchRoom(roomID: String) async throws -> EmptySuccess { throw unimplemented }
  func sendWatchSignal( roomID: String, type: String, payload: JSONValue ) async throws -> WatchSignalResponse { throw unimplemented }
  func watchRoomState(roomID: String) async throws -> WatchCanonicalState { throw unimplemented }
  func updateWatchSettings( roomID: String, patch: WatchSettingsPatch ) async throws -> EmptySuccess { throw unimplemented }
  func updateWatchRoomMeta( roomID: String, title: String?, emoji: String? ) async throws -> EmptySuccess { throw unimplemented }
  func replaceWatchQueue(roomID: String, mediaIDs: [String]) async throws -> EmptySuccess { throw unimplemented }
  func addWatchQueueItem(roomID: String, mediaID: String) async throws -> EmptySuccess { throw unimplemented }
  func removeWatchQueueItem(roomID: String, index: Int) async throws -> EmptySuccess { throw unimplemented }
  func setWatchParticipantRole( roomID: String, userID: String, role: String ) async throws -> EmptySuccess { throw unimplemented }
  func kickWatchParticipant(roomID: String, userID: String) async throws -> EmptySuccess { throw unimplemented }
  func transferWatchHost(roomID: String, userID: String) async throws -> EmptySuccess { throw unimplemented }
  func endWatchRoom(roomID: String) async throws -> EmptySuccess { throw unimplemented }
  func watchHistory(conversationID: String, limit: Int) async throws -> [WatchHistoryEntry] { throw unimplemented }
  func createWatchGuestLink( roomID: String, expiresInHours: Int?, maxUses: Int? ) async throws -> WatchGuestLink { throw unimplemented }
  func watchGuestLinks(roomID: String) async throws -> [WatchGuestLink] { throw unimplemented }
  func revokeWatchGuestLink(linkID: String) async throws -> EmptySuccess { throw unimplemented }
  func createWatchScheduled( conversationID: String, scheduledAt: String, title: String?, emoji: String?, mediaID: String?, source: WatchSource? ) async throws -> WatchScheduledEntry { throw unimplemented }
  func watchScheduled(conversationID: String) async throws -> [WatchScheduledEntry] { throw unimplemented }
  func deleteWatchScheduled(id: String) async throws -> EmptySuccess { throw unimplemented }

  func profile() async throws -> MobileProfileResponse { throw unimplemented }
  func updateProfile(_ patch: ProfileUpdateRequest) async throws -> MobileProfileResponse {
    throw unimplemented
  }
  func uploadProfileImage(fileURL: URL, kind: ProfileImageKind) async throws -> URL {
    throw unimplemented
  }
  func chats() async throws -> MobileChatListResponse { throw unimplemented }
  func realtimeTicket() async throws -> MaxV2RealtimeTicket { throw unimplemented }
  func messages(
    chatID: String,
    limit: Int,
    before: String?
  ) async throws -> MobileMessagesResponse { throw unimplemented }
  func sendMessage(
    chatID: String,
    caption: String,
    mediaFileIDs: [String],
    replyToID: String?
  ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func editMessage(
    chatID: String,
    messageID: String,
    content: String
  ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func deleteMessage(
    chatID: String,
    messageID: String
  ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func setMessagePinned(
    chatID: String,
    messageID: String,
    isPinned: Bool
  ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func forwardMessage(
    chatID: String,
    messageID: String,
    targetChatID: String
  ) async throws -> MobileMessageSendResponse { throw unimplemented }
  func markChatRead(chatID: String) async throws -> EmptySuccess { throw unimplemented }
  func ratings(fileID: String) async throws -> MobileRatingsResponse {
    MobileRatingsResponse(success: true, subjects: subjects)
  }
  func ratedMedia() async throws -> MobileRatedMediaResponse { throw unimplemented }
  func setRating(
    fileID: String,
    targetUserID: String,
    score: Int
  ) async throws -> MobileRatingMutationResponse {
    setRatingCallCount += 1
    throw ProductContractStubError.ratingRejected
  }
  func saveHistory(fileID: String, position: Double) async throws -> EmptySuccess {
    throw unimplemented
  }
  func setFavorite(fileID: String, favorite: Bool) async throws -> EmptySuccess { throw unimplemented }
  func requestAccess(fileID: String, messageID: String?) async throws -> EmptySuccess {
    throw unimplemented
  }
  func accessRequests() async throws -> MobileAccessRequestsResponse { throw unimplemented }
  func decideAccessRequest(
    id: String,
    decision: String
  ) async throws -> MobileAccessDecisionResponse { throw unimplemented }
  func uploadMultipart(
    fileURL: URL,
    mimeType: String,
    spaceID: String?,
    fileName: String?,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> MobileUploadRegisterResponse { throw unimplemented }
  func downloadFile(
    from remoteURL: URL,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> DownloadedTemporaryFile { throw unimplemented }
  func preflightMediaStream(url: URL) async throws { throw unimplemented }

  private var unimplemented: ProductContractStubError { .unimplemented }
}
