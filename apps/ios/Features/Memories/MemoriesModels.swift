import Foundation
import SwiftUI

enum MemoryMediaKind: String, CaseIterable, Codable, Hashable, Sendable {
  case photo
  case video
  case livePhoto
}

enum MemoryMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case onThisDay
  case thisWeekAcrossYears
  case oneYearAgo
  case twoYearsAgo
  case fiveYearsAgo
  case randomEntireLibrary
  case recentlyRediscovered
  case unseen
  case saved
  case customYearRange

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .onThisDay: "memories.mode.on_this_day"
    case .thisWeekAcrossYears: "memories.mode.this_week"
    case .oneYearAgo: "memories.mode.one_year"
    case .twoYearsAgo: "memories.mode.two_years"
    case .fiveYearsAgo: "memories.mode.five_years"
    case .randomEntireLibrary: "memories.mode.random"
    case .recentlyRediscovered: "memories.mode.rediscovered"
    case .unseen: "memories.mode.unseen"
    case .saved: "memories.mode.saved"
    case .customYearRange: "memories.mode.custom_range"
    }
  }
}

enum MemoryCurationMode: String, CaseIterable, Codable, Hashable, Sendable {
  case smartRandom
  case pureRandom

  var titleKey: LocalizedStringKey {
    switch self {
    case .smartRandom: "memories.curation.smart"
    case .pureRandom: "memories.curation.pure"
    }
  }
}

enum MemoryMediaSelection: String, CaseIterable, Codable, Hashable, Sendable {
  case allMedia
  case photosOnly
  case videosOnly

  var titleKey: LocalizedStringKey {
    switch self {
    case .allMedia: "memories.filter.media.all"
    case .photosOnly: "memories.filter.media.photos"
    case .videosOnly: "memories.filter.media.videos"
    }
  }
}

enum MemoryPhotoAuthorizationStatus: String, Codable, Hashable, Sendable {
  case notDetermined
  case authorized
  case limited
  case denied
  case restricted

  var titleKey: LocalizedStringKey {
    switch self {
    case .notDetermined: "memories.permission.status.not_determined"
    case .authorized: "memories.permission.status.full"
    case .limited: "memories.permission.status.limited"
    case .denied: "memories.permission.status.denied"
    case .restricted: "memories.permission.status.restricted"
    }
  }

  var canReadLibrary: Bool {
    self == .authorized || self == .limited
  }
}

enum MemoryLibraryLayout: String, CaseIterable, Identifiable, Sendable {
  case highlights
  case timeline
  case places

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .highlights: "memories.layout.highlights"
    case .timeline: "memories.layout.timeline"
    case .places: "memories.layout.places"
    }
  }

  var systemName: String {
    switch self {
    case .highlights: "square.grid.2x2"
    case .timeline: "calendar.day.timeline.left"
    case .places: "map"
    }
  }
}

enum MemoryCollectionScope: String, CaseIterable, Identifiable, Sendable {
  case all
  case saved
  case hidden

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .all: "memories.collection.all"
    case .saved: "memories.saved"
    case .hidden: "memories.hidden"
    }
  }
}

struct MemoryAssetKey: Hashable, Codable, Identifiable, Sendable {
  let identifier: String

  var id: String { identifier }
}

struct MemoryFilter: Codable, Hashable, Sendable {
  var mode: MemoryMode = .thisWeekAcrossYears
  var mediaSelection: MemoryMediaSelection = .allMedia
  var curationMode: MemoryCurationMode = .smartRandom
  var includeScreenshots = false
  var includeScreenRecordings = false
  var startYear: Int?
  var endYear: Int?

  var signature: MemoryCycleSignature {
    MemoryCycleSignature(
      mode: mode,
      mediaSelection: mediaSelection,
      curationMode: curationMode,
      includeScreenshots: includeScreenshots,
      includeScreenRecordings: includeScreenRecordings,
      startYear: startYear,
      endYear: endYear
    )
  }

  mutating func normalizeYearRange() {
    guard let startYear, let endYear, startYear > endYear else { return }
    self.startYear = endYear
    self.endYear = startYear
  }
}

struct MemoryCycleSignature: Codable, Hashable, Identifiable, Sendable {
  let mode: MemoryMode
  let mediaSelection: MemoryMediaSelection
  let curationMode: MemoryCurationMode
  let includeScreenshots: Bool
  let includeScreenRecordings: Bool
  let startYear: Int?
  let endYear: Int?

  var id: String {
    [
      mode.rawValue,
      mediaSelection.rawValue,
      curationMode.rawValue,
      includeScreenshots ? "screenshots-on" : "screenshots-off",
      includeScreenRecordings ? "recordings-on" : "recordings-off",
      startYear.map(String.init) ?? "min",
      endYear.map(String.init) ?? "max",
    ].joined(separator: "|")
  }
}

struct MediaRecoveryKey: Codable, Hashable, Sendable {
  let mediaKind: MemoryMediaKind
  let createdAt: Date?
  let modifiedAt: Date?
  let pixelWidth: Int
  let pixelHeight: Int
  let duration: Double?
  let burstIdentifier: String?
}

