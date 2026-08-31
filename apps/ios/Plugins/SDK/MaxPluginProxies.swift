import SwiftUI

/// Access-restricted proxy to query library item metadata safely.
@MainActor
protocol MaxPluginLibraryProxy: Sendable {
  func getMediaItemsCount() -> Int
  func getFavoritesCount() -> Int
  func getMediaDistribution() -> [String: Int]
  func getStorageUsed() -> Int64
}

/// Access-restricted navigation proxy to invoke actions and tab selection safely.
@MainActor
protocol MaxPluginNavigationProxy: Sendable {
  func selectTab(tabId: String)
  func openRoute(routeId: String)
}

/// Fallback or mock library proxy.
struct MockPluginLibraryProxy: MaxPluginLibraryProxy {
  init() {}
  func getMediaItemsCount() -> Int { 12 }
  func getFavoritesCount() -> Int { 3 }
  func getMediaDistribution() -> [String : Int] { ["video": 5, "image": 7] }
  func getStorageUsed() -> Int64 { 104_857_600 }
}

/// Fallback or mock navigation proxy.
struct MockPluginNavigationProxy: MaxPluginNavigationProxy {
  init() {}
  func selectTab(tabId: String) {
    print("Mock navigate selectTab: \(tabId)")
  }
  func openRoute(routeId: String) {
    print("Mock navigate openRoute: \(routeId)")
  }
}

/// Real application navigation proxy binding.
@MainActor
struct DefaultPluginNavigationProxy: MaxPluginNavigationProxy {
  private let model: MaxAppModel

  init(model: MaxAppModel) {
    self.model = model
  }

  func selectTab(tabId: String) {
    if let tab = AppTab(rawValue: tabId) {
      model.selectedTab = tab
    }
  }

  func openRoute(routeId: String) {
    PluginStore.shared.activeRouteId = routeId
  }
}

/// Real application library metadata proxy binding.
@MainActor
struct DefaultPluginLibraryProxy: MaxPluginLibraryProxy {
  private let model: MaxAppModel

  init(model: MaxAppModel) {
    self.model = model
  }

  func getMediaItemsCount() -> Int {
    model.libraryStore.catalogItems.count
  }

  func getFavoritesCount() -> Int {
    model.libraryStore.catalogItems.filter { $0.isFavorite }.count
  }

  func getMediaDistribution() -> [String: Int] {
    var dist: [String: Int] = [:]
    for item in model.libraryStore.catalogItems {
      dist[item.kind, default: 0] += 1
    }
    return dist
  }

  func getStorageUsed() -> Int64 {
    model.libraryStore.catalogItems.reduce(into: 0) { $0 += Int64($1.sizeBytes) }
  }
}


