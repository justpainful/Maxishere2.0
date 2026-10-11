import Foundation

enum LoadState<Value: Sendable>: Sendable {
  case idle
  case loading
  case loaded(Value)
  case failed(String)

  var value: Value? {
    guard case .loaded(let value) = self else { return nil }
    return value
  }

  var errorMessage: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }

  var isLoading: Bool {
    guard case .loading = self else { return false }
    return true
  }
}

struct EmptySuccess: Codable, Sendable {
  let success: Bool
}

struct MobileLoginResponse: Codable, Sendable {
  struct Session: Codable, Sendable {
    let token: String
    let transport: String
    let tokenType: String
  }

  let success: Bool
  let session: Session
  let user: MaxUser
}

struct MobileBootstrapResponse: Codable, Sendable {
  struct Capabilities: Codable, Sendable {
    let rootTabs: [String]
    let pushNotifications: Bool
    let voiceCalls: Bool
    let videoCalls: Bool
    let watchParties: Bool
    let manualDownloads: Bool
    let mediaReferenceMessages: Bool
    let requestAccess: Bool
    let ratingScale: RatingScale?
  }

  struct RatingScale: Codable, Sendable {
    let min: Int
    let max: Int
    let clearValue: Int
  }

  let success: Bool
  let user: MaxUser
  let preferences: MobilePreferences
  let capabilities: Capabilities
}

struct MobilePreferences: Codable, Sendable {
  struct Synced: Codable, Sendable {
    let homeMode: String
    let filters: [String: JSONValue]
    let libraryLayout: String
    let lastWorkspaceId: String?
    let lastCollectionId: String?
    let playerDefaults: [String: JSONValue]
    let dismissedTips: [String]
  }

  let synced: Synced
  let localOnly: [String: String]
}

enum JSONValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

struct MaxUser: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let email: String?
  let username: String?
  let displayName: String
  let avatarUrl: URL?
  let coverUrl: URL?
  let bio: String?
  let role: String?
  let accessLevel: Int?
}

struct MobileHomeResponse: Codable, Sendable {
  let success: Bool
  let defaultMode: String
  let shuffle: [MaxMediaItem]
  let browse: [MaxMediaItem]
  let filters: [String: JSONValue]
}

struct MobileMediaListResponse: Codable, Sendable {
  struct Pagination: Codable, Sendable {
    let limit: Int
    let offset: Int
    let nextOffset: Int?
    /// How many items match in total, server-reported.
    ///
    /// Counting the loaded page instead reports the page size, which is why every
    /// summary in the app read "100" regardless of the real library size.
    let total: Int?

    init(limit: Int, offset: Int, nextOffset: Int?, total: Int? = nil) {
      self.limit = limit
      self.offset = offset
      self.nextOffset = nextOffset
      self.total = total
    }
  }

  let success: Bool
  let mode: String
  let items: [MaxMediaItem]
  let pagination: Pagination
}

struct MaxMediaItem: Codable, Hashable, Identifiable, Sendable {
  struct Actor: Codable, Hashable, Sendable {
    let id: String?
    let name: String?
    let avatarUrl: URL?
  }

  struct Workspace: Codable, Hashable, Sendable {
    let id: String
    let name: String?
  }

  let id: String
  let title: String
  let kind: String
  let sizeBytes: Int
  let duration: Double?
  let mediaUrl: URL?
  /// Adaptive stream (HLS) — preferred by the player when present. Defaulted
  /// so the existing memberwise-init call sites keep compiling; only the live
  /// wire mapping supplies it.
  var hlsUrl: URL? = nil
  let thumbnailUrl: URL?
  let videoThumbnailUrl: URL?
  let uploader: Actor
  let workspace: Workspace?
  let uploadedAt: String?
  let rating: Int?
  let isFavorite: Bool
  let isSaved: Bool
  let lastPosition: Double
  let lastViewedAt: String?
  let isPrivate: Bool
  let downloadable: Bool
  // Defaulted so the eight existing memberwise-init call sites keep compiling;
  // only the live API mapping supplies them.
  var width: Int? = nil
  var height: Int? = nil

  /// Width divided by height, or nil when the server has not measured the item.
  ///
  /// A grid that assumes one shape for everything has to crop whatever does not
  /// match, which is what made portrait video read as zoomed in. Clamped so a
  /// pathological file cannot produce a tile taller than the screen.
  var aspectRatio: CGFloat? {
    guard let width, let height, width > 0, height > 0 else { return nil }
    return min(max(CGFloat(width) / CGFloat(height), 0.5), 2.2)
  }

  /// The title as a person should read it, rather than as the filesystem stored it.
  ///
  /// Uploads arrive named `IMG_4312.MOV` or `video_2026-02-11_final.mp4`, and
  /// printing that verbatim is what made the profile and library shelves look
  /// like a directory listing. The extension goes, separators become spaces, and
  /// anything that does not survive that falls back to the original name so a
  /// deliberately titled item is never mangled.
  var displayTitle: String { title.asMediaDisplayName }

  var posterURL: URL? {
    // A video stream is not an image fallback. Passing `mediaUrl` to the
    // thumbnail loader downloads video bytes and guarantees a decode failure.
    kind.lowercased() == "video"
      ? (thumbnailUrl ?? videoThumbnailUrl)
      : (thumbnailUrl ?? mediaUrl)
  }
  var hasProgress: Bool { lastPosition > 0 }