struct MemoryLocation: Codable, Hashable, Sendable {
  let latitude: Double
  let longitude: Double

  var regionKey: String {
    let latitudeBand = (latitude * 10).rounded() / 10
    let longitudeBand = (longitude * 10).rounded() / 10
    return "\(latitudeBand),\(longitudeBand)"
  }

  var coordinateLabel: String {
    String(format: "%.2f, %.2f", latitude, longitude)
  }
}

struct MemoryCycleState: Codable, Hashable, Sendable {
  let signature: MemoryCycleSignature
  var orderedKeys: [MemoryAssetKey]
  var viewedKeys: Set<MemoryAssetKey>
}

struct MemoryCandidate: Identifiable, Hashable, Codable, Sendable {
  let key: MemoryAssetKey
  let kind: MemoryMediaKind
  let title: String
  let subtitle: String
  let createdAt: Date
  let duration: Double?
  let pixelWidth: Int
  let pixelHeight: Int
  let isFavorite: Bool
  let isScreenshot: Bool
  let isScreenRecording: Bool
  let localIdentifier: String
  let location: MemoryLocation?
  let recoveryKey: MediaRecoveryKey

  var id: String { key.id }
  var year: Int { Calendar.current.component(.year, from: createdAt) }
  var dayKey: String { DateFormatter.memoriesDayKey.string(from: createdAt) }
  var monthKey: String { DateFormatter.memoriesMonthKey.string(from: createdAt) }
  var sortCluster: String { DateFormatter.memoriesCluster.string(from: createdAt) }
  var aspectRatio: CGFloat {
    guard pixelHeight > 0 else { return 1 }
    return CGFloat(pixelWidth) / CGFloat(pixelHeight)
  }

  func matches(filter: MemoryFilter, now: Date = Date()) -> Bool {
    if filter.mediaSelection == .photosOnly, kind == .video { return false }
    if filter.mediaSelection == .videosOnly, kind != .video { return false }
    if isScreenshot, !filter.includeScreenshots { return false }
    if isScreenRecording, !filter.includeScreenRecordings { return false }
    if let startYear = filter.startYear, year < startYear { return false }
    if let endYear = filter.endYear, year > endYear { return false }

    let calendar = Calendar.current
    switch filter.mode {
    case .onThisDay:
      let current = calendar.dateComponents([.month, .day], from: now)
      let memory = calendar.dateComponents([.month, .day], from: createdAt)
      return current.month == memory.month && current.day == memory.day
    case .thisWeekAcrossYears:
      return calendar.component(.weekOfYear, from: now)
        == calendar.component(.weekOfYear, from: createdAt)
    case .oneYearAgo:
      return isFromYear(yearsAgo: 1, now: now, calendar: calendar)
    case .twoYearsAgo:
      return isFromYear(yearsAgo: 2, now: now, calendar: calendar)
    case .fiveYearsAgo:
      return isFromYear(yearsAgo: 5, now: now, calendar: calendar)
    case .customYearRange, .randomEntireLibrary, .recentlyRediscovered, .unseen, .saved:
      return true
    }
  }

  private func isFromYear(
    yearsAgo: Int,
    now: Date,
    calendar: Calendar
  ) -> Bool {
    let current = calendar.dateComponents([.year], from: now)
    let memory = calendar.dateComponents([.year], from: createdAt)
    return memory.year == current.year.map { $0 - yearsAgo }
  }
}

struct MemoryIndexSnapshot: Codable, Sendable {
  let schemaVersion: Int
  let generatedAt: Date
  let candidates: [MemoryCandidate]

  init(generatedAt: Date = Date(), candidates: [MemoryCandidate]) {
    self.schemaVersion = 1
    self.generatedAt = generatedAt
    self.candidates = candidates
  }
}

struct MemoryStorageMetrics: Equatable, Sendable {
  var indexedAssetCount = 0
  var thumbnailCacheBytes: Int64 = 0
  var lastIndexedAt: Date?
}

struct MemoriesLocalState: Codable, Sendable {
  var selectedFilter = MemoryFilter()
  var savedKeys: Set<MemoryAssetKey> = []
  var hiddenKeys: Set<MemoryAssetKey> = []
  var excludedKeys: Set<MemoryAssetKey> = []
  var excludedDateKeys: Set<String> = []
  var viewedAt: [MemoryAssetKey: Date] = [:]
  var cycleStates: [String: MemoryCycleState] = [:]
  var lastSelectedKey: MemoryAssetKey?
  var hasOpenedFeature = false
  var muteEnabled = true
  var prefetchEnabled = true
  var calmMotionEnabled = false

