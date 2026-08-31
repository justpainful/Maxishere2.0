import XCTest
@testable import Max

final class MemoriesModelTests: XCTestCase {
  func testCycleSignatureStaysStableForSameFilter() {
    var filter = MemoryFilter()
    filter.mode = .onThisDay
    filter.mediaSelection = .photosOnly
    filter.curationMode = .smartRandom
    filter.startYear = 2022
    filter.endYear = 2026

    XCTAssertEqual(filter.signature.id, filter.signature.id)
  }

  func testPureRandomOrderingAvoidsViewedItemsUntilCycleEnds() {
    let engine = DefaultMemoryCurationEngine()
    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    let candidates = (0..<4).map { index in
      MemoryCandidate(
        key: MemoryAssetKey(identifier: "file-\(index)"),
        kind: .photo,
        title: "Memory \(index)",
        subtitle: "Max",
        createdAt: baseDate.addingTimeInterval(Double(index) * 3600),
        duration: nil,
        pixelWidth: 1600,
        pixelHeight: 1200,
        isFavorite: index == 0,
        isScreenshot: false,
        isScreenRecording: false,
        localIdentifier: "file-\(index)",
        location: nil,
        recoveryKey: MediaRecoveryKey(
          mediaKind: .photo,
          createdAt: baseDate,
          modifiedAt: nil,
          pixelWidth: 1600,
          pixelHeight: 1200,
          duration: nil,
          burstIdentifier: nil
        )
      )
    }

    var filter = MemoryFilter()
    filter.mode = .randomEntireLibrary
    filter.curationMode = .pureRandom
    let viewed = Set([candidates[0].key, candidates[1].key])
    let ordered = engine.orderedCandidates(from: candidates, filter: filter, viewedKeys: viewed)

    XCTAssertFalse(ordered.prefix(2).contains(where: { viewed.contains($0.key) }))
  }

  func testCurationDropsDuplicateAssetIdentifiers() throws {
    var filter = MemoryFilter()
    filter.mode = .randomEntireLibrary
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let candidate = MemoryCandidate(
      key: MemoryAssetKey(identifier: "duplicate-local-asset"),
      kind: .photo,
      title: "Memory",
      subtitle: "Max",
      createdAt: date,
      duration: nil,
      pixelWidth: 1_600,
      pixelHeight: 1_200,
      isFavorite: false,
      isScreenshot: false,
      isScreenRecording: false,
      localIdentifier: "duplicate-local-asset",
      location: nil,
      recoveryKey: MediaRecoveryKey(
        mediaKind: .photo,
        createdAt: date,
        modifiedAt: nil,
        pixelWidth: 1_600,
        pixelHeight: 1_200,
        duration: nil,
        burstIdentifier: nil
      )
    )

    let ordered = DefaultMemoryCurationEngine().orderedCandidates(
      from: [candidate, candidate],
      filter: filter,
      viewedKeys: []
    )

    XCTAssertEqual(ordered.map(\.key), [candidate.key])
  }
}
