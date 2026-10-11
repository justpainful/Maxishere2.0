import Foundation
import XCTest

final class MaxIdentityContractTests: XCTestCase {
  func testProductIdentityNeverUsesAPlaybackRectangle() throws {
    let identitySources = try [
      "Views/EntryExperienceView.swift",
      "Features/ReleaseExperience/ReleaseHeroView.swift",
      "Features/ReleaseExperience/ReleaseFeaturePreview.swift",
    ].map(Self.appSource).joined(separator: "\n")

    XCTAssertTrue(identitySources.contains("MaxIdentityMark"))
    XCTAssertFalse(identitySources.contains("play.rectangle.fill"))
  }

  private static func appSource(_ path: String) throws -> String {
    try String(contentsOf: maxRoot.appendingPathComponent(path), encoding: .utf8)
  }

  private static var maxRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