  /// A copy with `lastPosition` changed — the mini-player hand-off, so
  /// re-opening the full player resumes at the card's live position.
  func withLastPosition(_ value: Double) -> MaxMediaItem {
    MaxMediaItem(
      id: id, title: title, kind: kind, sizeBytes: sizeBytes, duration: duration,
      mediaUrl: mediaUrl, hlsUrl: hlsUrl, thumbnailUrl: thumbnailUrl, videoThumbnailUrl: videoThumbnailUrl,
      uploader: uploader, workspace: workspace, uploadedAt: uploadedAt, rating: rating,
      isFavorite: isFavorite, isSaved: isSaved, lastPosition: max(value, 0),
      lastViewedAt: lastViewedAt, isPrivate: isPrivate, downloadable: downloadable,
      width: width, height: height
    )
  }

  /// A copy with `isFavorite` changed — used for optimistic in-place updates so
  /// toggling a favorite never has to reload (and momentarily empty) the catalog
  /// out from under an open player.
  func withFavorite(_ value: Bool) -> MaxMediaItem {
    MaxMediaItem(
      id: id, title: title, kind: kind, sizeBytes: sizeBytes, duration: duration,
      mediaUrl: mediaUrl, hlsUrl: hlsUrl, thumbnailUrl: thumbnailUrl, videoThumbnailUrl: videoThumbnailUrl,
      uploader: uploader, workspace: workspace, uploadedAt: uploadedAt, rating: rating,
      isFavorite: value, isSaved: isSaved, lastPosition: lastPosition,
      lastViewedAt: lastViewedAt, isPrivate: isPrivate, downloadable: downloadable,
      // Carried over deliberately: dropping them makes `aspectRatio` nil, and the
      // masonry then re-shapes the tile to its fallback ratio, so every like made
      // the grid visibly reflow around the item that was just tapped.
      width: width, height: height
    )
  }
}

/// A saved range of a media item — the player's "virtual clip". Playing one is
/// ordinary playback with enforced bounds; deleting one deletes only the row.
struct MediaClip: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mediaId: String
  let ownerId: String
  let title: String
  let startSeconds: Double
  let endSeconds: Double
  let createdAt: String
}

/// A labelled timecode drawn as a tick on the player's scrubber.
struct MediaMarker: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mediaId: String
  let atSeconds: Double
  let label: String
  let createdAt: String
}

/// A saved chat sticker: a small image the caller re-sends with one tap.
/// `url` is the signed image URL; the server orders favorites first.
struct MaxSticker: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mediaId: String
  let emoji: String?
  let favorite: Bool
  let url: URL?
  let createdAt: String
}

/// The `{"items":[...]}` envelope the stickers listing answers with.
struct MaxStickerListResponse: Codable, Sendable {
  let items: [MaxSticker]
}

/// A public, expiring window onto one media item for someone with no account.
/// Dates stay RFC3339 strings, like every other model. `url` is the full
/// shareable address; the list endpoint merges it into each row, and the
/// create endpoint sends it beside the link.
struct MaxShareLink: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mediaId: String
  let token: String
  let expiresAt: String
  let maxViews: Int?
  let viewCount: Int
  let revokedAt: String?
  let createdAt: String
  // Defaulted so the wire row without a merged url still constructs; the live
  // client fills it from the create response's sibling field.
  var url: String? = nil
}

/// The `{"items":[...]}` envelope the share-links listing answers with.
struct MaxShareLinkListResponse: Codable, Sendable {
  let items: [MaxShareLink]
}

/// The create endpoint's `{"link":{...},"url":"..."}` envelope.
struct MaxShareLinkCreateResponse: Codable, Sendable {
  let link: MaxShareLink
  let url: String
}

/// One story: a media item pinned above the chat inbox for 24 hours, visible to
/// everyone the poster shares a conversation with. Dates stay RFC3339 strings,
/// like every other model.
struct MaxStory: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let mediaId: String
  /// "image" or "video".
  let kind: String
  let caption: String?
  let url: URL?
  let posterUrl: URL?
  let viewed: Bool
  let createdAt: String
  let expiresAt: String
}

/// One poster's ring on the stories rail — the server orders mine first, then
/// posters with unseen stories.
struct MaxStoryRail: Codable, Hashable, Identifiable, Sendable {
  var id: String { userId }
  let userId: String
  let displayName: String
  let avatarUrl: URL?
  let mine: Bool
  let unseen: Int
  let stories: [MaxStory]
}

/// The `{"rails":[...]}` envelope the stories listing answers with.
struct MaxStoryRailsResponse: Codable, Sendable {
  let rails: [MaxStoryRail]
}

/// One row of the profile's "Most Rewatched" shelf, ranked by re-watch heat.
struct MaxRewatchedItem: Codable, Hashable, Identifiable, Sendable {
  var id: String { mediaId }
  let mediaId: String
  let name: String
  let kind: String
  let posterUrl: URL?
  let heatTotal: Int
}

/// The `{"items":[...]}` envelope the rewatched listing answers with.
struct MaxRewatchedListResponse: Codable, Sendable {
  let items: [MaxRewatchedItem]
}

/// A shareable group-invite link: anyone holding the token can preview and
/// join the conversation until it expires, runs out of uses, or is revoked.
/// Dates stay RFC3339 strings, like every other model.
struct MaxGroupInvite: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let token: String
  let expiresAt: String
  let maxUses: Int?
  let useCount: Int
  let revokedAt: String?
  let createdAt: String
  /// The full join URL. The list rows carry it inline; the create endpoint
  /// sends it beside the invite and the client merges it, like share links.
  var link: String? = nil
}

