@preconcurrency import AVFoundation
import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class MemoriesStore {
  private let deviceClient: DevicePhotoLibraryClient
  private let curation: MemoryCurationScoring
  private let stateStore: MemoryCycleStore

  var filter: MemoryFilter
  var authorizationStatus: MemoryPhotoAuthorizationStatus
  var isLoading = false
  var isIndexing = false
  var hasLoaded = false
  var errorMessageKey: String?
  var allCandidates: [MemoryCandidate] = []
  var currentSequence: [MemoryCandidate] = []
  var selectedCandidateKey: MemoryAssetKey?
  var showingViewer = false
  var showingSettings = false
  var startedFromHome = false
  var libraryLayout: MemoryLibraryLayout = .highlights
  var collectionScope: MemoryCollectionScope = .all
  var savedKeys: Set<MemoryAssetKey>
  var hiddenKeys: Set<MemoryAssetKey>
  var excludedKeys: Set<MemoryAssetKey>
  var excludedDateKeys: Set<String>
  var viewedAt: [MemoryAssetKey: Date]
  var hasOpenedFeature: Bool
  var muted: Bool
  var prefetchEnabled: Bool
  var calmMotionEnabled: Bool
  var storageMetrics: MemoryStorageMetrics

  private var cycleStates: [String: MemoryCycleState]

  init(
    deviceClient: DevicePhotoLibraryClient,
    curation: MemoryCurationScoring = DefaultMemoryCurationEngine(),
    stateStore: MemoryCycleStore = AppMemoryCycleStore()
  ) {
    self.deviceClient = deviceClient
    self.curation = curation
    self.stateStore = stateStore
    let state = stateStore.loadState()
    filter = state.selectedFilter
    savedKeys = state.savedKeys
    hiddenKeys = state.hiddenKeys
    excludedKeys = state.excludedKeys
    excludedDateKeys = state.excludedDateKeys
    viewedAt = state.viewedAt
    cycleStates = state.cycleStates
    hasOpenedFeature = state.hasOpenedFeature
    muted = state.muteEnabled
    prefetchEnabled = state.prefetchEnabled
    calmMotionEnabled = state.calmMotionEnabled
    selectedCandidateKey = state.lastSelectedKey
    authorizationStatus = deviceClient.authorizationStatus()
    storageMetrics = deviceClient.storageMetrics()
    deviceClient.startObservingChanges { [weak self] in
      Task { await self?.refreshIndex() }
    }
  }

  var activeCandidate: MemoryCandidate? {
    guard let selectedCandidateKey else { return viewerCandidates.first }
    return viewerCandidates.first(where: { $0.key == selectedCandidateKey })
  }

  var resurfacedCandidate: MemoryCandidate? {
    currentSequence.first
  }

  var visibleCandidates: [MemoryCandidate] {
    currentSequence.filter { !hiddenKeys.contains($0.key) }
  }

  var savedCandidates: [MemoryCandidate] {
    allCandidates
      .filter { savedKeys.contains($0.key) && !hiddenKeys.contains($0.key) }
      .sorted { $0.createdAt > $1.createdAt }
  }

  var hiddenCandidates: [MemoryCandidate] {
    allCandidates
      .filter { hiddenKeys.contains($0.key) }
      .sorted { $0.createdAt > $1.createdAt }
  }

  var collectionCandidates: [MemoryCandidate] {
    switch collectionScope {
    case .all: visibleCandidates
    case .saved: savedCandidates
    case .hidden: hiddenCandidates
    }
  }

  var viewerCandidates: [MemoryCandidate] {
    collectionCandidates
  }

  var availableYears: [Int] {
    Set(allCandidates.map(\.year)).sorted(by: >)
  }

  var cycleCompleted: Bool {
    !currentSequence.isEmpty
      && currentSequence.allSatisfy { currentCycleViewedKeys.contains($0.key) }
  }

  var canPresentOriginalInPhotos: Bool {
    deviceClient.presentsSystemPhotoLibrary
  }

  var timelineGroups: [(id: String, title: String, items: [MemoryCandidate])] {
    let grouped = Dictionary(grouping: collectionCandidates, by: \.monthKey)
    return grouped.compactMap { key, items in
      guard let date = items.first?.createdAt else { return nil }
      return (
        id: key,
        title: DateFormatter.memoriesMonthTitle.string(from: date),
        items: items.sorted { $0.createdAt > $1.createdAt }
      )
    }
    .sorted { $0.id > $1.id }
  }

  var placeGroups: [(id: String, title: String, items: [MemoryCandidate])] {
    let located = collectionCandidates.compactMap { candidate -> (String, MemoryCandidate)? in
      guard let location = candidate.location else { return nil }
      return (location.regionKey, candidate)
    }
    let grouped = Dictionary(grouping: located, by: \.0)
    return grouped.map { key, entries in
      (
        id: key,
        title: entries.first?.1.location?.coordinateLabel ?? key,
        items: entries.map(\.1).sorted { $0.createdAt > $1.createdAt }
      )
    }
    .sorted { lhs, rhs in
      if lhs.items.count != rhs.items.count { return lhs.items.count > rhs.items.count }
      return lhs.id < rhs.id
    }
  }

  func activate() async {
    hasOpenedFeature = true
    persist()
    authorizationStatus = deviceClient.authorizationStatus()
    storageMetrics = deviceClient.storageMetrics()
    guard authorizationStatus.canReadLibrary else { return }

    let cached = deviceClient.cachedCandidates(filter: filter)
    if !cached.isEmpty {
      allCandidates = uniqueCandidates(cached)
      rebuildSequence(forceNewCycle: false)
      hasLoaded = true
    }
    await refreshIndex()
  }

  func requestPhotoAccess() async {
    authorizationStatus = await deviceClient.requestAuthorization()
    if authorizationStatus.canReadLibrary {
      await refreshIndex()
    } else {
      allCandidates = []
      currentSequence = []
      hasLoaded = true
    }
  }

  func resumeAfterSceneActivation() async {
    authorizationStatus = deviceClient.authorizationStatus()
    guard authorizationStatus.canReadLibrary else { return }
    await refreshIndex()
  }

  func refreshIndex() async {
    guard authorizationStatus.canReadLibrary, !isIndexing else { return }
    isLoading = !hasLoaded
    isIndexing = true
    errorMessageKey = nil
    defer {
      isLoading = false
      isIndexing = false
    }
    do {
      allCandidates = uniqueCandidates(
        try await deviceClient.refreshCandidates(filter: filter)
      )
      rebuildSequence(forceNewCycle: false)
      hasLoaded = true
      storageMetrics = deviceClient.storageMetrics()
      persist()
    } catch is CancellationError {
      return
    } catch {
      errorMessageKey = "memories.error.index"
    }
  }

  func applyFilter(_ newFilter: MemoryFilter) {
    var normalized = newFilter
    normalized.normalizeYearRange()
    filter = normalized
    allCandidates = uniqueCandidates(deviceClient.cachedCandidates(filter: filter))
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func selectMode(_ mode: MemoryMode) {
    var updated = filter
    updated.mode = mode
    applyFilter(updated)
  }

  func updatePreferences(
    filter: MemoryFilter,
    muted: Bool,
    prefetchEnabled: Bool,
    calmMotionEnabled: Bool
  ) {
    self.muted = muted
    self.prefetchEnabled = prefetchEnabled
    self.calmMotionEnabled = calmMotionEnabled
    applyFilter(filter)
  }

  func startNewCycle() {
    cycleStates[filter.signature.id] = MemoryCycleState(
      signature: filter.signature,
      orderedKeys: [],
      viewedKeys: []
    )
    rebuildSequence(forceNewCycle: true)
    persist()
  }

  func markViewed(_ candidate: MemoryCandidate) {
    var state = cycleStates[filter.signature.id] ?? MemoryCycleState(
      signature: filter.signature,
      orderedKeys: currentSequence.map(\.key),
      viewedKeys: []
    )
    state.viewedKeys.insert(candidate.key)
    cycleStates[filter.signature.id] = state
    viewedAt[candidate.key] = Date()
    selectedCandidateKey = candidate.key
    persist()
    prefetchNeighbors(around: candidate)
  }

  func toggleSaved(_ candidate: MemoryCandidate) {
    if savedKeys.contains(candidate.key) {
      savedKeys.remove(candidate.key)
    } else {
      savedKeys.insert(candidate.key)
    }
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func hide(_ candidate: MemoryCandidate) {
    advancePast(candidate)
    hiddenKeys.insert(candidate.key)
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func restore(_ candidate: MemoryCandidate) {
    hiddenKeys.remove(candidate.key)
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func doNotShowAgain(_ candidate: MemoryCandidate) {
    excludedKeys.insert(candidate.key)
    advancePast(candidate)
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func excludeDate(of candidate: MemoryCandidate) {
    excludedDateKeys.insert(candidate.dayKey)
    advancePast(candidate)
    rebuildSequence(forceNewCycle: false)
    persist()
  }

  func excludeScreenshots() {
    var updated = filter
    updated.includeScreenshots = false
    applyFilter(updated)
  }

  func excludeScreenRecordings() {
    var updated = filter
    updated.includeScreenRecordings = false
    applyFilter(updated)
  }

  func prepareOpen(candidate: MemoryCandidate? = nil, fromHome: Bool = false) {
    startedFromHome = fromHome
    guard let candidate else {
      showingViewer = false
      selectedCandidateKey = currentSequence.first?.key
      return
    }
    selectedCandidateKey = candidate.key
    showingViewer = true
    markViewed(candidate)
  }

  func openSequence() {
    guard let candidate = collectionCandidates.first ?? currentSequence.first else { return }
    selectedCandidateKey = candidate.key
    showingViewer = true
    markViewed(candidate)
  }

  func dismissViewer() {
    showingViewer = false
    startedFromHome = false
  }

  func toggleMute() {
    muted.toggle()
    persist()
  }

  func thumbnail(localIdentifier: String) async -> UIImage? {
    await deviceClient.thumbnail(
      for: localIdentifier,
      targetSize: CGSize(width: 480, height: 480)
    )
  }

  func image(localIdentifier: String, targetSize: CGSize) async -> UIImage? {
    await deviceClient.image(for: localIdentifier, targetSize: targetSize)
  }

  func livePhoto(localIdentifier: String) async -> PHLivePhoto? {
    await deviceClient.livePhoto(
      for: localIdentifier,
      targetSize: CGSize(width: 1800, height: 1800)
    )
  }

  func avAsset(localIdentifier: String) async -> AVAsset? {
    await deviceClient.avAsset(for: localIdentifier)
  }

  func deviceExportFile(localIdentifier: String) async throws -> URL {
    try await deviceClient.exportAssetFile(for: localIdentifier)
  }

  func clearThumbnailCache() {
    deviceClient.clearThumbnailCache()
    storageMetrics = deviceClient.storageMetrics()
  }

  func resetLocalMemories() async {
    stateStore.resetState()
    deviceClient.resetLocalIndexAndCache()
    let fresh = MemoriesLocalState()
    filter = fresh.selectedFilter
    savedKeys = []
    hiddenKeys = []
    excludedKeys = []
    excludedDateKeys = []
    viewedAt = [:]
    cycleStates = [:]
    hasOpenedFeature = true
    muted = fresh.muteEnabled
    prefetchEnabled = fresh.prefetchEnabled
    calmMotionEnabled = fresh.calmMotionEnabled
    allCandidates = []
    currentSequence = []
    selectedCandidateKey = nil
    hasLoaded = false
    errorMessageKey = nil
    storageMetrics = deviceClient.storageMetrics()
    persist()
    if authorizationStatus.canReadLibrary {
      await refreshIndex()
    }
  }

  private var currentCycleViewedKeys: Set<MemoryAssetKey> {
    cycleStates[filter.signature.id]?.viewedKeys ?? []
  }

  private func eligibleCandidates() -> [MemoryCandidate] {
    var candidates = allCandidates.filter {
      !hiddenKeys.contains($0.key)
        && !excludedKeys.contains($0.key)
        && !excludedDateKeys.contains($0.dayKey)
    }
    switch filter.mode {
    case .saved:
      candidates = candidates.filter { savedKeys.contains($0.key) }
    case .unseen:
      candidates = candidates.filter { viewedAt[$0.key] == nil }
    case .recentlyRediscovered:
      candidates = candidates.filter { viewedAt[$0.key] != nil }
      candidates.sort {
        (viewedAt[$0.key] ?? .distantPast) > (viewedAt[$1.key] ?? .distantPast)
      }
    default:
      break
    }
    return candidates
  }

  private func rebuildSequence(forceNewCycle: Bool) {
    let signature = filter.signature
    let existing = cycleStates[signature.id]
    let viewed = forceNewCycle ? Set<MemoryAssetKey>() : (existing?.viewedKeys ?? [])
    let curated = curation.orderedCandidates(
      from: eligibleCandidates(),
      filter: filter,
      viewedKeys: []
    )

    let ordered: [MemoryCandidate]
    if !forceNewCycle, let existing {
      let candidatesByKey = Dictionary(
        curated.map { ($0.key, $0) },
        uniquingKeysWith: { first, _ in first }
      )
      var includedKeys = Set<MemoryAssetKey>()
      var restored = existing.orderedKeys.compactMap { key -> MemoryCandidate? in
        guard let candidate = candidatesByKey[key], includedKeys.insert(key).inserted else {
          return nil
        }
        return candidate
      }
      restored.append(contentsOf: curated.filter { includedKeys.insert($0.key).inserted })
      ordered = restored
    } else {
      ordered = curated
    }

    cycleStates[signature.id] = MemoryCycleState(
      signature: signature,
      orderedKeys: ordered.map(\.key),
      viewedKeys: viewed
    )
    currentSequence = ordered
    if selectedCandidateKey == nil
      || !ordered.contains(where: { $0.key == selectedCandidateKey }) {
      selectedCandidateKey = ordered.first(where: { !viewed.contains($0.key) })?.key
        ?? ordered.first?.key
    }
  }

  private func uniqueCandidates(_ candidates: [MemoryCandidate]) -> [MemoryCandidate] {
    var seen = Set<MemoryAssetKey>()
    return candidates.filter { seen.insert($0.key).inserted }
  }

  private func advancePast(_ candidate: MemoryCandidate) {
    let candidates = viewerCandidates
    guard let index = candidates.firstIndex(where: { $0.key == candidate.key }) else {
      return
    }
    if candidates.indices.contains(index + 1) {
      selectedCandidateKey = candidates[index + 1].key
    } else if candidates.indices.contains(index - 1) {
      selectedCandidateKey = candidates[index - 1].key
    } else {
      selectedCandidateKey = nil
    }
  }

  private func prefetchNeighbors(around candidate: MemoryCandidate) {
    guard prefetchEnabled,
          let index = viewerCandidates.firstIndex(where: { $0.key == candidate.key }) else {
      return
    }
    let range = max(0, index - 1)...min(viewerCandidates.count - 1, index + 1)
    let identifiers = range
      .filter { $0 != index }
      .map { viewerCandidates[$0].localIdentifier }
    deviceClient.prefetch(
      localIdentifiers: identifiers,
      targetSize: CGSize(width: 960, height: 1280)
    )
  }

  private func persist() {
    var state = MemoriesLocalState()
    state.selectedFilter = filter
    state.savedKeys = savedKeys
    state.hiddenKeys = hiddenKeys
    state.excludedKeys = excludedKeys
    state.excludedDateKeys = excludedDateKeys
    state.viewedAt = viewedAt
    state.cycleStates = cycleStates
    state.lastSelectedKey = selectedCandidateKey
    state.hasOpenedFeature = hasOpenedFeature
    state.muteEnabled = muted
    state.prefetchEnabled = prefetchEnabled
    state.calmMotionEnabled = calmMotionEnabled
    stateStore.saveState(state)
  }
}
