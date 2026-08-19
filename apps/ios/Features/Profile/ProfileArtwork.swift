import SwiftUI
import UIKit

/// One authoritative shape for the profile cover. The crop editor, the edit
/// preview and the profile header all read these values, so whatever the user
/// frames in the cropper is exactly what the header renders.
enum ProfileCoverMetrics {
  static let aspectRatio: CGFloat = 16 / 7
  static let pixelWidth: CGFloat = 1_920
  static var pixelHeight: CGFloat { (pixelWidth / aspectRatio).rounded() }
  /// Landscape caps the header by narrowing the band, never by squashing it,
  /// so the saved crop is never cropped a second time.
  static let maxHeight: CGFloat = 260
  static var maxWidth: CGFloat { maxHeight * aspectRatio }
}

struct ProfileHeaderArtwork: View {
  let url: URL?
  let previewImage: UIImage?

  init(url: URL?, previewImage: UIImage? = nil) {
    self.url = url
    self.previewImage = previewImage
  }

  var body: some View {
    Group {
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFill()
      } else if let localImage = ProfileArtworkLoader.localImage(from: url) {
        Image(uiImage: localImage)
          .resizable()
          .scaledToFill()
      } else if let url {
        MaxAsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            ProfileAtmosphericFallback()
          }
        }
      } else {
        ProfileAtmosphericFallback()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }
}

struct ProfileAvatarArtwork: View {
  let name: String
  let url: URL?
  let previewImage: UIImage?
  let size: CGFloat
  /// Callers that seat the avatar on a plate pass the plate's own style so the
  /// ring and the plate read as a single band instead of two near-identical tones.
  let ringStyle: AnyShapeStyle

  init(
    name: String,
    url: URL?,
    previewImage: UIImage? = nil,
    size: CGFloat = 112,
    ringStyle: AnyShapeStyle = AnyShapeStyle(MaxColor.surface)
  ) {
    self.name = name
    self.url = url
    self.previewImage = previewImage
    self.size = size
    self.ringStyle = ringStyle
  }

  var body: some View {
    ZStack {
      Rectangle().fill(MaxColor.surfaceStrong)
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFill()
      } else if let localImage = ProfileArtworkLoader.localImage(from: url) {
        Image(uiImage: localImage)
          .resizable()
          .scaledToFill()
      } else if let url {
        MaxAsyncImage(url: url) { phase in
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
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .strokeBorder(ringStyle, lineWidth: max(2, size * 0.024))
    }
    .accessibilityLabel(Text(verbatim: name))
  }

  private var initials: some View {
    Text(verbatim: ProfileArtworkLoader.initials(for: name))
      .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
      .foregroundStyle(MaxColor.textSecondary)
  }
}

private struct ProfileAtmosphericFallback: View {
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    MeshGradient(
      width: 3,
      height: 2,
      points: [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 1), .init(0.58, 0.88), .init(1, 1),
      ],
      colors: palette.isDark
        ? [
          MaxColor.deepNavy,
          MaxColor.violet,
          MaxColor.sky.opacity(0.56),
          MaxColor.midnight,
          MaxColor.coral.opacity(0.70),
          MaxColor.deepNavy,
        ]
        : [
          MaxColor.sky,
          MaxColor.periwinkle,
          MaxColor.lavender,
          MaxColor.periwinkle,
          MaxColor.coral,
          MaxColor.amber,
        ],
      background: palette.atmosphericBackground,
      smoothsColors: true
    )
  }
}

enum DemoProfileArtwork: String, CaseIterable, Identifiable {
  case avatarAurora
  case avatarMidnight
  case coverSky
  case coverViolet

  var id: String { rawValue }

  var kind: ProfileImageKind {
    switch self {
    case .avatarAurora, .avatarMidnight: .avatar
    case .coverSky, .coverViolet: .cover
    }
  }

  var titleKey: LocalizedStringKey {
    switch self {
    case .avatarAurora: "profile.demo_asset.avatar_aurora"
    case .avatarMidnight: "profile.demo_asset.avatar_midnight"
    case .coverSky: "profile.demo_asset.cover_sky"
    case .coverViolet: "profile.demo_asset.cover_violet"
    }
  }

