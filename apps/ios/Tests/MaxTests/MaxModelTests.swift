import XCTest
@testable import Max

@MainActor
final class MaxModelTests: XCTestCase {
  func testRootNavigationHasExactlyFiveDestinations() {
    XCTAssertEqual(AppTab.allCases.map(\.rawValue), [
      "vault",
      "library",
      "shared",
      "chats",
      "profile",
    ])
  }

  func testMediaQueryBuildsExpectedSearch() {
    var query = MediaQuery()
    query.mode = "browse"
    query.search = "private media"
    query.saved = true

    XCTAssertTrue(query.queryString.contains("mode=browse"))
    XCTAssertTrue(query.queryString.contains("q=private%20media"))
    XCTAssertTrue(query.queryString.contains("saved=1"))
  }

  func testMediaQueryIncludesTruthfulWorkspaceAndCollectionFilters() {
    var query = MediaQuery()
    query.workspaceId = "workspace/one"
    query.collectionId = "collection two"
    query.limit = 500
    query.offset = -10

    XCTAssertTrue(query.queryString.contains("workspaceId=workspace/one"))
    XCTAssertTrue(query.queryString.contains("collectionId=collection%20two"))
    XCTAssertTrue(query.queryString.contains("limit=100"))
    XCTAssertTrue(query.queryString.contains("offset=0"))
  }

  func testTransferStateActionsMatchLifecycle() {
    XCTAssertTrue(TransferState.queued.isActive)
    XCTAssertTrue(TransferState.uploading.canCancel)
    XCTAssertFalse(TransferState.completed.canCancel)
    XCTAssertTrue(TransferState.failed.canRetry)
    XCTAssertTrue(TransferState.cancelled.canRetry)
  }

  func testDoubleLockMaterialAcceptsOnlyMatchingPIN() throws {
    let material = try DoubleLockHasher.makeMaterial(pin: "2468")

    XCTAssertTrue(DoubleLockHasher.verify(pin: "2468", material: material))
    XCTAssertFalse(DoubleLockHasher.verify(pin: "1357", material: material))
  }

  func testConfigurationRejectsCredentialsAndNormalizesOrigin() throws {
    XCTAssertNil(MaxConfiguration.validHTTPURL(from: "https://user:secret@example.com"))
    XCTAssertNil(MaxConfiguration.validHTTPURL(from: "http://example.com"))
    XCTAssertNotNil(MaxConfiguration.validHTTPURL(from: "http://127.0.0.1:8080"))
    XCTAssertNil(MaxConfiguration.validWebSocketURL(from: "ws://example.com"))
    XCTAssertNotNil(MaxConfiguration.validWebSocketURL(from: "ws://localhost:8080"))

    let normalized = MaxConfiguration.validHTTPURL(
      from: "HTTPS://Example.COM/path?token=secret"
    )
    XCTAssertEqual(normalized?.absoluteString, "https://example.com")
  }

  func testConfigurationHonorsTheServerAddressTheUserSaved() {
    let suiteName = "MaxModelTests.saved-server.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("https://example-tunnel.trycloudflare.com", forKey: "vault_baseURL")

    let configuration = MaxConfiguration.fromBundle(
      defaults: defaults,
      bundle: Bundle(for: MaxModelTests.self)
    )

    // The address the user typed wins verbatim, tunnel or not, and the realtime
    // origin is derived from it rather than from a bundled default.
    XCTAssertEqual(
      configuration.baseURL.absoluteString,
      "https://example-tunnel.trycloudflare.com"
    )
    XCTAssertEqual(
      configuration.websocketURL?.absoluteString,
      "wss://example-tunnel.trycloudflare.com"
    )
  }

  func testConfigurationFallsBackToAStableOriginWhenNothingUsableIsSaved() {
    let suiteName = "MaxModelTests.unusable-server.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("ftp://example.com", forKey: "vault_baseURL")

    let configuration = MaxConfiguration.fromBundle(
      defaults: defaults,
      bundle: Bundle(for: MaxModelTests.self)
    )

    XCTAssertEqual(configuration.baseURL.absoluteString, "https://archivedata.shop")
    XCTAssertFalse(configuration.baseURL.absoluteString.hasSuffix(".trycloudflare.com"))
  }

  func testBackendHostAllowlistFollowsTheConfiguredOrigin() {
    let baseURL = URL(string: "https://media.example.com")!

    XCTAssertTrue(MaxConfiguration.isBackendHost("media.example.com", baseURL: baseURL))
    XCTAssertTrue(MaxConfiguration.isBackendHost("MEDIA.EXAMPLE.COM", baseURL: baseURL))
    XCTAssertTrue(MaxConfiguration.isBackendHost("127.0.0.1", baseURL: baseURL))
    XCTAssertTrue(MaxConfiguration.isBackendHost("localhost", baseURL: baseURL))
    XCTAssertFalse(MaxConfiguration.isBackendHost("attacker.example.net", baseURL: baseURL))
    XCTAssertFalse(MaxConfiguration.isBackendHost(nil, baseURL: baseURL))
    XCTAssertFalse(MaxConfiguration.isBackendHost("", baseURL: baseURL))
  }