/// The `{"items":[...]}` envelope the invite listing answers with.
struct MaxGroupInviteListResponse: Codable, Sendable {
  let items: [MaxGroupInvite]
}

/// The create endpoint's `{"invite":{...},"link":"..."}` envelope.
struct MaxGroupInviteCreateResponse: Codable, Sendable {
  let invite: MaxGroupInvite
  let link: String
}

/// What an invite token shows before joining: enough to decide, nothing more.
struct MaxInvitePreview: Codable, Hashable, Sendable {
  let conversationId: String
  let title: String
  let avatarUrl: URL?
  let memberCount: Int
  let alreadyMember: Bool
}

/// The accept endpoint's answer: the conversation to open.
struct MaxInviteAcceptResponse: Codable, Sendable {
  let success: Bool
  let conversationId: String
}

/// One person with access to a shared collection, plus their role
/// ("owner", "editor" or "viewer").
struct MaxCollectionMember: Codable, Hashable, Identifiable, Sendable {
  var id: String { userId }
  let userId: String
  let displayName: String
  let username: String
  let role: String
  let createdAt: String
}

/// The `{"items":[...]}` envelope the collection-members listing answers with.
struct MaxCollectionMemberListResponse: Codable, Sendable {
  let items: [MaxCollectionMember]
}

/// One "Continue Watching" card: a video left partway through.
struct MaxContinueItem: Codable, Hashable, Identifiable, Sendable {
  var id: String { mediaId }
  let mediaId: String
  let name: String
  let kind: String
  let posterUrl: URL?
  let positionSeconds: Double
  let durationSeconds: Double?
  let viewedAt: String
}

/// The `{"items":[...]}` envelope the continue-watching listing answers with.
struct MaxContinueListResponse: Codable, Sendable {
  let items: [MaxContinueItem]
}

/// The private year-in-review aggregates — computed from the caller's own
/// data, visible to the caller alone. `busiestMonth` is 1...12 (0 = none).
struct MaxWrapped: Codable, Hashable, Sendable {
  let year: Int
  let watchSeconds: Int
  let itemsWatched: Int
  let ratingsGiven: Int
  let favoritesAdded: Int
  let uploads: Int
  let busiestMonth: Int
  let topRewatched: [MaxRewatchedItem]
}

/// The `{"items":[...]}` envelope the clips and markers endpoints answer with.
struct MediaClipListResponse: Codable, Sendable {
  let items: [MediaClip]
}

struct MediaMarkerListResponse: Codable, Sendable {
  let items: [MediaMarker]
}

/// A soft-deleted media item plus its trash metadata, shown on the Trash screen.
struct TrashedMedia: Identifiable, Hashable, Sendable {
  let media: MaxMediaItem
  let deletedAt: Date?
  let purgeAfter: Date?

  var id: String { media.id }

  /// Whole days until the item is eligible for permanent purge (nil if unknown).
  /// Uses `ceil` so "0 days left" only appears once the window has truly lapsed.
  var daysUntilPurge: Int? {
    guard let purgeAfter else { return nil }
    let seconds = purgeAfter.timeIntervalSinceNow
    if seconds <= 0 { return 0 }
    return Int(ceil(seconds / 86_400))
  }
}

struct TrashedMediaPage: Sendable {
  let items: [TrashedMedia]
  let nextCursor: String?
}

struct MobileLibraryResponse: Codable, Sendable {
  struct Storage: Codable, Sendable {
    let usedBytes: Int
    let itemCount: Int
  }

  let success: Bool
  let personalStorage: Storage
  let workspaces: [WorkspaceSummary]
  let collections: [CollectionSummary]
  let saved: [MaxMediaItem]
  let downloads: DownloadSummary
}

struct MobileProfileResponse: Codable, Sendable {
  struct ProfileStats: Codable, Sendable {
    let ratedFiles: Int?
    let totalViewed: Int
    let totalWatchSeconds: Int
  }

  struct ProfileStorage: Codable, Sendable {
    let usedBytes: Int
    let fileCount: Int
  }

  struct Personal: Codable, Sendable {
    let stickyNotes: [ProfileStickyNote]
    let fileFavoritePins: [ProfileFavoritePin]
    let personalRatings: [ProfileRating]
    let catalogFavorites: [CatalogEntry]
    let catalogRatings: [CatalogEntry]
    let showcaseCards: [ShowcaseCard]
  }

  let success: Bool
  let user: MaxUser
  let stats: ProfileStats
  let storage: ProfileStorage
  let workspaces: [WorkspaceSummary]
  let favorites: [MaxMediaItem]
  let personal: Personal
}

struct ProfileUpdateRequest: Codable, Hashable, Sendable {
  let displayName: String?
  let username: String?
  let bio: String?
  let avatarUrl: URL?
  let coverUrl: URL?

  init(
    displayName: String? = nil,
    username: String? = nil,
    bio: String? = nil,
    avatarUrl: URL? = nil,
    coverUrl: URL? = nil
  ) {
    self.displayName = displayName
    self.username = username
    self.bio = bio
    self.avatarUrl = avatarUrl
    self.coverUrl = coverUrl
  }
}

enum ProfileImageKind: String, Codable, Hashable, Sendable {
  case avatar
  case cover
}

