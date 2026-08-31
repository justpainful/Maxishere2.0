import Foundation
import SwiftUI

enum ReleaseVisualStyle: String, CaseIterable, Identifiable, Sendable {
  case mobileLaunch
  case memories
  case settings
  case featurePreview

  var id: String { rawValue }
}

enum ReleaseDestination: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case home
  case library
  case create
  case chats
  case profile
  case memories
  case settings

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .home: "tab.home"
    case .library: "tab.vault"
    case .create: "upload.title"
    case .chats: "tab.chats"
    case .profile: "tab.profile"
    case .memories: "memories.library.title"
    case .settings: "settings.title"
    }
  }

  var symbolName: String {
    switch self {
    case .home: "house.fill"
    case .library: "archivebox.fill"
    case .create: "square.and.arrow.up"
    case .chats: "bubble.left.and.bubble.right.fill"
    case .profile: "person.crop.circle.fill"
    case .memories: "rectangle.stack.fill"
    case .settings: "gearshape.fill"
    }
  }
}

enum ReleasePresentationStyle: String, Codable, Hashable, Sendable {
  case longLaunch
  case compactLaunch
  case featureUpdate

  var ctaTitleKey: String {
    switch self {
    case .longLaunch: "release.cta.start"
    case .compactLaunch: "release.cta.got_it"
    case .featureUpdate: "release.cta.open"
    }
  }
}

struct ReleaseFeatureItem: Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let subtitle: String?
  let symbolName: String

  init(id: String, title: String, subtitle: String? = nil, symbolName: String) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.symbolName = symbolName
  }
}

struct ReleaseAnnouncement: Identifiable, Hashable, Sendable {
  let id: String
  let minimumAppBuild: Int
  let title: String
  let subtitle: String
  let featureItems: [ReleaseFeatureItem]
  let destination: ReleaseDestination
  let presentationStyle: ReleasePresentationStyle
  let showBadgeUntil: Date?
  let hasBeenSeen: Bool
  let visualStyle: ReleaseVisualStyle

  init(
    id: String,
    minimumAppBuild: Int,
    title: String,
    subtitle: String,
    featureItems: [ReleaseFeatureItem],
    destination: ReleaseDestination,
    presentationStyle: ReleasePresentationStyle,
    showBadgeUntil: Date?,
    hasBeenSeen: Bool = false,
    visualStyle: ReleaseVisualStyle
  ) {
    self.id = id
    self.minimumAppBuild = minimumAppBuild
    self.title = title
    self.subtitle = subtitle
    self.featureItems = featureItems
    self.destination = destination
    self.presentationStyle = presentationStyle
    self.showBadgeUntil = showBadgeUntil
    self.hasBeenSeen = hasBeenSeen
    self.visualStyle = visualStyle
  }

  func seen(_ value: Bool) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: id,
      minimumAppBuild: minimumAppBuild,
      title: title,
      subtitle: subtitle,
      featureItems: featureItems,
      destination: destination,
      presentationStyle: presentationStyle,
      showBadgeUntil: showBadgeUntil,
      hasBeenSeen: value,
      visualStyle: visualStyle
    )
  }

  func presented(as style: ReleasePresentationStyle) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: id,
      minimumAppBuild: minimumAppBuild,
      title: title,
      subtitle: subtitle,
      featureItems: featureItems,
      destination: destination,
      presentationStyle: style,
      showBadgeUntil: showBadgeUntil,
      hasBeenSeen: hasBeenSeen,
      visualStyle: visualStyle
    )
  }
}

extension ReleaseAnnouncement {
  static let mobileLaunchID = "max-mobile-launch-v1"
  static let memoriesID = "max-memories-v1"
  static let settingsID = "max-settings-v2"
  static let chatsV2ID = "max-chats-v2"
  static let mediaV2ID = "max-media-v2"

  static func defaultAnnouncements(
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current
  ) -> [ReleaseAnnouncement] {
    [
      mobileLaunch(
        presentationStyle: .longLaunch,
        releaseDate: releaseDate,
        calendar: calendar
      ),
      memories(releaseDate: releaseDate, calendar: calendar),
      settings(releaseDate: releaseDate, calendar: calendar),
      chatsV2(releaseDate: releaseDate, calendar: calendar),
      mediaV2(releaseDate: releaseDate, calendar: calendar),
    ]
  }