  func testPreferenceEnumsExposeEveryProductionChoice() {
    XCTAssertEqual(
      AppTheme.allCases.map(\.rawValue),
      ["light", "dark", "max", "spectrum", "clouds", "council", "daydream"]
    )
    XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["system", "en", "ar", "ru"])
    XCTAssertEqual(
      DownloadNetworkPreference.allCases.map(\.rawValue),
      ["wifiOnly", "wifiAndCellular"]
    )
  }

  func testFreshInstallDefaultsToMaxAndPersistsEveryTheme() {
    let suiteName = "MaxModelTests.theme.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = AppPreferencesStore(defaults: defaults)
    XCTAssertEqual(store.theme, .max)

    for theme in AppTheme.allCases {
      store.theme = theme
      XCTAssertEqual(AppPreferencesStore(defaults: defaults).theme, theme)
    }
  }

  func testLegacySystemThemeMigratesToMax() {
    let suiteName = "MaxModelTests.legacy-theme.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("system", forKey: "app.max.preferences.appearance")

    let store = AppPreferencesStore(defaults: defaults)

    XCTAssertEqual(store.theme, .max)
    XCTAssertEqual(defaults.string(forKey: "app.max.preferences.appearance"), "max")
  }

  func testThemeResolutionForcesNeutralModesAndLetsMaxFollowSystem() {
    XCTAssertEqual(AppTheme.light.forcedColorScheme, .light)
    XCTAssertEqual(AppTheme.dark.forcedColorScheme, .dark)
    XCTAssertNil(AppTheme.max.forcedColorScheme)
    XCTAssertNil(AppTheme.spectrum.forcedColorScheme)
    XCTAssertEqual(AppTheme.clouds.forcedColorScheme, .light)
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .light, systemColorScheme: .dark).variant,
      .neutralLight
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .dark, systemColorScheme: .light).variant,
      .neutralDark
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .max, systemColorScheme: .light).variant,
      .maxLight
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .max, systemColorScheme: .dark).variant,
      .maxDark
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .spectrum, systemColorScheme: .light).variant,
      .spectrumLight
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .spectrum, systemColorScheme: .dark).variant,
      .spectrumDark
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .clouds, systemColorScheme: .dark).variant,
      .clouds
    )
    XCTAssertNil(AppTheme.daydream.forcedColorScheme)
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .daydream, systemColorScheme: .light).variant,
      .daydreamLight
    )
    XCTAssertEqual(
      MaxThemePalette.resolve(theme: .daydream, systemColorScheme: .dark).variant,
      .daydreamDark
    )
  }

  func testMediaDisplayNameHidesTheFileSystemWithoutManglingRealTitles() {
    XCTAssertEqual("IMG_4312.MOV".asMediaDisplayName, "IMG 4312")
    XCTAssertEqual("beach-clip-final.mp4".asMediaDisplayName, "beach clip final")
    XCTAssertEqual("أضواء المساء".asMediaDisplayName, "أضواء المساء")

    // A version number is not a file extension, and a title that is nothing but
    // an extension has to survive intact rather than render as an empty row.
    XCTAssertEqual("Take 2.0".asMediaDisplayName, "Take 2.0")
    XCTAssertEqual("Aurora Passage".asMediaDisplayName, "Aurora Passage")
    XCTAssertEqual(".mp4".asMediaDisplayName, ".mp4")
  }

  func testTogglingAFavoriteKeepsTheDimensionsTheMasonryLaysOutFrom() {
    let item = MaxMediaItem(
      id: "media-1",
      title: "Portrait clip.mov",
      kind: "video",
      sizeBytes: 1_024,
      duration: 12,
      mediaUrl: nil,
      thumbnailUrl: nil,
      videoThumbnailUrl: nil,
      uploader: .init(id: "u1", name: "Owner", avatarUrl: nil),
      workspace: nil,
      uploadedAt: nil,
      rating: nil,
      isFavorite: false,
      isSaved: false,
      lastPosition: 0,
      lastViewedAt: nil,
      isPrivate: false,
      downloadable: true,
      width: 1_080,
      height: 1_920
    )

    let liked = item.withFavorite(true)

    XCTAssertTrue(liked.isFavorite)
    XCTAssertEqual(liked.width, 1_080)
    XCTAssertEqual(liked.height, 1_920)
    XCTAssertEqual(liked.aspectRatio, item.aspectRatio)
  }

  func testMarkingAThreadReadClearsOnlyTheBadge() {
    let thread = ChatThread(
      id: "thread-1",
      title: "Team",
      isGroup: true,
      ownerId: "u1",
      partnerId: nil,
      avatarUrl: nil,
      lastMessage: "Latest",
      lastMessageAt: "2026-08-01T10:00:00Z",
      unreadCount: 4,
      isMuted: true,
      isArchived: false,
      mutedUntil: "2026-08-02T10:00:00Z"
    )

    let read = thread.markingRead()

    XCTAssertEqual(read.unreadCount, 0)
    XCTAssertEqual(read.id, thread.id)
    XCTAssertEqual(read.lastMessage, thread.lastMessage)
    XCTAssertEqual(read.isMuted, thread.isMuted)
    XCTAssertEqual(read.mutedUntil, thread.mutedUntil)
  }
}
