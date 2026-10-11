import XCTest
@testable import Max

@MainActor
final class ReleaseAnnouncementStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "ReleaseAnnouncementStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testLoggedOutLaunchPresentsLongMobileIntro() {
    let store = ReleaseAnnouncementStore(
      announcements: [.mobileLaunch(presentationStyle: .longLaunch)],
      defaults: defaults,
      currentBuild: 1
    )

    store.evaluateLaunch(isAuthenticated: false, userDisplayName: nil)

    XCTAssertEqual(store.activeAnnouncement?.id, ReleaseAnnouncement.mobileLaunchID)
    XCTAssertEqual(store.activeAnnouncement?.presentationStyle, .longLaunch)
  }

  func testSeenAnnouncementDoesNotRepeatAcrossStoreInstances() {
    let firstStore = ReleaseAnnouncementStore(
      announcements: [.mobileLaunch(presentationStyle: .longLaunch)],
      defaults: defaults,
      currentBuild: 1
    )
    firstStore.evaluateLaunch(isAuthenticated: false, userDisplayName: nil)
    firstStore.dismissActiveAnnouncement(markSeen: true)

    let secondStore = ReleaseAnnouncementStore(
      announcements: [.mobileLaunch(presentationStyle: .longLaunch)],
      defaults: defaults,
      currentBuild: 1
    )
    secondStore.evaluateLaunch(isAuthenticated: false, userDisplayName: nil)

    XCTAssertNil(secondStore.activeAnnouncement)
  }

  func testBadgeClearsWhenDestinationIsVisited() {
    let releaseDate = Date(timeIntervalSince1970: 1_782_768_000)
    let store = ReleaseAnnouncementStore(
      announcements: [.memories(releaseDate: releaseDate)],
      defaults: defaults,
      currentBuild: 1
    )
    let insideBadgeWindow = releaseDate.addingTimeInterval(60)

    XCTAssertTrue(store.shouldShowBadge(for: .memories, now: insideBadgeWindow))

    store.markDestinationVisited(.memories)

    XCTAssertFalse(store.shouldShowBadge(for: .memories, now: insideBadgeWindow))
  }
}
