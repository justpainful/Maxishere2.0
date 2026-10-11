import Foundation
import Observation

/// A saved query over the loaded catalogue ("videos over 20 minutes I never
/// rated", as a living folder). Purely client-side: the catalogue is already in
/// memory, so a filter is a predicate, not a request. Mirrors the desktop's
/// data/smartFilters.ts.
struct SmartFilter: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var name: String
  /// "all" | "video" | "image" | "audio" — matched against the item's kind.
  var kind: String
  /// Minimum duration in minutes; 0 = any.
  var minMinutes: Int
  var unrated: Bool
  var favoritesOnly: Bool

  func matches(_ item: MaxMediaItem) -> Bool {
    if kind != "all", item.kind.lowercased() != kind { return false }
    if minMinutes > 0, (item.duration ?? 0) < Double(minMinutes) * 60 { return false }
    if unrated, item.rating != nil { return false }
    if favoritesOnly, !(item.isFavorite || item.isSaved) { return false }
    return true
  }
}

/// The saved smart filters, persisted as JSON in UserDefaults. The active
/// selection is deliberately transient — a filter is something you step into
/// and out of, not a mode the app should reopen in.
@MainActor
@Observable
final class SmartFiltersStore {
  private static let storageKey = "max.smartFilters"
  private let defaults: UserDefaults

  private(set) var filters: [SmartFilter]
  var activeID: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.storageKey),
       let saved = try? JSONDecoder().decode([SmartFilter].self, from: data) {
      filters = saved
    } else {
      filters = []
    }
  }

  var activeFilter: SmartFilter? {
    filters.first { $0.id == activeID }
  }

  func toggle(_ id: String) {
    activeID = activeID == id ? nil : id
  }

  func save(
    name: String,
    kind: String,
    minMinutes: Int,
    unrated: Bool,
    favoritesOnly: Bool
  ) {
    let filter = SmartFilter(
      id: "sf-\(UUID().uuidString.lowercased())",
      name: name,
      kind: kind,
      minMinutes: max(minMinutes, 0),
      unrated: unrated,
      favoritesOnly: favoritesOnly
    )
    filters.append(filter)
    persist()
  }

  func remove(_ id: String) {
    filters.removeAll { $0.id == id }
    if activeID == id { activeID = nil }
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(filters) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }
}
