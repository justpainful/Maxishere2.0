@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Applies a fixed aspect ratio, or none when the parent already decides the shape.
private struct MaxPosterShape: ViewModifier {
  let ratio: CGFloat?

  func body(content: Content) -> some View {
    if let ratio {
      content.aspectRatio(ratio, contentMode: .fill)
    } else {
      // Fill the space the parent allotted. The parent sized it from the item's
      // real dimensions, so filling crops nothing meaningful.
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct MaxMediaPoster: View {
  let item: MaxMediaItem
  let compact: Bool
  let showsMetadata: Bool
  /// When true the poster adopts the shape its parent gives it.
  ///
  /// A masonry column already sizes each tile from the item's own dimensions, so
  /// imposing a second ratio here would crop the media back into the wrong shape
  /// — the reason portrait video rendered zoomed in.
  let usesContainerShape: Bool

  init(
    item: MaxMediaItem,
    compact: Bool = false,
    showsMetadata: Bool = true,
    usesContainerShape: Bool = false
  ) {
    self.item = item
    self.compact = compact
    self.showsMetadata = showsMetadata
    self.usesContainerShape = usesContainerShape
  }

  var body: some View {
    let radius = compact ? MaxRadius.small : MaxRadius.large

    ZStack(alignment: .bottomLeading) {
      posterContent
        .modifier(MaxPosterShape(ratio: usesContainerShape ? nil : (compact ? 1 : 16 / 10)))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

      if showsMetadata {
        LinearGradient(
          colors: [.clear, Color.black.opacity(0.28), Color.black.opacity(0.90)],
          startPoint: .top,
          endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          if item.isPrivate {
            Label("media.shared_privately", systemImage: "lock.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
          }
          Text(verbatim: item.displayTitle)
            .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(compact ? 2 : 3)
          if let source = item.workspace?.name ?? item.uploader.name, !source.isEmpty {
            Text(verbatim: source)
              .font(.caption)
              .foregroundStyle(.white)
              .lineLimit(1)
          }
        }
        .padding(compact ? MaxSpace.sm : MaxSpace.md)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .clipped()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.title))
    .accessibilityValue(Text(verbatim: item.kind))
  }

  @ViewBuilder
  private var posterContent: some View {
    if let posterURL = item.posterURL {
      MaxAsyncImage(url: posterURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        case .failure:
          videoPosterOrPlaceholder
        case .empty:
          posterPlaceholder
            .overlay { ProgressView() }
        @unknown default:
          videoPosterOrPlaceholder
        }
      }
    } else {
      videoPosterOrPlaceholder
    }
  }

  @ViewBuilder
  private var videoPosterOrPlaceholder: some View {
    if item.kind.lowercased() == "video", let mediaURL = item.mediaUrl {
      // Legacy records may have no thumbnail, and a signed thumbnail URL can
      // expire independently of its video URL. In either case, use the first
      // decodable video frame instead of leaving a blank tile.
      // Resolved onto the origin this device can actually reach, exactly as
      // every other AVFoundation entry point does. Skipping it left every
      // thumbnail-less video tile stuck on the placeholder whenever the API
      // returned a URL on its internal origin.
      MaxVideoPoster(
        mediaID: item.id,
        url: mediaURL.resolved(against: MaxConfiguration.fromBundle().baseURL),
        placeholder: { posterPlaceholder }
      )
        .accessibilityIdentifier("ui_video_poster_\(item.id.maxAccessibilityToken)")
    } else {
      posterPlaceholder
    }
  }

  private var posterPlaceholder: some View {
    Rectangle()
      .fill(MaxColor.surfaceStrong)
      .overlay {
        Image(systemName: item.kind == "video" ? "film.stack.fill" : "photo.fill")
          .font(.system(size: compact ? 20 : 34, weight: .medium))
          .foregroundStyle(MaxColor.textSecondary)
      }
  }
}

/// Produces a correctly oriented, bounded first-frame poster for any playable
/// video URL while server-side processing catches up. It is intentionally used
/// only when the API did not provide `thumbnailUrl`.
private struct MaxVideoPoster<Placeholder: View>: View {
  let mediaID: String
  let url: URL
  let placeholder: () -> Placeholder

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        placeholder()
      }
    }
    // Keyed on the media id, never on `url`: the backend re-signs the streaming
    // URL on every list response, so a URL-keyed task restarted generation on
    // each refresh and a URL-keyed cache could never hit.
    .task(id: mediaID) {
      if let cached = await MaxVideoPosterCache.shared.cachedPoster(mediaID: mediaID) {
        image = cached.image
        return
      }
      let asset = AVURLAsset(url: url)
      guard (try? await asset.load(.isPlayable)) == true else { return }
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 960, height: 960)
      // Accept the nearest sync frame. An exact seek forces the decoder to walk
      // from the previous keyframe, which over the network is many more range
      // requests for a frame nobody can tell apart at thumbnail size.
      generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
      generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
      // `image(at:)` is the async replacement for `copyCGImage(at:actualTime:)`.
      // The synchronous form blocked a cooperative-pool thread for a whole
      // network round trip, once per visible video tile, which starved the
      // image loader actor sharing that pool and stalled the neighbouring
      // photo thumbnails as well.
      guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image,
            !Task.isCancelled else { return }
      let poster = MaxVideoPosterImage(image: UIImage(cgImage: frame))
      await MaxVideoPosterCache.shared.store(poster, mediaID: mediaID)
      image = poster.image
    }
  }
}

