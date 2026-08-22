import Foundation

enum MaxFixtures {
  static let media: [MediaItem] = [
    MediaItem(
      id: "demo-media-aurora",
      title: "Aurora Passage",
      kind: .video,
      subtitle: "Evening Studio · Max Explorer",
      symbol: "play.rectangle.fill",
      hue: 0.72,
      duration: 168,
      sizeBytes: 42_000_000,
      isSaved: true,
      isOffline: true,
      isTrashed: false,
      ownRating: 8,
      partnerRating: 7,
      workspaceID: "demo-space-studio",
      uploadedAt: Date(timeIntervalSince1970: 1_752_480_000)
    ),
    MediaItem(
      id: "demo-media-blue-hour",
      title: "Blue Hour Still",
      kind: .image,
      subtitle: "Shared Archive · Nora Demo",
      symbol: "photo.fill",
      hue: 0.58,
      duration: nil,
      sizeBytes: 3_200_000,
      isSaved: true,
      isOffline: false,
      isTrashed: false,
      ownRating: 9,
      partnerRating: 8,
      workspaceID: "demo-space-archive",
      uploadedAt: Date(timeIntervalSince1970: 1_752_432_000)
    ),
    MediaItem(
      id: "demo-media-signal",
      title: "Distant Signal",
      kind: .video,
      subtitle: "Shared Archive · Nora Demo",
      symbol: "waveform.path.ecg.rectangle.fill",
      hue: 0.92,
      duration: 312,
      sizeBytes: 68_000_000,
      isSaved: false,
      isOffline: false,
      isTrashed: false,
      ownRating: nil,
      partnerRating: nil,
      workspaceID: "demo-space-archive",
      uploadedAt: Date(timeIntervalSince1970: 1_752_345_000)
    ),
    MediaItem(
      id: "demo-media-arabic",
      title: "أضواء المساء",
      kind: .image,
      subtitle: "Max Explorer · Private",
      symbol: "moon.stars.fill",
      hue: 0.10,
      duration: nil,
      sizeBytes: 2_400_000,
      isSaved: false,
      isOffline: false,
      isTrashed: false,
      ownRating: 8,
      partnerRating: nil,
      workspaceID: nil,
      uploadedAt: Date(timeIntervalSince1970: 1_752_276_000)
    ),
    MediaItem(
      id: "demo-media-orbit",
      title: "Quiet Orbit",
      kind: .video,
      subtitle: "Night Drives · Max Explorer",
      symbol: "sparkles.tv.fill",
      hue: 0.82,
      duration: 241,
      sizeBytes: 51_000_000,
      isSaved: true,
      isOffline: false,
      isTrashed: false,
      ownRating: 10,
      partnerRating: 9,
      workspaceID: "demo-space-studio",
      uploadedAt: Date(timeIntervalSince1970: 1_752_100_000)
    ),
    MediaItem(
      id: "demo-media-dunes",
      title: "Dunes at Dawn",
      kind: .image,
      subtitle: "Personal Vault · Max Explorer",
      symbol: "sun.horizon.fill",
      hue: 0.07,
      duration: nil,
      sizeBytes: 4_800_000,
      isSaved: false,
      isOffline: false,
      isTrashed: false,
      ownRating: 7,
      partnerRating: 8,
      workspaceID: nil,
      uploadedAt: Date(timeIntervalSince1970: 1_751_980_000)
    ),
    MediaItem(
      id: "demo-media-rain",
      title: "Window Rain",
      kind: .video,
      subtitle: "Evening Studio · Nora Demo",
      symbol: "cloud.rain.fill",
      hue: 0.54,
      duration: 94,
      sizeBytes: 21_000_000,
      isSaved: true,
      isOffline: true,
      isTrashed: false,
      ownRating: 9,
      partnerRating: nil,
      workspaceID: "demo-space-studio",
      uploadedAt: Date(timeIntervalSince1970: 1_751_820_000)
    ),
    MediaItem(
      id: "demo-media-garden",
      title: "Glass Garden",
      kind: .image,
      subtitle: "Shared Archive · Max Explorer",
      symbol: "leaf.fill",
      hue: 0.36,
      duration: nil,
      sizeBytes: 6_100_000,
      isSaved: false,
      isOffline: false,
      isTrashed: false,
      ownRating: nil,
      partnerRating: 6,
      workspaceID: "demo-space-archive",
      uploadedAt: Date(timeIntervalSince1970: 1_751_700_000)
    ),
    MediaItem(
      id: "demo-media-neon",
      title: "Neon Crossing",
      kind: .video,
      subtitle: "Night Drives · Max Explorer",
      symbol: "car.side.fill",
      hue: 0.94,
      duration: 203,
      sizeBytes: 46_000_000,
      isSaved: true,
      isOffline: false,
      isTrashed: false,
      ownRating: 8,
      partnerRating: 9,
      workspaceID: "demo-space-studio",
      uploadedAt: Date(timeIntervalSince1970: 1_751_540_000)
    ),
    MediaItem(
      id: "demo-media-archive",
      title: "Archive Fragment",
      kind: .image,
      subtitle: "Deleted 2 days ago",
      symbol: "doc.richtext.fill",
      hue: 0.62,
      duration: nil,
      sizeBytes: 1_900_000,
      isSaved: false,
      isOffline: false,
      isTrashed: true,
      ownRating: nil,
      partnerRating: nil,
      workspaceID: nil,
      uploadedAt: Date(timeIntervalSince1970: 1_750_000_000)
    ),
  ]