  private enum CodingKeys: String, CodingKey {
    case selectedFilter
    case savedKeys
    case hiddenKeys
    case excludedKeys
    case excludedDateKeys
    case viewedAt
    case cycleStates
    case lastSelectedKey
    case hasOpenedFeature
    case muteEnabled
    case prefetchEnabled
    case calmMotionEnabled
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    selectedFilter = try values.decodeIfPresent(MemoryFilter.self, forKey: .selectedFilter)
      ?? MemoryFilter()
    savedKeys = try values.decodeIfPresent(Set<MemoryAssetKey>.self, forKey: .savedKeys) ?? []
    hiddenKeys = try values.decodeIfPresent(Set<MemoryAssetKey>.self, forKey: .hiddenKeys) ?? []
    excludedKeys = try values.decodeIfPresent(Set<MemoryAssetKey>.self, forKey: .excludedKeys)
      ?? []
    excludedDateKeys = try values.decodeIfPresent(Set<String>.self, forKey: .excludedDateKeys)
      ?? []
    viewedAt = try values.decodeIfPresent([MemoryAssetKey: Date].self, forKey: .viewedAt) ?? [:]
    cycleStates = try values.decodeIfPresent(
      [String: MemoryCycleState].self,
      forKey: .cycleStates
    ) ?? [:]
    lastSelectedKey = try values.decodeIfPresent(
      MemoryAssetKey.self,
      forKey: .lastSelectedKey
    )
    hasOpenedFeature = try values.decodeIfPresent(Bool.self, forKey: .hasOpenedFeature) ?? false
    muteEnabled = try values.decodeIfPresent(Bool.self, forKey: .muteEnabled) ?? true
    prefetchEnabled = try values.decodeIfPresent(Bool.self, forKey: .prefetchEnabled) ?? true
    calmMotionEnabled = try values.decodeIfPresent(Bool.self, forKey: .calmMotionEnabled)
      ?? false
  }
}

protocol MemoryCurationScoring {
  func orderedCandidates(
    from candidates: [MemoryCandidate],
    filter: MemoryFilter,
    viewedKeys: Set<MemoryAssetKey>
  ) -> [MemoryCandidate]
}

struct DefaultMemoryCurationEngine: MemoryCurationScoring {
  func orderedCandidates(
    from candidates: [MemoryCandidate],
    filter: MemoryFilter,
    viewedKeys: Set<MemoryAssetKey>
  ) -> [MemoryCandidate] {
    var seen = Set<MemoryAssetKey>()
    let eligible = candidates.filter {
      seen.insert($0.key).inserted && $0.matches(filter: filter)
    }
    let unseen = eligible.filter { !viewedKeys.contains($0.key) }
    let pool = unseen.isEmpty ? eligible : unseen

    switch filter.curationMode {
    case .pureRandom:
      return stableShuffle(pool, seed: filter.signature.id)
    case .smartRandom:
      return stableSmartOrder(pool, seed: filter.signature.id)
    }
  }

  private func stableSmartOrder(
    _ candidates: [MemoryCandidate],
    seed: String
  ) -> [MemoryCandidate] {
    let grouped = Dictionary(grouping: candidates, by: \.sortCluster)
    let representatives = grouped.values.compactMap { cluster -> MemoryCandidate? in
      cluster.max { lhs, rhs in smartScore(for: lhs) < smartScore(for: rhs) }
    }
    return representatives.sorted { lhs, rhs in
      let leftScore = smartScore(for: lhs)
      let rightScore = smartScore(for: rhs)
      if leftScore != rightScore { return leftScore > rightScore }
      let leftWeight = stableWeight(for: lhs.id, seed: seed)
      let rightWeight = stableWeight(for: rhs.id, seed: seed)
      if leftWeight != rightWeight { return leftWeight < rightWeight }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
      return lhs.id < rhs.id
    }
  }

  private func smartScore(for candidate: MemoryCandidate) -> Double {
    let resolution = Double(candidate.pixelWidth * candidate.pixelHeight) / 1_000_000
    let favorite = candidate.isFavorite ? 2.4 : 0
    // Smart memories should surface downloaded video moments first. Photos
    // remain available through the explicit Photos filter, but no longer win
    // merely because they have a larger pixel count.
    let mediaPreference: Double = candidate.kind == .video ? 5.0 : 0
    let liveBonus = candidate.kind == .livePhoto ? 0.5 : 0
    let durationPenalty = candidate.kind == .video && (candidate.duration ?? 0) > 180 ? 0.6 : 0
    return mediaPreference + resolution * 0.35 + favorite + liveBonus - durationPenalty
  }

  private func stableShuffle(_ candidates: [MemoryCandidate], seed: String) -> [MemoryCandidate] {
    candidates.sorted { lhs, rhs in
      let leftWeight = stableWeight(for: lhs.id, seed: seed)
      let rightWeight = stableWeight(for: rhs.id, seed: seed)
      if leftWeight != rightWeight { return leftWeight < rightWeight }
      return lhs.id < rhs.id
    }
  }

  private func stableWeight(for value: String, seed: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    for byte in seed.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }
    hash ^= 0xFF
    hash &*= prime
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }
    return hash
  }
}

extension DateFormatter {
  static let memoriesPrimary: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static let memoriesSecondary: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  static let memoriesMonthTitle: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return formatter
  }()

  fileprivate static let memoriesDayKey: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  fileprivate static let memoriesMonthKey: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM"
    return formatter
  }()

  fileprivate static let memoriesCluster: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd-HH"
    return formatter
  }()
}
