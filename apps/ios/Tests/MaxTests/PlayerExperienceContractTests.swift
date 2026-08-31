import Foundation
import XCTest

final class PlayerExperienceContractTests: XCTestCase {
  func testPrimaryPlayerChromeOmitsFilenameAndStreamingBadges() throws {
    let source = try appSource("Player/MaxPlayerChrome.swift")

    XCTAssertFalse(source.contains("player.streaming"))
    XCTAssertFalse(source.contains("Text(verbatim: item.title)"))
    XCTAssertTrue(source.contains("ui_player_play_pause"))
  }

  func testScrollingPlayerUsesVerticalPagingAndSideActions() throws {
    let source = try appSource("Player/MaxScrollingPlayerView.swift")
    let library = try appSource("Views/LibraryView.swift")

    XCTAssertTrue(source.contains("ScrollView(.vertical)"))
    XCTAssertTrue(
      source.contains(".scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))")
    )
    XCTAssertTrue(source.contains("preferredForwardBufferDuration = 12"))
    XCTAssertTrue(source.contains("ui_scrolling_player_actions"))
    XCTAssertTrue(source.contains("MaxInlinePlayerSurface"))
    XCTAssertTrue(library.contains("ui_library_vertical_feed"))
    XCTAssertTrue(library.contains("MaxScrollingPlayerView("))
    XCTAssertTrue(library.contains("items: verticalFeedItems"))
  }

  func testVaultIsAPaginatedVisualBrowserAndShuffleUsesScrollingPlayer() throws {
    let vault = try appSource("Views/VaultView.swift")

    XCTAssertTrue(vault.contains("LazyVGrid"))
    XCTAssertTrue(vault.contains("loadMoreCatalog"))
    XCTAssertTrue(vault.contains("loadRemainingCatalogPages"))
    XCTAssertTrue(vault.contains("MaxScrollingPlayerView"))
    XCTAssertFalse(vault.contains("prefix(12)"))
    XCTAssertFalse(vault.contains("quickActions"))
  }

  func testThumbnailLoaderCoalescesAndKeepsAuthenticatedMediaOffDisk() throws {
    let loader = try appSource("Design/MaxAsyncImage.swift")
    let models = try appSource("Domain/MaxModels.swift")

    XCTAssertTrue(loader.contains("inFlight"))
    XCTAssertTrue(loader.contains("URLSessionConfiguration.ephemeral"))
    XCTAssertTrue(loader.contains("token == nil"))
    XCTAssertTrue(loader.contains("looksLikeExpiringSignedURL"))
    XCTAssertTrue(models.contains("kind.lowercased() == \"video\""))
  }

  func testEveryIOSVideoSurfaceHasAFrameFallbackForMissingOrExpiredThumbnails() throws {
    let components = try appSource("Views/Components.swift")
    let vault = try appSource("Views/VaultView.swift")
    let chats = try appSource("Views/ChatsView.swift")

    XCTAssertTrue(components.contains("AVAssetImageGenerator"))
    XCTAssertTrue(components.contains("case .failure:\n          videoPosterOrPlaceholder"))
    XCTAssertTrue(components.contains("videoPosterOrPlaceholder"))
    // What matters is that both surfaces route through the poster pipeline, so a
    // video with no server thumbnail still gets a locally generated frame. The
    // argument list is not the contract — pinning it made an unrelated layout
    // change look like a regression.
    XCTAssertTrue(vault.contains("MaxMediaPoster(item: item"))
    XCTAssertTrue(chats.contains("MaxMediaPoster(item: item"))
  }

  func testBothPlayersKeepTheSignedMediaURLForAVFoundation() throws {
    let primary = try appSource("Player/MaxPlayerPlayback.swift")
    let scrolling = try appSource("Player/MaxScrollingPlayerView.swift")

    XCTAssertTrue(primary.contains("let asset = AVURLAsset(url: playbackURL)"))
    XCTAssertTrue(scrolling.contains("let asset = AVURLAsset(url: url)"))
    XCTAssertFalse(primary.contains("AVAssetResourceLoaderDelegate"))
    XCTAssertFalse(scrolling.contains("AVAssetResourceLoaderDelegate"))
  }

  func testPlayerSupportsSequenceErrorsAndPhotoExport() throws {
    let player = try appSource("Player/MaxPlayerView.swift")
    let chrome = try appSource("Player/MaxPlayerChrome.swift")
    let scrolling = try appSource("Player/MaxScrollingPlayerView.swift")
    let exporter = try appSource("Infrastructure/MediaPhotoExporter.swift")

    XCTAssertTrue(chrome.contains("ui_player_previous"))
    XCTAssertTrue(chrome.contains("ui_player_next"))
    XCTAssertTrue(chrome.contains("ui_player_save_to_photos"))
    XCTAssertTrue(player.contains("dismissPlaybackError"))
    XCTAssertTrue(scrolling.contains("ui_scrolling_player_error_dismiss"))
    XCTAssertTrue(exporter.contains("PHPhotoLibrary"))
    XCTAssertTrue(exporter.contains("transferStore.localURL"))
  }

  func testMemoriesVideoValidatesAssetAndPresentsRecoverableFailure() throws {
    let source = try appSource("Features/Memories/MemoriesMediaViews.swift")

    XCTAssertTrue(source.contains("asset.load(.isPlayable)"))
    XCTAssertTrue(source.contains("memories.video.error"))
    XCTAssertTrue(source.contains("memories.video.retry"))
    XCTAssertFalse(source.contains("VideoPlayer(player: player)"))
  }

  private func appSource(_ path: String) throws -> String {
    try String(contentsOf: Self.maxRoot.appendingPathComponent(path), encoding: .utf8)
  }

  private static var maxRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