  static let workspaces: [Workspace] = [
    Workspace(
      id: "demo-space-studio",
      name: "Evening Studio",
      summary: "Private edits, source footage, and works in progress.",
      memberNames: ["Max Explorer", "Nora Demo", "Sami"],
      itemIDs: ["demo-media-aurora", "demo-media-orbit", "demo-media-rain", "demo-media-neon"],
      hue: 0.74
    ),
    Workspace(
      id: "demo-space-archive",
      name: "Shared Archive",
      summary: "A calm shared shelf for films, stills, and references.",
      memberNames: ["Max Explorer", "Nora Demo"],
      itemIDs: ["demo-media-blue-hour", "demo-media-signal", "demo-media-garden"],
      hue: 0.55
    ),
  ]

  static let threads: [ChatThread] = [
    ChatThread(
      id: "demo-chat-bot",
      title: "Max Demo Bot",
      subtitle: "Ready for a repeatable local walkthrough.",
      unreadCount: 1,
      isMuted: false,
      hue: 0.74,
      messages: [
        ChatMessage(
          id: "demo-message-welcome",
          sender: "Max Demo Bot",
          body: "I am a deterministic local participant — no person or network is connected.",
          sentAt: Date(timeIntervalSince1970: 1_752_486_900),
          isMine: false,
          reaction: "✨",
          isEdited: false,
          mediaID: nil
        ),
        ChatMessage(
          id: "demo-message-plan",
          sender: "Max Explorer",
          body: "Keep Aurora Passage in the Night Drives collection.",
          sentAt: Date(timeIntervalSince1970: 1_752_487_200),
          isMine: true,
          reaction: nil,
          isEdited: false,
          mediaID: "demo-media-aurora"
        ),
        ChatMessage(
          id: "demo-message-reply",
          sender: "Max Demo Bot",
          body: "Done. The video is saved and ready offline.",
          sentAt: Date(timeIntervalSince1970: 1_752_487_500),
          isMine: false,
          reaction: "👍",
          isEdited: false,
          mediaID: nil
        ),
      ]
    ),
    ChatThread(
      id: "demo-chat-shared",
      title: "Evening Studio",
      subtitle: "Nora: The new cut is saved in Shared.",
      unreadCount: 0,
      isMuted: false,
      hue: 0.12,
      messages: [
        ChatMessage(
          id: "demo-shared-1",
          sender: "Nora Demo",
          body: "The new cut is saved in Shared. The color pass feels right now.",
          sentAt: Date(timeIntervalSince1970: 1_752_485_000),
          isMine: false,
          reaction: "❤️",
          isEdited: false,
          mediaID: "demo-media-blue-hour"
        ),
        ChatMessage(
          id: "demo-shared-2",
          sender: "Max Explorer",
          body: "Perfect. I’ll review it tonight.",
          sentAt: Date(timeIntervalSince1970: 1_752_485_900),
          isMine: true,
          reaction: nil,
          isEdited: false,
          mediaID: nil
        ),
      ]
    ),
    ChatThread(
      id: "demo-chat-sami",
      title: "Sami",
      subtitle: "Sent a photo · Yesterday",
      unreadCount: 3,
      isMuted: true,
      hue: 0.37,
      messages: [
        ChatMessage(
          id: "demo-sami-1",
          sender: "Sami",
          body: "This frame belongs in the shared archive.",
          sentAt: Date(timeIntervalSince1970: 1_752_400_000),
          isMine: false,
          reaction: nil,
          isEdited: false,
          mediaID: "demo-media-garden"
        ),
      ]
    ),
  ]