struct MobileRatingsResponse: Codable, Hashable, Sendable {
  let success: Bool
  let subjects: [RatingSubject]
}

struct RatingSubject: Codable, Hashable, Identifiable, Sendable {
  struct User: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: URL?
  }

  let user: User
  let score: Int?
  let updatedAt: String?
  let canEdit: Bool

  var id: String { user.id }
}

struct MobileRatingMutationResponse: Codable, Hashable, Sendable {
  let success: Bool
  let subjectUserId: String
  let score: Int?
  let cleared: Bool
  let operationId: String?
}

struct MobileRatedMediaResponse: Codable, Hashable, Sendable {
  let success: Bool
  let items: [RatedMediaEntry]
}

struct RatedMediaEntry: Codable, Hashable, Identifiable, Sendable {
  let media: MaxMediaItem
  let subjects: [RatingSubject]

  var id: String { media.id }
}

struct ProfileStickyNote: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let content: String?
  let authorName: String?
  let createdAt: String?
}

struct ProfileFavoritePin: Codable, Hashable, Identifiable, Sendable {
  let fileId: String
  let createdAt: String?

  var id: String { fileId }
}

struct ProfileRating: Codable, Hashable, Identifiable, Sendable {
  let fileId: String
  let name: String?
  let score: Double?
  let createdAt: String?

  var id: String { fileId }
}

struct CatalogEntry: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String?
  let subtitle: String?
  let posterUrl: URL?
  let artworkUrl: URL?
  let personalRating: Double?
  let mediaType: String?
}

struct ShowcaseCard: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String?
  let rarity: String?
  let ownerUserId: String?
}

struct WorkspaceSummary: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String?
  let ownerId: String?
  let coverUrl: String?
  let description: String?
  let spaceType: String?
  let itemCount: Int?
}

struct CollectionSummary: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String?
  let userId: String?
  let coverUrlFileId: String?
  let itemCount: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case userId
    case itemCount
    case coverUrlFileId = "coverUrl_fileId"
  }
}

struct DownloadSummary: Codable, Sendable {
  let scope: String
  let usedBytes: Int
  let items: [LocalDownload]
}

struct LocalDownload: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let localURL: URL
  let remoteURL: URL?
  let sizeBytes: Int
  let downloadedAt: Date
  let kind: String
}

struct MobileChatListResponse: Codable, Sendable {
  let success: Bool
  let chats: [ChatThread]
}

struct ChatPerson: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let username: String?
  let avatarUrl: URL?
}

struct MobileChatPeopleResponse: Codable, Sendable {
  let success: Bool
  let people: [ChatPerson]
}

struct MobileChatCreateResponse: Codable, Sendable {
  let success: Bool
  let operationId: String?
  let chat: ChatThread
}

struct ChatThread: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let isGroup: Bool
  let ownerId: String?
  let partnerId: String?
  let avatarUrl: URL?
  let lastMessage: String
  let lastMessageAt: String?
  let unreadCount: Int
  let isMuted: Bool?
  let isArchived: Bool?
  let mutedUntil: String?
  /// Disappearing-messages timer for the conversation, in seconds. nil = off.
  let messageTtlSeconds: Int?
  /// The caller's synced draft for this conversation, when one exists.
  let draft: String?

  init(
    id: String,
    title: String,
    isGroup: Bool,
    ownerId: String?,
    partnerId: String?,
    avatarUrl: URL?,
    lastMessage: String,
    lastMessageAt: String?,
    unreadCount: Int,
    isMuted: Bool? = nil,
    isArchived: Bool? = nil,
    mutedUntil: String? = nil,
    messageTtlSeconds: Int? = nil,
    draft: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isGroup = isGroup
    self.ownerId = ownerId
    self.partnerId = partnerId
    self.avatarUrl = avatarUrl
    self.lastMessage = lastMessage
    self.lastMessageAt = lastMessageAt
    self.unreadCount = unreadCount
    self.isMuted = isMuted
    self.isArchived = isArchived
    self.mutedUntil = mutedUntil
    self.messageTtlSeconds = messageTtlSeconds
    self.draft = draft
  }

  /// The self-conversation has no partner and no title — it is Saved Messages.
  /// Every surface that shows a conversation name goes through this so the
  /// otherwise-blank thread reads correctly.
  var displayTitle: String {
    if !isGroup, partnerId == nil { return "Saved Messages" }
    return title
  }

  /// A copy with the unread badge cleared, for the moment the user has provably
  /// seen the conversation — opening it, or sending into it — without waiting for
  /// the next list refresh to agree.
  func markingRead() -> ChatThread {
    ChatThread(
      id: id,
      title: title,
      isGroup: isGroup,
      ownerId: ownerId,
      partnerId: partnerId,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      unreadCount: 0,
      isMuted: isMuted,
      isArchived: isArchived,
      mutedUntil: mutedUntil,
      messageTtlSeconds: messageTtlSeconds,
      draft: draft
    )
  }
}

struct MobileMessagesResponse: Codable, Sendable {
  let success: Bool
  let messages: [ChatMessage]
}

struct MobileMessageSendResponse: Codable, Sendable {
  let success: Bool
  let operationId: String?
  let message: ChatMessage
}

/// A message written now and sent later by the worker. Dates stay RFC3339
/// strings, like every other model, so nanosecond timestamps cannot break
/// decoding.
struct ScheduledMessage: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let conversationId: String
  let body: String
  let sendAt: String
  let createdAt: String
}

