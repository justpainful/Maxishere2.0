import XCTest
@testable import MaxMac

final class MaxMacTests: XCTestCase {
  @MainActor
  func testPublicMacClientCoversEveryIPhoneRootDestination() {
    XCTAssertEqual(
      Array(SidebarDestination.allCases.prefix(5)),
      [.vault, .library, .shared, .chats, .profile]
    )
  }

  @MainActor
  func testDemoFixturesExerciseCoreProductStates() {
    let model = MaxDesktopModel(environment: [
      "MAX_MAC_UI_TESTING": "1",
      "MAX_MAC_UI_TEST_AUTHENTICATED": "1",
    ])

    XCTAssertTrue(model.isAuthenticated)
    XCTAssertTrue(model.media.contains(where: { $0.kind == .video }))
    XCTAssertTrue(model.media.contains(where: { $0.kind == .image }))
    XCTAssertTrue(model.media.contains(where: { $0.isSaved }))
    XCTAssertTrue(model.media.contains(where: { $0.isOffline }))
    XCTAssertTrue(model.media.contains(where: { $0.isTrashed }))
    XCTAssertTrue(model.media.contains(where: { $0.ownRating != nil && $0.partnerRating != nil }))
    XCTAssertFalse(model.workspaces.isEmpty)
    XCTAssertFalse(model.threads.isEmpty)
    XCTAssertFalse(model.memories.isEmpty)
    XCTAssertFalse(model.plugins.isEmpty)
  }

  @MainActor
  func testLibraryMutationsStayConsistent() {
    let model = MaxDesktopModel(environment: ["MAX_MAC_UI_TESTING": "1"])
    let item = try! XCTUnwrap(model.media.first(where: { !$0.isTrashed }))
    let originalSaved = item.isSaved
    let originalOffline = item.isOffline

    model.toggleSaved(item.id)
    model.toggleOffline(item.id)

    let updated = try! XCTUnwrap(model.media.first(where: { $0.id == item.id }))
    XCTAssertEqual(updated.isSaved, !originalSaved)
    XCTAssertEqual(updated.isOffline, !originalOffline)
  }

  @MainActor
  func testChatComposerAppendsToSelectedThread() {
    let model = MaxDesktopModel(environment: ["MAX_MAC_UI_TESTING": "1"])
    let initialCount = model.activeThread?.messages.count
    model.sendMessage("Tahoe UI test message")
    XCTAssertEqual(model.activeThread?.messages.count, initialCount.map { $0 + 1 })
    XCTAssertEqual(model.activeThread?.messages.last?.body, "Tahoe UI test message")
  }

  func testEveryThemeHasAStablePersistedIdentity() {
    XCTAssertEqual(Set(AppTheme.allCases.map(\.rawValue)).count, AppTheme.allCases.count)
    XCTAssertEqual(AppTheme.allCases.count, 6)
  }
}