  static let profile = MaxProfile(
    displayName: "Max Explorer",
    username: "maxdemo",
    bio: "Collecting quiet films, shared spaces, and device-only memories.",
    email: "demo@max.local",
    totalItems: 428,
    watchHours: 126,
    sharedSpaces: 2,
    storageUsedGB: 18.7
  )

  static let plugins: [PluginDescriptor] = [
    PluginDescriptor(id: "insights", name: "Activity Insights", summary: "Private viewing and library trends.", symbol: "chart.xyaxis.line", hue: 0.72, isEnabled: true),
    PluginDescriptor(id: "quick-actions", name: "Quick Actions", summary: "Save, upload, and share from a compact palette.", symbol: "bolt.fill", hue: 0.11, isEnabled: true),
    PluginDescriptor(id: "chromatic", name: "Chromatic", summary: "A vivid visual layer for Max surfaces.", symbol: "paintpalette.fill", hue: 0.93, isEnabled: false),
    PluginDescriptor(id: "winter", name: "Winter Is Coming", summary: "Seasonal snow, tones, and ambient motion.", symbol: "snowflake", hue: 0.56, isEnabled: false),
    PluginDescriptor(id: "external-data", name: "External Data Lab", summary: "A sandbox for scoped network integrations.", symbol: "network", hue: 0.34, isEnabled: false),
  ]

  static let memories: [MemoryMoment] = [
    MemoryMoment(id: "memory-1", title: "One year ago", date: Date(timeIntervalSince1970: 1_720_000_000), location: "Riyadh", symbol: "sparkles", hue: 0.09),
    MemoryMoment(id: "memory-2", title: "Night drives", date: Date(timeIntervalSince1970: 1_708_000_000), location: "AlUla", symbol: "car.side.fill", hue: 0.78),
    MemoryMoment(id: "memory-3", title: "Quiet mornings", date: Date(timeIntervalSince1970: 1_690_000_000), location: "Jeddah", symbol: "sunrise.fill", hue: 0.52),
    MemoryMoment(id: "memory-4", title: "Studio fragments", date: Date(timeIntervalSince1970: 1_680_000_000), location: "Dubai", symbol: "film.stack.fill", hue: 0.91),
  ]

  static let collections: [CollectionDescriptor] = [
    CollectionDescriptor(id: "collection-night", name: "Night Drives", summary: "4 items · Updated today", symbol: "car.side.fill", itemIDs: ["demo-media-aurora", "demo-media-orbit", "demo-media-neon"], hue: 0.75),
    CollectionDescriptor(id: "collection-stills", name: "Quiet Stills", summary: "3 items · Updated yesterday", symbol: "photo.stack.fill", itemIDs: ["demo-media-blue-hour", "demo-media-dunes", "demo-media-garden"], hue: 0.46),
    CollectionDescriptor(id: "collection-favorites", name: "All-time Favorites", summary: "5 items · Synced", symbol: "heart.fill", itemIDs: ["demo-media-aurora", "demo-media-blue-hour", "demo-media-orbit", "demo-media-rain"], hue: 0.95),
  ]
}