/// The `{"items":[...]}` envelope the scheduled-messages listing answers with.
struct ScheduledMessageListResponse: Codable, Sendable {
  let items: [ScheduledMessage]
}

/// 100 normalised re-watch bins (0...1) — the scrubber's heat lane.
struct MediaHeatmapResponse: Codable, Sendable {
  let bins: [Double]
}

struct MobileCollectionMutationResponse: Codable, Hashable, Sendable {
  let success: Bool
  let collectionId: String
  let fileId: String
  let added: Bool
  let operationId: String?
}

struct ChatMessageActor: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let avatarUrl: URL?
}

struct ChatReplyPreview: Codable, Hashable, Sendable {
  let id: String
  let sender: ChatMessageActor?
  let content: String?
  let mediaType: String?
  let thumbnailUrl: URL?
  let isDeleted: Bool

  init(
    id: String,
    sender: ChatMessageActor?,
    content: String?,
    mediaType: String?,
    isDeleted: Bool,
    thumbnailUrl: URL? = nil
  ) {
    self.id = id
    self.sender = sender
    self.content = content
    self.mediaType = mediaType
    self.thumbnailUrl = thumbnailUrl
    self.isDeleted = isDeleted
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case sender
    case content
    case mediaType
    case thumbnailUrl
    case isDeleted
  }

  private enum WireCodingKeys: String, CodingKey {
    case messageId
    case senderId
    case senderName
    case body
  }

  // The server names the quoted message `messageId` and its text `body`, and it
  // sends the quoted sender as two flat fields rather than a nested object.
  // Decoding only the nested shape made every reply preview fail to decode,
  // which discarded the whole message it belonged to.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let wire = try decoder.container(keyedBy: WireCodingKeys.self)

    if let identifier = try container.decodeIfPresent(String.self, forKey: .id) {
      id = identifier
    } else {
      id = try wire.decode(String.self, forKey: .messageId)
    }

    if let nested = try container.decodeIfPresent(ChatMessageActor.self, forKey: .sender) {
      sender = nested
    } else {
      let name = try wire.decodeIfPresent(String.self, forKey: .senderName)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let senderId = try wire.decodeIfPresent(String.self, forKey: .senderId)
      if let name, !name.isEmpty {
        sender = ChatMessageActor(id: senderId ?? "", displayName: name, avatarUrl: nil)
      } else {
        sender = nil
      }
    }

    if let inline = try container.decodeIfPresent(String.self, forKey: .content) {
      content = inline
    } else {
      content = try wire.decodeIfPresent(String.self, forKey: .body)
    }
    mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    thumbnailUrl = try container.decodeIfPresent(URL.self, forKey: .thumbnailUrl)
    isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
  }
}

struct ChatForwardedOrigin: Codable, Hashable, Sendable {
  let messageId: String
  let dmId: String?
  let senderId: String?
  let senderName: String?
  let forwardedAt: String?
}

/// One piece of media hanging off a message, with URLs already signed by the
/// server. `openedAt` is set once a view-once attachment has been consumed.
struct ChatAttachment: Codable, Hashable, Identifiable, Sendable {
  var id: String { mediaId }
  let mediaId: String
  let kind: String?
  let mimeType: String?
  let name: String?
  let sizeBytes: Int?
  let url: URL?
  let thumbnailUrl: URL?
  let durationSeconds: Double?
  let width: Int?
  let height: Int?
  let openedAt: String?
  /// Text of a voice note, written by the sender via the transcript endpoint.
  let transcript: String?

  var resolvedKind: String {
    if let kind, !kind.isEmpty { return kind.lowercased() }
    let type = (mimeType ?? "").lowercased()
    if type.hasPrefix("video") { return "video" }
    if type.hasPrefix("audio") { return "audio" }
    if type.hasPrefix("image") { return "image" }
    return type.isEmpty ? "image" : "document"
  }

  /// A player/poster-ready item. Returns nil while the server withholds the URL,
  /// which it does for a view-once attachment that has not been opened yet.
  var mediaItem: MaxMediaItem? {
    guard let url else { return nil }
    return MaxMediaItem(
      id: mediaId,
      title: name ?? String(localized: "chat.message.media"),
      kind: resolvedKind,
      sizeBytes: sizeBytes ?? 0,
      duration: durationSeconds,
      mediaUrl: url,
      thumbnailUrl: thumbnailUrl,
      videoThumbnailUrl: nil,
      uploader: .init(id: nil, name: nil, avatarUrl: nil),
      workspace: nil,
      uploadedAt: nil,
      rating: nil,
      isFavorite: false,
      isSaved: false,
      lastPosition: 0,
      lastViewedAt: nil,
      isPrivate: false,
      downloadable: true
    )
  }
}

struct ChatReaction: Codable, Hashable, Identifiable, Sendable {
  var id: String { key }
  let key: String
  let count: Int
  let reactedByMe: Bool
  let userIds: [String]
}

struct ChatMessagePin: Codable, Hashable, Sendable {
  let pinnedBy: String
  let pinnedAt: String?
}

struct ChatReadReceipt: Codable, Hashable, Identifiable, Sendable {
  var id: String { userId }
  let userId: String
  let displayName: String?
  let avatarUrl: URL?
  let readAt: String?
}

struct ChatPollOption: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let text: String
  let voteCount: Int
  let votedByMe: Bool
}

