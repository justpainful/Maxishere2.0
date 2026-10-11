import Foundation
import Observation
import SwiftUI

private enum ReleaseAnnouncementStorageKey {
  static let seenAnnouncementIDs = "max.releaseExperience.seenAnnouncementIDs"
  static let visitedDestinationIDs = "max.releaseExperience.visitedDestinationIDs"
}

@MainActor
@Observable
final class ReleaseAnnouncementStore {
  static let seenAnnouncementIDsKey = ReleaseAnnouncementStorageKey.seenAnnouncementIDs
  static let visitedDestinationIDsKey = ReleaseAnnouncementStorageKey.visitedDestinationIDs

  var announcements: [ReleaseAnnouncement]
  var activeAnnouncement: ReleaseAnnouncement?
  var hasPresentedAnnouncementThisLaunch = false
  var personalDisplayName: String?
  private(set) var storageRevision = 0

  @ObservationIgnored
  @AppStorage(ReleaseAnnouncementStorageKey.seenAnnouncementIDs)
  private var seenAnnouncementIDsRaw = ""

  @ObservationIgnored
  @AppStorage(ReleaseAnnouncementStorageKey.visitedDestinationIDs)
  private var visitedDestinationIDsRaw = ""

  @ObservationIgnored private let currentBuild: Int

  init(
    announcements: [ReleaseAnnouncement] = ReleaseAnnouncement.defaultAnnouncements(),
    defaults: UserDefaults? = .standard,
    currentBuild: Int = ReleaseAnnouncementStore.bundleBuildNumber()
  ) {
    self.announcements = announcements
    self.currentBuild = currentBuild
    _seenAnnouncementIDsRaw = AppStorage(
      wrappedValue: "",
      ReleaseAnnouncementStorageKey.seenAnnouncementIDs,
      store: defaults
    )
    _visitedDestinationIDsRaw = AppStorage(
      wrappedValue: "",
      ReleaseAnnouncementStorageKey.visitedDestinationIDs,
      store: defaults
    )
  }

  var resolvedAnnouncements: [ReleaseAnnouncement] {
    _ = storageRevision
    let seen = seenAnnouncementIDs
    return announcements
      .filter { $0.minimumAppBuild <= currentBuild }
      .map { $0.seen(seen.contains($0.id)) }
  }

  var whatsNewAnnouncements: [ReleaseAnnouncement] {
    resolvedAnnouncements.enumerated().sorted { lhs, rhs in
      let left = lhs.element
      let right = rhs.element
      if left.hasBeenSeen != right.hasBeenSeen {
        return !left.hasBeenSeen && right.hasBeenSeen
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  func evaluateLaunch(isAuthenticated: Bool, userDisplayName: String?) {
    personalDisplayName = userDisplayName
    presentNextAnnouncement(isAuthenticated: isAuthenticated)
  }

  func evaluateAfterAuthentication(userDisplayName: String?) {
    personalDisplayName = userDisplayName
    presentNextAnnouncement(isAuthenticated: true)
  }

  func dismissActiveAnnouncement(markSeen: Bool = true) {
    guard let announcement = activeAnnouncement else { return }
    if markSeen {
      self.markSeen(announcement)
    }
    activeAnnouncement = nil
  }

  func markSeen(_ announcement: ReleaseAnnouncement) {
    var ids = seenAnnouncementIDs
    ids.insert(announcement.id)
    saveSeenAnnouncementIDs(ids)
  }

  func markDestinationVisited(_ destination: ReleaseDestination) {
    var destinations = visitedDestinationIDs
    destinations.insert(destination.rawValue)
    saveVisitedDestinationIDs(destinations)
  }

  func shouldShowBadge(for destination: ReleaseDestination, now: Date = Date()) -> Bool {
    _ = storageRevision
    guard !visitedDestinationIDs.contains(destination.rawValue) else { return false }
    return resolvedAnnouncements.contains { announcement in
      announcement.destination == destination &&
        announcement.showBadgeUntil.map { now <= $0 } == true
    }
  }

  func announcement(withID id: String) -> ReleaseAnnouncement? {
    resolvedAnnouncements.first { $0.id == id }
  }

  private func presentNextAnnouncement(isAuthenticated: Bool) {
    guard !hasPresentedAnnouncementThisLaunch, activeAnnouncement == nil else { return }
    guard let announcement = nextAnnouncement(isAuthenticated: isAuthenticated) else { return }
    activeAnnouncement = announcement
    hasPresentedAnnouncementThisLaunch = true
  }

  private func nextAnnouncement(isAuthenticated: Bool) -> ReleaseAnnouncement? {
    let unseen = resolvedAnnouncements.filter { !$0.hasBeenSeen }
    if let mobileLaunch = unseen.first(where: { $0.id == ReleaseAnnouncement.mobileLaunchID }) {
      return mobileLaunch.presented(as: isAuthenticated ? .compactLaunch : .longLaunch)
    }

    guard isAuthenticated else { return nil }
    return unseen.first { $0.destination != .home }
  }

  private var seenAnnouncementIDs: Set<String> {
    decodeSet(seenAnnouncementIDsRaw)
  }

  private var visitedDestinationIDs: Set<String> {
    decodeSet(visitedDestinationIDsRaw)
  }

  private func saveSeenAnnouncementIDs(_ ids: Set<String>) {
    seenAnnouncementIDsRaw = encodeSet(ids)
    storageRevision += 1
  }

  private func saveVisitedDestinationIDs(_ ids: Set<String>) {
    visitedDestinationIDsRaw = encodeSet(ids)
    storageRevision += 1
  }

  private func decodeSet(_ raw: String) -> Set<String> {
    Set(
      raw
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
    )
  }

  private func encodeSet(_ values: Set<String>) -> String {
    values.sorted().joined(separator: "\n")
  }

  private nonisolated static func bundleBuildNumber(bundle: Bundle = .main) -> Int {
    guard
      let raw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let number = Int(raw)
    else {
      return 1
    }
    return number
  }
}
