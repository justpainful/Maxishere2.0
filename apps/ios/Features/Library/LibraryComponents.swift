import Foundation
import SwiftUI

enum MaxLibrarySort: String, CaseIterable, Identifiable, Hashable {
  case recent
  case name

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .recent: "library.sort.recent"
    case .name: "library.sort.name"
    }
  }

  func apply(to items: [MaxMediaItem]) -> [MaxMediaItem] {
    switch self {
    case .recent:
      items.sorted { lhs, rhs in
        let leftDate = lhs.uploadedAt ?? ""
        let rightDate = rhs.uploadedAt ?? ""
        if leftDate == rightDate {
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return leftDate > rightDate
      }
    case .name:
      items.sorted {
        $0.title.localizedStandardCompare($1.title) == .orderedAscending
      }
    }
  }
}

enum MaxLibraryKindFilter: String, CaseIterable, Identifiable, Hashable {
  case all
  case video
  case image
  case audio
  case document

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .all: "home.filter.all"
    case .video: "media.kind.video"
    case .image: "media.kind.media"
    case .audio: "media.kind.audio"
    case .document: "media.kind.document"
    }
  }

  func includes(_ item: MaxMediaItem) -> Bool {
    self == .all || item.kind == rawValue
  }
}

struct MaxLibraryDestinationCard: View {
  @Environment(\.appTheme) private var appTheme
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  let systemImage: String
  let accent: Color
  let count: Int?

  var body: some View {
    let isCouncil = appTheme == .council
    let resolvedAccent = isCouncil
      ? (systemImage.contains("heart") ? CouncilColor.royalCrimson : (systemImage.contains("sparkles") ? CouncilColor.activeCrimson : CouncilColor.coldSilver))
      : accent

    MaxContentSurface(padding: MaxSpace.md) {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        HStack(alignment: .top) {
          Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(resolvedAccent)
            .frame(width: 44, height: 44)
            .background(resolvedAccent.opacity(isCouncil ? 0.20 : 0.13), in: RoundedRectangle(
              cornerRadius: MaxRadius.small,
              style: .continuous
            ))

          Spacer(minLength: MaxSpace.xs)

          if let count {
            Text(verbatim: count.formatted())
              .font(.caption.weight(.semibold))
              .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.primaryText) : AnyShapeStyle(MaxColor.textSecondary))
              .padding(.horizontal, MaxSpace.xs)
              .padding(.vertical, MaxSpace.xxs)
              .background(isCouncil ? AnyShapeStyle(CouncilColor.obsidianSurface) : AnyShapeStyle(MaxColor.surfaceSoft), in: Capsule())
          }
        }

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(title)
            .font(isCouncil ? CouncilTypography.headline : .headline)
            .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.primaryText) : AnyShapeStyle(MaxColor.textPrimary))
          Text(subtitle)
            .font(isCouncil ? CouncilTypography.caption : .caption)
            .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.secondaryText) : AnyShapeStyle(MaxColor.textSecondary))
            .lineLimit(3)
        }

        Spacer(minLength: 0)

        Image(systemName: "arrow.up.forward")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.tertiaryText) : AnyShapeStyle(MaxColor.textTertiary))
          .frame(maxWidth: .infinity, alignment: .trailing)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

struct MaxVaultContinueCard: View {
  let item: MaxMediaItem
  let isOffline: Bool

  var body: some View {
    ZStack(alignment: .bottom) {
      MaxMediaPoster(item: item, compact: false, showsMetadata: false)
        .frame(maxWidth: .infinity)

      LinearGradient(
        colors: [.clear, Color.black.opacity(0.78)],
        startPoint: .center,
        endPoint: .bottom
      )

      VStack(spacing: MaxSpace.xs) {
        if let progressFraction {
          ProgressView(value: progressFraction)
            .tint(.white)
            .accessibilityValue(Text(verbatim: progressPercent))
        }

        HStack(spacing: MaxSpace.xs) {
          Image(systemName: "play.fill")
          Text(verbatim: item.lastPosition.minuteString)
          if let duration = item.duration, duration > 0 {
            Text(verbatim: "/ \(duration.minuteString)")
          }
          Spacer(minLength: 0)
          if isOffline {
            Image(systemName: "arrow.down.circle.fill")
              .accessibilityLabel(Text("storage.offline.title"))
          }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
      }
      .padding(MaxSpace.sm)
    }
    .frame(width: 268)
    .aspectRatio(16 / 10, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("home.section.continue"))
    .accessibilityValue(Text(verbatim: item.kind))
  }

  private var progressFraction: Double? {
    guard let duration = item.duration, duration > 0 else { return nil }
    return min(max(item.lastPosition / duration, 0), 1)
  }

  private var progressPercent: String {
    let percent = Int((progressFraction ?? 0) * 100)
    return "\(percent)%"
  }
}

struct MaxVaultMediaCard: View {
  let item: MaxMediaItem
  let isOffline: Bool
  let transferProgress: Double?