struct ChatPoll: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let question: String
  let allowMultipleVotes: Bool
  let isClosed: Bool
  let createdBy: String
  let createdAt: String?
  let options: [ChatPollOption]

  var totalVotes: Int { options.reduce(0) { $0 + $1.voteCount } }
}

struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let dmId: String
  let senderId: String
  let content: String?
  let mediaUrl: String?
  let mediaType: String?
  let dmMediaId: String?
  let mediaName: String?
  let isEdited: Bool
  let isDeleted: Bool
  let isHardDeleted: Bool
  let isPinned: Bool?
  let pin: ChatMessagePin?
  let reactions: [ChatReaction]?
  let readReceipts: [ChatReadReceipt]?
  let poll: ChatPoll?
  let readAt: String?
  let replyToId: String?
  let createdAt: String?
  let mediaReferences: [MediaReference]?
  let sender: ChatMessageActor?
  let replyPreview: ChatReplyPreview?
  let forwardedFrom: ChatForwardedOrigin?
  let isViewOnce: Bool?
  let isViewOnceExpired: Bool?
  let attachments: [ChatAttachment]?
  /// When the message self-destructs (disappearing messages), ISO timestamp.
  let expiresAt: String?

  init(
    id: String,
    dmId: String,
    senderId: String,
    content: String?,
    mediaUrl: String?,
    mediaType: String?,
    dmMediaId: String?,
    mediaName: String?,
    isEdited: Bool,
    isDeleted: Bool,
    isHardDeleted: Bool,
    readAt: String?,
    replyToId: String?,
    createdAt: String?,
    mediaReferences: [MediaReference]?,
    sender: ChatMessageActor? = nil,
    replyPreview: ChatReplyPreview? = nil,
    isPinned: Bool? = nil,
    pin: ChatMessagePin? = nil,
    reactions: [ChatReaction]? = nil,
    readReceipts: [ChatReadReceipt]? = nil,
    poll: ChatPoll? = nil,
    forwardedFrom: ChatForwardedOrigin? = nil,
    isViewOnce: Bool? = nil,
    isViewOnceExpired: Bool? = nil,
    attachments: [ChatAttachment]? = nil,
    expiresAt: String? = nil
  ) {
    self.id = id
    self.dmId = dmId
    self.senderId = senderId
    self.content = content
    self.mediaUrl = mediaUrl
    self.mediaType = mediaType
    self.dmMediaId = dmMediaId
    self.mediaName = mediaName
    self.isEdited = isEdited
    self.isDeleted = isDeleted
    self.isHardDeleted = isHardDeleted
    self.isPinned = isPinned
    self.pin = pin
    self.reactions = reactions
    self.readReceipts = readReceipts
    self.poll = poll
    self.readAt = readAt
    self.replyToId = replyToId
    self.createdAt = createdAt
    self.mediaReferences = mediaReferences
    self.sender = sender
    self.replyPreview = replyPreview
    self.forwardedFrom = forwardedFrom
    self.isViewOnce = isViewOnce
    self.isViewOnceExpired = isViewOnceExpired
    self.attachments = attachments
    self.expiresAt = expiresAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case dmId
    case senderId
    case content
    case mediaUrl
    case mediaType
    case dmMediaId
    case mediaName
    case isEdited
    case isDeleted
    case isHardDeleted
    case isPinned
    case pin
    case reactions
    case readReceipts
    case poll
    case readAt
    case replyToId
    case createdAt
    case mediaReferences
    case sender
    case replyPreview
    case forwardedFrom
    case isViewOnce
    case isViewOnceExpired
    case attachments
    case expiresAt
  }

  /// Keys the server sends flat that this model stores in a nested shape.
  private enum WireCodingKeys: String, CodingKey {
    case senderName
    case senderAvatarUrl
    case viewOnce
  }

  // Every mutation endpoint (edit, delete, pin, react, forward, poll vote) and
  // both the search and pinned lists return the server's message shape, which
  // carries the sender as flat `senderName`/`senderAvatarUrl` fields. Relying on
  // synthesised decoding left `sender` nil on all of those paths, so a message
  // lost its author the moment anyone touched it.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let wire = try decoder.container(keyedBy: WireCodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    dmId = try container.decodeIfPresent(String.self, forKey: .dmId) ?? ""
    senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
    content = try container.decodeIfPresent(String.self, forKey: .content)
    dmMediaId = try container.decodeIfPresent(String.self, forKey: .dmMediaId)
    mediaName = try container.decodeIfPresent(String.self, forKey: .mediaName)
    isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
    isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    isHardDeleted = try container.decodeIfPresent(Bool.self, forKey: .isHardDeleted) ?? false
    isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
    pin = try container.decodeIfPresent(ChatMessagePin.self, forKey: .pin)
    reactions = try container.decodeIfPresent([ChatReaction].self, forKey: .reactions)
    readReceipts = try container.decodeIfPresent([ChatReadReceipt].self, forKey: .readReceipts)
    poll = try container.decodeIfPresent(ChatPoll.self, forKey: .poll)
    readAt = try container.decodeIfPresent(String.self, forKey: .readAt)
    replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
    createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    mediaReferences = try container.decodeIfPresent([MediaReference].self, forKey: .mediaReferences)
    replyPreview = try container.decodeIfPresent(ChatReplyPreview.self, forKey: .replyPreview)
    forwardedFrom = try container.decodeIfPresent(ChatForwardedOrigin.self, forKey: .forwardedFrom)
    expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)

    let decodedAttachments = try container.decodeIfPresent(
      [ChatAttachment].self,
      forKey: .attachments
    )
    attachments = (decodedAttachments?.isEmpty ?? true) ? nil : decodedAttachments
    let firstAttachment = attachments?.first

    if let nested = try container.decodeIfPresent(ChatMessageActor.self, forKey: .sender) {
      sender = nested
    } else {
      let name = try wire.decodeIfPresent(String.self, forKey: .senderName)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let avatarUrl = try wire.decodeIfPresent(URL.self, forKey: .senderAvatarUrl)
      if let name, !name.isEmpty {
        sender = ChatMessageActor(id: senderId, displayName: name, avatarUrl: avatarUrl)
      } else {
        sender = nil
      }
    }

    let inlineMediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
    mediaUrl = inlineMediaUrl ?? firstAttachment?.url?.absoluteString
    let inlineMediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    mediaType = inlineMediaType ?? firstAttachment?.mimeType

    let declaredViewOnce = try container.decodeIfPresent(Bool.self, forKey: .isViewOnce)
    let wireViewOnce = try wire.decodeIfPresent(Bool.self, forKey: .viewOnce)
    isViewOnce = declaredViewOnce ?? wireViewOnce
    let declaredExpiry = try container.decodeIfPresent(Bool.self, forKey: .isViewOnceExpired)
    // `openedAt` on the attachment is the server's record that a view-once photo
    // has been consumed; without honouring it the bubble keeps offering an Open
    // button for a photo that can never open again.
    let consumedAttachment = attachments?.contains(where: { $0.openedAt != nil })
    isViewOnceExpired = declaredExpiry ?? consumedAttachment
  }
}

