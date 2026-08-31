import SwiftUI

struct PluginAuthor: Codable, Sendable, Hashable {
  let name: String
  let email: String?
  let website: String?
}

struct AssetReference: Codable, Sendable, Hashable {
  let type: String // "system", "local", "color"
  let name: String
}

struct PluginIcon: Codable, Sendable, Hashable {
  let light: AssetReference
  let dark: AssetReference
  let monochrome: AssetReference?
  let animated: AssetReference?
}

struct PluginHero: Codable, Sendable, Hashable {
  let title: String
  let subtitle: String?
  let backgroundAsset: AssetReference
}

struct PluginPreview: Codable, Sendable, Hashable, Identifiable {
  var id: String { name }
  let name: String
  let type: String // "image", "video", "interactive"
  let title: String?
  let asset: AssetReference
  let aspectRatio: String // e.g. "16:9", "1:1"
}

enum PluginCategory: String, Codable, CaseIterable, Sendable, Hashable {
  case appearance
  case feature
  case integration
  case utility
  case seasonal
  case experimental

  var localizedName: String {
    switch self {
    case .appearance: "Appearance"
    case .feature: "Feature"
    case .integration: "Integration"
    case .utility: "Utility"
    case .seasonal: "Seasonal"
    case .experimental: "Experimental"
    }
  }
  
  var localizedNameAr: String {
    switch self {
    case .appearance: "المظهر"
    case .feature: "الميزات"
    case .integration: "التكامل"
    case .utility: "الأدوات"
    case .seasonal: "الموسمية"
    case .experimental: "التجريبية"
    }
  }
}

enum PluginCapability: String, Codable, CaseIterable, Sendable, Hashable {
  case theme = "theme"
  case navigationStyle = "navigation-style"
  case navigationItems = "navigation-items"
  case navigationOrder = "navigation-order"
  case customRoute = "custom-route"
  case customWidget = "custom-widget"
  case cardStyle = "card-style"
  case viewerStyle = "viewer-style"
  case profileStyle = "profile-style"
  case emptyStateStyle = "empty-state-style"
  case transitions = "transitions"
  case sounds = "sounds"
  case haptics = "haptics"
  case externalApi = "external-api"
  case dataReview = "data-review"
  case settingsPage = "settings-page"
}

enum PluginPermission: String, Codable, CaseIterable, Sendable, Hashable {
  case modifyAppearance = "modify-appearance"
  case modifyNavigation = "modify-navigation"
  case addRoutes = "add-routes"
  case addWidgets = "add-widgets"
  case readPublicMetadata = "read-public-metadata"
  case readSelectedUserData = "read-selected-user-data"
  case accessNetwork = "access-network"
  case connectExternalApi = "connect-external-api"
  case reviewSelectedData = "review-selected-data"
  case useSound = "use-sound"
  case useHaptics = "use-haptics"

  var localizedTitle: String {
    let key = "plugin.permission.\(self.rawValue.replacingOccurrences(of: "-", with: "_"))"
    return String(localized: LocalizedStringResource(stringLiteral: key))
  }

  var userDescription: String {
    let key = "plugin.permission.\(self.rawValue.replacingOccurrences(of: "-", with: "_")).desc"
    return String(localized: LocalizedStringResource(stringLiteral: key))
  }
}

struct PluginNetworkManifest: Codable, Sendable, Hashable {
  let allowedDomains: [String]
  let sendsUserData: Bool

  init(allowedDomains: [String] = [], sendsUserData: Bool = false) {
    self.allowedDomains = allowedDomains
    self.sendsUserData = sendsUserData
  }
}

struct MaxPluginManifest: Codable, Sendable, Hashable {
  let schemaVersion: Int
  let id: String
  let name: String
  let version: String
  let description: String
  let longDescription: String?
  let author: PluginAuthor
  let category: PluginCategory
  let tags: [String]
  let icon: PluginIcon
  let hero: PluginHero?
  let previews: [PluginPreview]
  let capabilities: [PluginCapability]
  let permissions: [PluginPermission]
  let network: PluginNetworkManifest?
  let minimumAppVersion: String
  let maximumAppVersion: String?
}