struct MaxMediaTile: View {
  let item: MaxMediaItem

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      MaxMediaPoster(item: item, compact: true, showsMetadata: false)
      Text(verbatim: item.displayTitle)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
      if let source = item.workspace?.name ?? item.uploader.name, !source.isEmpty {
        Text(verbatim: source)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.title))
  }
}

struct MaxMediaRow: View {
  let item: MaxMediaItem

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      MaxMediaPoster(item: item, compact: true, showsMetadata: false)
        .frame(width: 72, height: 72)

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: item.displayTitle)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)

        if let source = item.workspace?.name ?? item.uploader.name, !source.isEmpty {
          Text(verbatim: source)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
            .lineLimit(1)
        }

        HStack(spacing: MaxSpace.xs) {
          Label(
            item.kind == "video" ? "media.kind.video" : "media.kind.media",
            systemImage: item.kind == "video" ? "film.stack" : "photo"
          )
          if let duration = item.duration {
            Text(verbatim: duration.minuteString)
          }
          if item.hasProgress {
            Image(systemName: "clock.arrow.circlepath")
              .accessibilityLabel(Text("home.section.continue"))
          }
        }
        .font(.caption)
        .foregroundStyle(MaxColor.textSecondary)
      }

      Spacer(minLength: 0)
      Image(systemName: "chevron.forward")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
  }
}

struct MaxAvatar: View {
  let name: String
  let imageURL: URL?
  let size: CGFloat

  init(name: String, imageURL: URL? = nil, size: CGFloat = 44) {
    self.name = name
    self.imageURL = imageURL
    self.size = size
  }

  var body: some View {
    ZStack {
      Circle().fill(MaxColor.surfaceStrong)
      if let imageURL {
        MaxAsyncImage(url: imageURL) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            initials
          }
        }
      } else {
        initials
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityLabel(Text(verbatim: name))
  }

  private var initials: some View {
    Text(verbatim: String(name.prefix(1)).uppercased())
      .font(.system(size: size * 0.40, weight: .semibold))
      .foregroundStyle(MaxColor.textSecondary)
  }
}

struct MaxThreadRow: View {
  let thread: ChatThread

  var body: some View {
    MaxS6ChannelListItem(thread: thread)
  }
}

struct MaxStatTile: View {
  let title: LocalizedStringKey
  let value: String
  let symbol: String

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(MaxColor.accent)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: value)
          .font(.headline)
        Text(title)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, MaxSpace.xs)
  }
}

struct MaxEmptyState: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  let symbol: String

  var body: some View {
    VStack(spacing: MaxSpace.sm) {
      Image(systemName: symbol)
        .font(.system(size: 32, weight: .semibold))
        .foregroundStyle(MaxColor.accent)
        .accessibilityHidden(true)
      Text(title)
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(MaxColor.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(MaxSpace.xl)
    // The card hugs its text instead of stretching edge to edge, so it reads as a
    // deliberate placeholder rather than a full-width banner on a wide screen.
    .frame(maxWidth: 420)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    // Centred in whatever space the caller gives it. Without the height the view
    // hugged its content and settled at the very top, leaving a tall band of dead
    // space beneath it — most visibly in a conversation, where the placeholder sat
    // against the navigation bar with the keyboard crowding it from below.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(MaxSpace.lg)
    .accessibilityElement(children: .combine)
  }
}

/// Kept for legacy feature views. New root flows use `.searchable`.
struct MaxSearchField: View {
  let title: LocalizedStringKey
  @Binding var text: String

  var body: some View {
    TextField(title, text: $text)
      .textFieldStyle(.roundedBorder)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(.search)
  }
}

struct MaxIconButton: View {
  let systemName: String
  let size: MaxControlSize
  let accessibilityLabel: LocalizedStringKey
  let hint: LocalizedStringKey?
  let isSelected: Bool
  let isProminent: Bool
  let action: () -> Void

  init(
    systemName: String,
    size: MaxControlSize = .compact,
    accessibilityLabel: LocalizedStringKey,
    hint: LocalizedStringKey? = nil,
    isSelected: Bool = false,
    isProminent: Bool = false,
    action: @escaping () -> Void
  ) {
    self.systemName = systemName
    self.size = size
    self.accessibilityLabel = accessibilityLabel
    self.hint = hint
    self.isSelected = isSelected
    self.isProminent = isProminent
    self.action = action
  }

  var body: some View {
    Group {
      if isProminent {
        button.buttonStyle(.glassProminent)
      } else {
        button.buttonStyle(.glass)
      }
    }
    .tint(isSelected || isProminent ? MaxColor.accent : nil)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(hint ?? "")
  }

  private var button: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: size.iconSize, weight: .semibold))
        .frame(width: size.visualSize, height: size.visualSize)
        .contentShape(Circle())
    }
  }
}