extension ChatMessage {
  /// Player-ready attachments. Prefers the server's `attachments[]` payload and
  /// falls back to the legacy `mediaReferences` projection.
  var attachmentMediaItems: [MaxMediaItem] {
    let fromAttachments = (attachments ?? []).compactMap(\.mediaItem)
    if !fromAttachments.isEmpty { return fromAttachments }
    return (mediaReferences ?? []).compactMap { reference in
      guard case .media(let item) = reference.file else { return nil }
      return item
    }
  }

  var isViewOnceConsumed: Bool {
    if let isViewOnceExpired { return isViewOnceExpired }
    return (attachments ?? []).contains(where: { $0.openedAt != nil })
  }

  /// Normalises the wire's MIME type into the four media kinds the app renders.
  var resolvedMediaKind: String {
    if let attachment = attachments?.first { return attachment.resolvedKind }
    let type = (mediaType ?? "").lowercased()
    if type.hasPrefix("video") { return "video" }
    if type.hasPrefix("audio") { return "audio" }
    if type.hasPrefix("image") { return "image" }
    if type.isEmpty { return "image" }
    return type == "document" ? "document" : type
  }
}

extension ChatMessage {
  func replacingReactions(_ reactions: [ChatReaction]) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: dmId,
      senderId: senderId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      dmMediaId: dmMediaId,
      mediaName: mediaName,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isHardDeleted: isHardDeleted,
      readAt: readAt,
      replyToId: replyToId,
      createdAt: createdAt,
      mediaReferences: mediaReferences,
      sender: sender,
      replyPreview: replyPreview,
      isPinned: isPinned,
      pin: pin,
      reactions: reactions,
      readReceipts: readReceipts,
      poll: poll,
      forwardedFrom: forwardedFrom,
      // Dropping these turned a view-once photo into an ordinary one the moment
      // somebody reacted to it, defeating the protection until the next reload.
      isViewOnce: isViewOnce,
      isViewOnceExpired: isViewOnceExpired,
      attachments: attachments,
      expiresAt: expiresAt
    )
  }
}

struct MobileChatReactionMutationResponse: Codable, Sendable {
  let success: Bool
  let dmId: String
  let messageId: String
  let reactionKey: String?
  let previousReactionKey: String?
  let reactions: [ChatReaction]
}

struct ChatThreadPreference: Codable, Hashable, Sendable {
  let dmId: String
  let userId: String
  let isMuted: Bool
  let isArchived: Bool
  let mutedUntil: String?
  let updatedAt: String?
}

struct MobileChatPreferenceResponse: Codable, Sendable {
  let success: Bool
  let preference: ChatThreadPreference
}

struct MobileChatPreferenceMutationResponse: Codable, Sendable {
  let success: Bool
  let preference: ChatThreadPreference
  let previous: ChatThreadPreference?
}

struct ChatGroupMember: Codable, Hashable, Identifiable, Sendable {
  var id: String { userId }
  let userId: String
  let displayName: String
  let avatarUrl: URL?
  let role: String
  let joinedAt: String?
}

struct MobileChatMembersResponse: Codable, Sendable {
  let success: Bool
  let members: [ChatGroupMember]
}

struct ChatActivity: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let dmId: String
  let messageId: String?
  let kind: String
  let actorId: String
  let createdAt: String?
  let readAt: String?
  let actorName: String?
  let actorAvatar: URL?
  let isGroup: Bool?
  let groupName: String?
  let groupAvatar: URL?
  let content: String?
}