  static func chatsV2(
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: chatsV2ID,
      minimumAppBuild: 2,
      title: "release.chats_v2.title",
      subtitle: "release.chats_v2.subtitle",
      featureItems: [
        ReleaseFeatureItem(id: "inline-edit", title: "release.chats_v2.feature.edit", symbolName: "pencil.line"),
        ReleaseFeatureItem(id: "media", title: "release.chats_v2.feature.media", subtitle: "release.chats_v2.feature.media.subtitle", symbolName: "play.rectangle.fill"),
        ReleaseFeatureItem(id: "privacy", title: "release.chats_v2.feature.privacy", subtitle: "release.chats_v2.feature.privacy.subtitle", symbolName: "lock.shield.fill"),
      ],
      destination: .chats,
      presentationStyle: .featureUpdate,
      showBadgeUntil: badgeUntil(from: releaseDate, calendar: calendar),
      hasBeenSeen: hasBeenSeen,
      visualStyle: .featurePreview
    )
  }

  static func mediaV2(
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: mediaV2ID,
      minimumAppBuild: 2,
      title: "release.media_v2.title",
      subtitle: "release.media_v2.subtitle",
      featureItems: [
        ReleaseFeatureItem(id: "fit", title: "release.media_v2.feature.fit", symbolName: "rectangle.inset.filled"),
        ReleaseFeatureItem(id: "controls", title: "release.media_v2.feature.controls", symbolName: "play.circle.fill"),
        ReleaseFeatureItem(id: "smart", title: "release.media_v2.feature.smart", subtitle: "release.media_v2.feature.smart.subtitle", symbolName: "sparkles.tv.fill"),
      ],
      destination: .memories,
      presentationStyle: .featureUpdate,
      showBadgeUntil: badgeUntil(from: releaseDate, calendar: calendar),
      hasBeenSeen: hasBeenSeen,
      visualStyle: .memories
    )
  }

  static func mobileLaunch(
    presentationStyle: ReleasePresentationStyle,
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: mobileLaunchID,
      minimumAppBuild: 1,
      title: "release.mobile_launch.title",
      subtitle: "release.mobile_launch.subtitle",
      featureItems: [
        ReleaseFeatureItem(
          id: "native-shell",
          title: "release.mobile_launch.feature.shell",
          symbolName: "square.grid.3x3.fill"
        ),
        ReleaseFeatureItem(
          id: "private-media",
          title: "release.mobile_launch.feature.media",
          symbolName: "lock.shield.fill"
        ),
        ReleaseFeatureItem(
          id: "memories",
          title: "release.mobile_launch.feature.memories",
          symbolName: "rectangle.stack.fill"
        ),
      ],
      destination: .home,
      presentationStyle: presentationStyle,
      showBadgeUntil: nil,
      hasBeenSeen: hasBeenSeen,
      visualStyle: .mobileLaunch
    )
  }

  static func memories(
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: memoriesID,
      minimumAppBuild: 1,
      title: "release.memories.title",
      subtitle: "release.memories.subtitle",
      featureItems: [
        ReleaseFeatureItem(
          id: "sources",
          title: "release.memories.feature.sources",
          subtitle: "release.memories.feature.sources.subtitle",
          symbolName: "square.stack.3d.up.fill"
        ),
        ReleaseFeatureItem(
          id: "privacy",
          title: "release.memories.feature.privacy",
          subtitle: "release.memories.feature.privacy.subtitle",
          symbolName: "lock.shield.fill"
        ),
        ReleaseFeatureItem(
          id: "share",
          title: "release.memories.feature.share",
          subtitle: "release.memories.feature.share.subtitle",
          symbolName: "paperplane.fill"
        ),
      ],
      destination: .memories,
      presentationStyle: .featureUpdate,
      showBadgeUntil: badgeUntil(from: releaseDate, calendar: calendar),
      hasBeenSeen: hasBeenSeen,
      visualStyle: .memories
    )
  }

  static func settings(
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: settingsID,
      minimumAppBuild: 1,
      title: "release.settings.title",
      subtitle: "release.settings.subtitle",
      featureItems: [
        ReleaseFeatureItem(
          id: "whats-new",
          title: "release.settings.feature.whats_new",
          subtitle: "release.settings.feature.whats_new.subtitle",
          symbolName: "sparkles.rectangle.stack.fill"
        ),
        ReleaseFeatureItem(
          id: "connection",
          title: "release.settings.feature.connection",
          subtitle: "release.settings.feature.connection.subtitle",
          symbolName: "server.rack"
        ),
        ReleaseFeatureItem(
          id: "account",
          title: "release.settings.feature.account",
          subtitle: "release.settings.feature.account.subtitle",
          symbolName: "person.text.rectangle.fill"
        ),
      ],
      destination: .settings,
      presentationStyle: .featureUpdate,
      showBadgeUntil: badgeUntil(from: releaseDate, calendar: calendar),
      hasBeenSeen: hasBeenSeen,
      visualStyle: .settings
    )
  }

  static func featurePreview(
    id: String = "max-feature-preview-v1",
    releaseDate: Date = ReleaseAnnouncement.releaseReferenceDate,
    calendar: Calendar = .current,
    hasBeenSeen: Bool = false
  ) -> ReleaseAnnouncement {
    ReleaseAnnouncement(
      id: id,
      minimumAppBuild: 1,
      title: "release.feature_preview.title",
      subtitle: "release.feature_preview.subtitle",
      featureItems: [
        ReleaseFeatureItem(
          id: "native",
          title: "release.feature_preview.feature.native",
          subtitle: "release.feature_preview.feature.native.subtitle",
          symbolName: "iphone"
        ),
        ReleaseFeatureItem(
          id: "reusable",
          title: "release.feature_preview.feature.reusable",
          subtitle: "release.feature_preview.feature.reusable.subtitle",
          symbolName: "square.stack.3d.forward.dottedline"
        ),
        ReleaseFeatureItem(
          id: "private",
          title: "release.feature_preview.feature.private",
          subtitle: "release.feature_preview.feature.private.subtitle",
          symbolName: "lock.fill"
        ),
      ],
      destination: .home,
      presentationStyle: .featureUpdate,
      showBadgeUntil: badgeUntil(from: releaseDate, calendar: calendar),
      hasBeenSeen: hasBeenSeen,
      visualStyle: .featurePreview
    )
  }

  private static let releaseReferenceDate: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 30
    return Calendar(identifier: .gregorian).date(from: components) ??
      Date(timeIntervalSince1970: 1_782_768_000)
  }()

  private static func badgeUntil(from date: Date, calendar: Calendar) -> Date? {
    calendar.date(byAdding: .day, value: 14, to: date)
  }
}