  /// Full-resolution source handed to the crop editor.
  @MainActor
  func makeImage() -> UIImage {
    render(size: kind == .avatar
      ? CGSize(width: 1_024, height: 1_024)
      : CGSize(width: ProfileCoverMetrics.pixelWidth, height: ProfileCoverMetrics.pixelHeight))
  }

  /// Small bitmap for the picker strip. Rasterising the full-size artwork on
  /// every body evaluation stalls the disclosure animation.
  @MainActor
  func makeThumbnail() -> UIImage {
    render(size: kind == .avatar
      ? CGSize(width: 234, height: 234)
      : CGSize(width: 396, height: (396 / ProfileCoverMetrics.aspectRatio).rounded()))
  }

  @MainActor
  private func render(size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let cgContext = context.cgContext
      let colors = gradientColors.map { $0.cgColor } as CFArray
      let locations: [CGFloat] = [0, 0.52, 1]
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: locations
      ) {
        cgContext.drawLinearGradient(
          gradient,
          start: .zero,
          end: CGPoint(x: size.width, y: size.height),
          options: []
        )
      }

      cgContext.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
      cgContext.fillEllipse(
        in: CGRect(
          x: size.width * 0.54,
          y: -size.height * 0.18,
          width: size.width * 0.72,
          height: size.width * 0.72
        )
      )
      cgContext.setFillColor(UIColor.black.withAlphaComponent(0.14).cgColor)
      cgContext.fillEllipse(
        in: CGRect(
          x: -size.width * 0.18,
          y: size.height * 0.58,
          width: size.width * 0.70,
          height: size.width * 0.70
        )
      )
    }
  }

  private var gradientColors: [UIColor] {
    switch self {
    case .avatarAurora:
      [
        UIColor(red: 0.22, green: 0.70, blue: 0.94, alpha: 1),
        UIColor(red: 0.55, green: 0.43, blue: 0.92, alpha: 1),
        UIColor(red: 0.94, green: 0.48, blue: 0.45, alpha: 1),
      ]
    case .avatarMidnight:
      [
        UIColor(red: 0.04, green: 0.08, blue: 0.17, alpha: 1),
        UIColor(red: 0.16, green: 0.25, blue: 0.52, alpha: 1),
        UIColor(red: 0.37, green: 0.72, blue: 0.88, alpha: 1),
      ]
    case .coverSky:
      [
        UIColor(red: 0.28, green: 0.72, blue: 0.94, alpha: 1),
        UIColor(red: 0.72, green: 0.68, blue: 0.96, alpha: 1),
        UIColor(red: 0.98, green: 0.64, blue: 0.47, alpha: 1),
      ]
    case .coverViolet:
      [
        UIColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1),
        UIColor(red: 0.28, green: 0.25, blue: 0.62, alpha: 1),
        UIColor(red: 0.65, green: 0.69, blue: 0.95, alpha: 1),
      ]
    }
  }
}

/// Memoises the demo picker thumbnails so the strip never rasterises inside a
/// view body more than once per asset.
@MainActor
enum DemoArtworkCache {
  private static var thumbnails: [String: UIImage] = [:]

  static func thumbnail(for artwork: DemoProfileArtwork) -> UIImage {
    if let cached = thumbnails[artwork.rawValue] { return cached }
    let image = artwork.makeThumbnail()
    thumbnails[artwork.rawValue] = image
    return image
  }
}

private enum ProfileArtworkLoader {
  static func localImage(from url: URL?) -> UIImage? {
    guard let url, url.isFileURL else { return nil }
    return UIImage(contentsOfFile: url.path)
  }

  static func initials(for name: String) -> String {
    let words = name
      .split(whereSeparator: \.isWhitespace)
      .prefix(2)
      .compactMap(\.first)
    let value = String(words)
    return value.isEmpty ? "M" : value.uppercased()
  }
}