extension ChatActivity {
  /// Local echo of a successful "mark read" so the feed updates without a refetch.
  func markingRead() -> ChatActivity {
    ChatActivity(
      id: id,
      dmId: dmId,
      messageId: messageId,
      kind: kind,
      actorId: actorId,
      createdAt: createdAt,
      readAt: ISO8601DateFormatter().string(from: Date()),
      actorName: actorName,
      actorAvatar: actorAvatar,
      isGroup: isGroup,
      groupName: groupName,
      groupAvatar: groupAvatar,
      content: content
    )
  }
}

struct MobileChatActivityResponse: Codable, Sendable {
  let success: Bool
  let activities: [ChatActivity]
}

struct MobileChatActivityReadResponse: Codable, Sendable {
  let success: Bool
  let markedCount: Int
}

struct MobileChatGroupMutationResponse: Codable, Sendable {
  let success: Bool
  let dmId: String
  let group: ChatGroupInfo?
}

struct ChatGroupInfo: Codable, Hashable, Sendable {
  let id: String
  let groupName: String?
  let groupAvatar: URL?
  let ownerId: String?
  let lastMessageAt: String?
}

struct MobileChatMemberMutationResponse: Codable, Sendable {
  let success: Bool
}

struct MediaReference: Codable, Hashable, Sendable {
  struct LockedFile: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: String
  }

  enum ReferenceFile: Codable, Hashable, Sendable {
    case media(MaxMediaItem)
    case locked(LockedFile)

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let item = try? container.decode(MaxMediaItem.self) {
        self = .media(item)
      } else {
        self = .locked(try container.decode(LockedFile.self))
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .media(let item): try container.encode(item)
      case .locked(let item): try container.encode(item)
      }
    }
  }

  let state: String
  let file: ReferenceFile
  let requestAccessSupported: Bool
}

struct MobileUploadResponse: Codable, Sendable {
  struct Upload: Codable, Sendable {
    let url: URL?
    let method: String?
    let filePath: String?
    let fields: [String: String]?
  }

  let success: Bool
  let upload: Upload
}

struct MobileUploadRegisterResponse: Codable, Sendable {
  let success: Bool
  let fileId: String?
  let filePath: String?
  let fileType: String?
  let sizeBytes: Int?
  let operationId: String?
}

struct MobileAccessRequestsResponse: Codable, Sendable {
  let success: Bool
  let incoming: [AccessRequest]
  let outgoing: [AccessRequest]
}

struct MobileAccessDecisionResponse: Codable, Sendable {
  let success: Bool
  let request: AccessRequest
  let alreadyDecided: Bool?
}

struct AccessRequest: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let fileId: String
  let requesterUserId: String
  let ownerUserId: String
  let messageId: String?
  let note: String?
  let status: String
  let shareId: String?
  let createdAt: String?
  let decidedAt: String?
  let decidedBy: String?
  let fileName: String?
  let requesterName: String?
}

struct MediaQuery: Codable, Hashable, Sendable {
  var mode = "browse"
  var search = ""
  var kind: String?
  var unwatched = false
  var unrated = false
  var saved = false
  var year: Int?
  var collectionId: String?
  var workspaceId: String?
  /// Only media owned by this user (the visitable-profile grid). The server's
  /// visibility rules still gate what actually comes back.
  var ownerId: String?
  var limit = 40
  var offset = 0

  var queryString: String {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "q", value: search.isEmpty ? nil : search),
      URLQueryItem(name: "kind", value: kind),
      URLQueryItem(name: "unwatched", value: unwatched ? "true" : nil),
      URLQueryItem(name: "unrated", value: unrated ? "true" : nil),
      URLQueryItem(name: "saved", value: saved ? "true" : nil),
      URLQueryItem(name: "year", value: year.map(String.init)),
      URLQueryItem(name: "collectionId", value: collectionId),
      URLQueryItem(name: "workspaceId", value: workspaceId),
      URLQueryItem(name: "ownerId", value: ownerId),
      URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))),
      URLQueryItem(name: "offset", value: String(max(offset, 0))),
    ].filter { $0.value != nil }
    return components.percentEncodedQuery.map { "?\($0)" } ?? ""
  }
}

extension Int {
  var byteString: String {
    ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
  }
}

extension String {
  /// A stored filename rewritten as something worth showing a person.
  ///
  /// Drops the extension and turns `_`/`-` runs into spaces, so `IMG_4312.MOV`
  /// reads as "IMG 4312" instead of leaking the file system into the UI. Falls
  /// back to the original whenever that would leave nothing, so an item somebody
  /// deliberately named is never mangled.
  var asMediaDisplayName: String {
    let cleaned = strippingMediaFileExtension
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
    return cleaned.isEmpty ? self : cleaned
  }

  /// Removes a trailing extension only when it actually looks like one.
  ///
  /// A blanket `deletingPathExtension` also eats the tail of a legitimate title —
  /// "Take 2.0" becomes "Take 2" — so the suffix has to be short and purely
  /// alphanumeric before it is treated as a file extension.
  private var strippingMediaFileExtension: String {
    let base = (self as NSString).deletingPathExtension
    let suffix = (self as NSString).pathExtension
    guard !base.isEmpty,
          (2...5).contains(suffix.count),
          suffix.allSatisfy({ $0.isLetter || $0.isNumber }),
          suffix.contains(where: { $0.isLetter })
    else { return self }
    return base
  }
}

extension Double {
  var minuteString: String {
    guard isFinite else { return "0:00" }
    let seconds = Int(self)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}
