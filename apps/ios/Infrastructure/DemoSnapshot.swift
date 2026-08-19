import Foundation

struct DemoSnapshot: Sendable {
  var primaryUser: MaxUser
  let secondUser: MaxUser
  let demoBot: MaxUser
  var bootstrap: MobileBootstrapResponse
  var media: [MaxMediaItem]
  var workspaces: [WorkspaceSummary]
  var collections: [CollectionSummary]
  var threads: [ChatThread]
  var messagesByChat: [String: [ChatMessage]]
  var ratings: [String: [RatingSubject]]
  var accessRequests: [AccessRequest]

  static var original: DemoSnapshot {
    let primary = MaxUser(
      id: "demo-primary",
      email: "demo@max.local",
      username: "maxdemo",
      displayName: "Max Explorer",
      avatarUrl: resourceURL(name: "demo-avatar", fileExtension: "png"),
      coverUrl: resourceURL(name: "demo-header", fileExtension: "jpg"),
      bio: "Collecting quiet films, shared spaces, and device-only memories.",
      role: "user",
      accessLevel: 1
    )
    let second = MaxUser(
      id: "demo-second",
      email: nil,
      username: "nora_demo",
      displayName: "Nora Demo",
      avatarUrl: resourceURL(name: "demo-avatar-second", fileExtension: "png"),
      coverUrl: nil,
      bio: nil,
      role: "user",
      accessLevel: 1
    )
    let bot = MaxUser(
      id: "demo-bot",
      email: nil,
      username: "max_demo_bot",
      displayName: "Max Demo Bot",
      avatarUrl: resourceURL(name: "demo-avatar-bot", fileExtension: "png"),
      coverUrl: nil,
      bio: "A deterministic local participant.",
      role: "demo",
      accessLevel: 1
    )

    let preferences = MobilePreferences(
      synced: .init(
        homeMode: "browse",
        filters: [:],
        libraryLayout: "grid",
        lastWorkspaceId: nil,
        lastCollectionId: nil,
        playerDefaults: [:],
        dismissedTips: []
      ),
      localOnly: ["mode": "demo"]
    )
    let bootstrap = MobileBootstrapResponse(
      success: true,
      user: primary,
      preferences: preferences,
      capabilities: .init(
        rootTabs: ["vault", "library", "shared", "chats", "profile"],
        pushNotifications: false,
        voiceCalls: false,
        videoCalls: false,
        watchParties: false,
        manualDownloads: true,
        mediaReferenceMessages: true,
        requestAccess: true,
        ratingScale: .init(min: 1, max: 5, clearValue: 0)
      )
    )

    let studio = WorkspaceSummary(
      id: "demo-space-studio",
      name: "Evening Studio",
      ownerId: primary.id,
      coverUrl: nil,
      description: "Private edits and original footage.",
      spaceType: "private",
      itemCount: 12
    )
    let archive = WorkspaceSummary(
      id: "demo-space-archive",
      name: "Shared Archive",
      ownerId: second.id,
      coverUrl: nil,
      description: "A calm shared shelf for two people.",
      spaceType: "shared",
      itemCount: 9
    )
    let collection = CollectionSummary(
      id: "demo-collection-night",
      name: "Night Drives",
      userId: primary.id,
      coverUrlFileId: nil,
      itemCount: 3
    )

    let videoURL = resourceURL(name: "max-demo-video", fileExtension: "mp4")
      ?? safeURL(path: "/media/aurora-passage.mp4")
    let imageURL = resourceURL(name: "demo-still", fileExtension: "jpg")
      ?? safeURL(path: "/media/blue-hour.jpg")
    let media: [MaxMediaItem] = [
      MaxMediaItem(
        id: "demo-media-aurora",
        title: "Aurora Passage",
        kind: "video",
        sizeBytes: 42_000_000,
        duration: 168,
        mediaUrl: videoURL,
        thumbnailUrl: resourceURL(name: "demo-poster-aurora", fileExtension: "jpg"),
        videoThumbnailUrl: nil,
        uploader: .init(id: primary.id, name: primary.displayName, avatarUrl: primary.avatarUrl),
        workspace: .init(id: studio.id, name: studio.name),
        uploadedAt: "2026-07-14T08:00:00Z",
        rating: 7,
        isFavorite: true,
        isSaved: true,
        lastPosition: 54,
        lastViewedAt: "2026-07-14T09:20:00Z",
        isPrivate: true,
        downloadable: true
      ),
      MaxMediaItem(
        id: "demo-media-blue-hour",
        title: "Blue Hour Still",
        kind: "image",
        sizeBytes: 3_200_000,
        duration: nil,
        mediaUrl: imageURL,
        thumbnailUrl: imageURL,
        videoThumbnailUrl: nil,
        uploader: .init(id: second.id, name: second.displayName, avatarUrl: second.avatarUrl),
        workspace: .init(id: archive.id, name: archive.name),
        uploadedAt: "2026-07-13T18:40:00Z",
        rating: 9,
        isFavorite: true,
        isSaved: true,
        lastPosition: 0,
        lastViewedAt: nil,
        isPrivate: false,
        downloadable: true
      ),
      MaxMediaItem(
        id: "demo-media-signal",
        title: "Distant Signal",
        kind: "video",
        sizeBytes: 68_000_000,
        duration: 312,
        mediaUrl: videoURL,
        thumbnailUrl: resourceURL(name: "demo-poster-signal", fileExtension: "jpg"),
        videoThumbnailUrl: nil,
        uploader: .init(id: second.id, name: second.displayName, avatarUrl: second.avatarUrl),
        workspace: .init(id: archive.id, name: archive.name),
        uploadedAt: "2026-07-12T15:15:00Z",
        rating: nil,
        isFavorite: false,
        isSaved: false,
        lastPosition: 0,
        lastViewedAt: nil,
        isPrivate: false,
        downloadable: true
      ),
      MaxMediaItem(
        id: "demo-media-arabic",
        title: "أضواء المساء",
        kind: "image",
        sizeBytes: 2_400_000,
        duration: nil,
        mediaUrl: imageURL,
        thumbnailUrl: imageURL,
        videoThumbnailUrl: nil,
        uploader: .init(id: primary.id, name: primary.displayName, avatarUrl: primary.avatarUrl),
        workspace: nil,
        uploadedAt: "2026-07-11T20:00:00Z",
        rating: 8,
        isFavorite: false,
        isSaved: false,
        lastPosition: 0,
        lastViewedAt: "2026-07-13T20:00:00Z",
        isPrivate: true,
        downloadable: true
      ),
    ]

    let demoBotThread = ChatThread(
      id: "demo-chat-bot",
      title: "Max Demo Bot",
      isGroup: false,
      ownerId: primary.id,
      partnerId: bot.id,
      avatarUrl: bot.avatarUrl,
      lastMessage: "Ready for a repeatable local walkthrough.",
      lastMessageAt: "2026-07-14T09:55:00Z",
      unreadCount: 1
    )
    let sharedThread = ChatThread(
      id: "demo-chat-shared",
      title: "Evening Studio",
      isGroup: true,
      ownerId: primary.id,
      partnerId: second.id,
      avatarUrl: second.avatarUrl,
      lastMessage: "The new cut is saved in Shared.",
      lastMessageAt: "2026-07-14T09:30:00Z",
      unreadCount: 0
    )

    let messages: [String: [ChatMessage]] = [
      demoBotThread.id: [
        ChatMessage(
          id: "demo-message-welcome",
          dmId: demoBotThread.id,
          senderId: bot.id,
          content: "I am a local deterministic Demo participant — no person or network is connected.",
          mediaUrl: nil,
          mediaType: nil,
          dmMediaId: nil,
          mediaName: nil,
          isEdited: false,
          isDeleted: false,
          isHardDeleted: false,
          readAt: nil,
          replyToId: nil,
          createdAt: "2026-07-14T09:55:00Z",
          mediaReferences: nil,
          sender: .init(id: bot.id, displayName: bot.displayName, avatarUrl: bot.avatarUrl)
        ),
      ],
      sharedThread.id: [
        ChatMessage(
          id: "demo-message-shared",
          dmId: sharedThread.id,
          senderId: second.id,
          content: "The new cut is saved in Shared.",
          mediaUrl: nil,
          mediaType: nil,
          dmMediaId: nil,
          mediaName: nil,
          isEdited: false,
          isDeleted: false,
          isHardDeleted: false,
          readAt: "2026-07-14T09:31:00Z",
          replyToId: nil,
          createdAt: "2026-07-14T09:30:00Z",
          mediaReferences: nil,
          sender: .init(id: second.id, displayName: second.displayName, avatarUrl: second.avatarUrl)
        ),
      ],
    ]

    let ratingUsers = (
      RatingSubject.User(
        id: primary.id,
        displayName: primary.displayName,
        avatarUrl: primary.avatarUrl
      ),
      RatingSubject.User(
        id: second.id,
        displayName: second.displayName,
        avatarUrl: second.avatarUrl
      )
    )
    let ratings: [String: [RatingSubject]] = [
      media[0].id: [
        RatingSubject(user: ratingUsers.0, score: 4, updatedAt: "2026-07-14T08:10:00Z", canEdit: true),
        RatingSubject(user: ratingUsers.1, score: 3, updatedAt: "2026-07-14T08:12:00Z", canEdit: true),
      ],
      media[1].id: [
        RatingSubject(user: ratingUsers.0, score: 5, updatedAt: "2026-07-13T19:00:00Z", canEdit: true),
        RatingSubject(user: ratingUsers.1, score: nil, updatedAt: nil, canEdit: true),
      ],
      media[3].id: [
        RatingSubject(user: ratingUsers.0, score: 4, updatedAt: "2026-07-13T20:05:00Z", canEdit: true),
        RatingSubject(user: ratingUsers.1, score: 4, updatedAt: "2026-07-13T20:06:00Z", canEdit: true),
      ],
    ]
    let accessRequest = AccessRequest(
      id: "demo-access-1",
      fileId: media[2].id,
      requesterUserId: second.id,
      ownerUserId: primary.id,
      messageId: nil,
      note: "May I add this to our shared screening shelf?",
      status: "pending",
      shareId: nil,
      createdAt: "2026-07-14T09:45:00Z",
      decidedAt: nil,
      decidedBy: nil,
      fileName: media[2].title,
      requesterName: second.displayName
    )

    return DemoSnapshot(
      primaryUser: primary,
      secondUser: second,
      demoBot: bot,
      bootstrap: bootstrap,
      media: media,
      workspaces: [studio, archive],
      collections: [collection],
      threads: [demoBotThread, sharedThread],
      messagesByChat: messages,
      ratings: ratings,
      accessRequests: [accessRequest]
    )
  }

  private static func resourceURL(name: String, fileExtension: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Demo")
      ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
  }

  private static func safeURL(path: String) -> URL? {
    var components = URLComponents()
    components.scheme = "max-demo"
    components.host = "fixture"
    components.path = path
    return components.url
  }
}