  var body: some View {
    ZStack {
      // The masonry column sizes this card from the item's own dimensions, so
      // the poster must not re-impose a shape of its own.
      MaxMediaPoster(item: item, compact: true, showsMetadata: false, usesContainerShape: true)
        .frame(maxWidth: .infinity)

      LinearGradient(
        colors: [.clear, Color.black.opacity(0.66)],
        startPoint: .center,
        endPoint: .bottom
      )

      VStack {
        HStack(spacing: MaxSpace.xxs) {
          Spacer(minLength: 0)
          if item.isSaved || item.isFavorite {
            Image(systemName: "heart.fill")
              .accessibilityLabel(Text("library.saved"))
          }
          if isOffline {
            Image(systemName: "arrow.down.circle.fill")
              .accessibilityLabel(Text("storage.offline.title"))
          }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(MaxSpace.sm)

        Spacer(minLength: 0)

        VStack(spacing: MaxSpace.xs) {
          if let visibleProgress {
            ProgressView(value: visibleProgress)
              .tint(.white)
          }

          HStack(spacing: MaxSpace.xs) {
            Image(systemName: item.kind == "video" ? "play.fill" : "photo.fill")
            if item.kind == "video", let duration = item.duration, duration > 0 {
              Text(verbatim: duration.minuteString)
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let rating = item.rating {
              Label("\(rating)", systemImage: "star.fill")
                .foregroundStyle(MaxColor.warning)
            }
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
        }
        .padding(MaxSpace.sm)
      }
    }
    .frame(maxWidth: .infinity)
    // No forced square. A square cell cropped every portrait video to its middle,
    // which is what read as "zoomed in"; the enclosing masonry column now sets the
    // height from the media's real aspect ratio.
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      item.kind == "video" ? Text("media.kind.video") : Text("media.kind.media")
    )
  }

  private var visibleProgress: Double? {
    if let transferProgress {
      return min(max(transferProgress, 0), 1)
    }
    return playbackProgress
  }

  private var playbackProgress: Double? {
    guard item.hasProgress, let duration = item.duration, duration > 0 else { return nil }
    return min(max(item.lastPosition / duration, 0), 1)
  }
}

struct MaxLibraryMediaRow: View {
  let item: MaxMediaItem
  let showsSavedState: Bool
  let isOffline: Bool

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      MaxMediaPoster(item: item, compact: true, showsMetadata: false)
        .frame(width: 78, height: 78)

      VStack(alignment: .leading, spacing: MaxSpace.xs) {
        Text(verbatim: item.displayTitle)
          .font(.body.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .lineLimit(2)

        if let sourceName {
          Text(verbatim: sourceName)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .lineLimit(1)
        }

        HStack(spacing: MaxSpace.sm) {
          if showsSavedState {
            Label("library.saved", systemImage: "heart.fill")
              .foregroundStyle(MaxColor.accent)
          }
          if let rating = item.rating {
            Label("\(rating)/10", systemImage: "star.fill")
              .foregroundStyle(MaxColor.warning)
          }
          if isOffline {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(MaxColor.mint)
              .accessibilityLabel(Text("storage.offline.title"))
          }
        }
        .font(.caption.weight(.semibold))
      }

      Spacer(minLength: 0)

      Image(systemName: "chevron.forward")
        .font(.caption.weight(.semibold))
        .foregroundStyle(MaxColor.textTertiary)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.title))
  }

  private var sourceName: String? {
    item.workspace?.name ?? item.uploader.name
  }
}

struct MaxLibraryTransferRow: View {
  let record: TransferRecord

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: record.kind == .download ? "arrow.down" : "arrow.up")
        .font(.body.weight(.semibold))
        .foregroundStyle(MaxColor.accent)
        .frame(width: 38, height: 38)
        .background(MaxColor.surfaceSoft, in: Circle())

      VStack(alignment: .leading, spacing: MaxSpace.xs) {
        HStack {
          Text(verbatim: record.displayName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 0)
          Text(stateKey)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
        }

        if let progress = record.progress {
          ProgressView(value: progress)
            .tint(MaxColor.accent)
        } else if record.state.isActive {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }

  private var stateKey: LocalizedStringKey {
    switch record.state {
    case .queued: "transfer.state.queued"
    case .preparing: "transfer.state.preparing"
    case .uploading: "transfer.state.uploading"
    case .downloading: "transfer.state.downloading"
    case .completed: "transfer.state.completed"
    case .failed: "transfer.state.failed"
    case .cancelled: "transfer.state.cancelled"
    case .retrying: "transfer.state.retrying"
    }
  }
}
