import Foundation

enum SidebarDestination: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case vault
  case library
  case shared
  case chats
  case profile
  case memories
  case plugins

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .vault: "archivebox.fill"
    case .library: "rectangle.grid.2x2.fill"
    case .shared: "person.2.fill"
    case .chats: "bubble.left.and.bubble.right.fill"
    case .profile: "person.crop.circle.fill"
    case .memories: "sparkles.rectangle.stack.fill"
    case .plugins: "puzzlepiece.extension.fill"
    }
  }
}

enum AppLanguage: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case english = "en"
  case arabic = "ar"

  var id: String { rawValue }
  var layoutDirectionIsRTL: Bool { self == .arabic }
}

enum AppTheme: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case max
  case light
  case dark
  case spectrum
  case clouds
  case council

  var id: String { rawValue }
}

enum MediaKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case all
  case video
  case image

  var id: String { rawValue }
}

enum LibrarySection: String, CaseIterable, Hashable, Identifiable, Sendable {
  case overview
  case saved
  case ratings
  case offline
  case collections
  case trash

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .saved: "bookmark.fill"
    case .ratings: "star.leadinghalf.filled"
    case .offline: "arrow.down.circle.fill"
    case .collections: "rectangle.stack.fill"
    case .trash: "trash.fill"
    }
  }
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
  let id: String
  var title: String
  let kind: MediaKind
  let subtitle: String
  let symbol: String
  let hue: Double
  let duration: TimeInterval?
  let sizeBytes: Int
  var isSaved: Bool
  var isOffline: Bool
  var isTrashed: Bool
  var ownRating: Int?
  var partnerRating: Int?
  let workspaceID: String?
  let uploadedAt: Date
}

struct Workspace: Identifiable, Codable, Hashable, Sendable {
  let id: String
  var name: String
  var summary: String
  var memberNames: [String]
  var itemIDs: [String]
  let hue: Double
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let sender: String
  var body: String
  let sentAt: Date
  let isMine: Bool
  var reaction: String?
  var isEdited: Bool
  var mediaID: String?
}

struct ChatThread: Identifiable, Codable, Hashable, Sendable {
  let id: String
  var title: String
  var subtitle: String
  var unreadCount: Int
  var isMuted: Bool
  let hue: Double
  var messages: [ChatMessage]
}

struct MaxProfile: Codable, Hashable, Sendable {
  var displayName: String
  var username: String
  var bio: String
  var email: String
  var totalItems: Int
  var watchHours: Int
  var sharedSpaces: Int
  var storageUsedGB: Double
}

enum TransferState: String, Codable, Hashable, Sendable {
  case preparing
  case uploading
  case complete
  case failed
}

struct TransferRecord: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let title: String
  var progress: Double
  var state: TransferState
}

struct PluginDescriptor: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let name: String
  let summary: String
  let symbol: String
  let hue: Double
  var isEnabled: Bool
}

struct MemoryMoment: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let title: String
  let date: Date
  let location: String
  let symbol: String
  let hue: Double
}

struct CollectionDescriptor: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let name: String
  let summary: String
  let symbol: String
  let itemIDs: [String]
  let hue: Double
}

