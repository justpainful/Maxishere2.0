import PhotosUI
import SwiftUI
import UIKit

/// Mirrors the real profile header composition — same cover ratio, same avatar
/// plate below the cover, same identity typography — so what the user approves
/// here is what the profile actually renders.
struct ProfileEditPreview: View {
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette

  let displayName: String
  let username: String
  let bio: String
  let avatarURL: URL?
  let coverURL: URL?
  let avatarImage: UIImage?
  let coverImage: UIImage?

  @ScaledMetric(relativeTo: .title) private var scaledAvatarSize: CGFloat = 96

  private var avatarSize: CGFloat {
    min(max(scaledAvatarSize, 92), 116)
  }

  private var resolvedName: String {
    displayName.isEmpty ? String(localized: "profile.default_name") : displayName
  }

  var body: some View {
    let isCouncil = appTheme == .council
    let plate: AnyShapeStyle = isCouncil
      ? AnyShapeStyle(CouncilColor.obsidianSurface)
      : AnyShapeStyle(MaxColor.surface)

    return VStack(alignment: .leading, spacing: 0) {
      Color.clear
        .aspectRatio(ProfileCoverMetrics.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay {
          ProfileHeaderArtwork(url: coverURL, previewImage: coverImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: MaxRadius.large,
            topTrailingRadius: MaxRadius.large,
            style: .continuous
          )
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MaxSpace.md) {
        HStack(alignment: .center, spacing: MaxSpace.md) {
          avatar(isCouncil: isCouncil, plate: plate)
          identityText(isCouncil: isCouncil)
          Spacer(minLength: 0)
        }

        if !bio.isEmpty {
          HStack(alignment: .top, spacing: MaxSpace.sm) {
            Image(systemName: "quote.opening")
              .font(.caption.weight(.bold))
              .foregroundStyle(palette.accent)
              .padding(.top, 2)

            Text(verbatim: bio)
              .font(.body)
              .foregroundStyle(MaxColor.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MaxSpace.md)
    }
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous)
    )
    .overlay(alignment: .topTrailing) {
      Text("profile.edit.preview")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, MaxSpace.xs)
        .background(MaxColor.mediaOverlay, in: Capsule())
        .padding(MaxSpace.sm)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("profile.edit.preview"))
    .accessibilityValue(
      Text(verbatim: username.isEmpty ? resolvedName : "\(resolvedName), @\(username)")
    )
    .accessibilityIdentifier("ui_profile_edit_preview")
  }

  private func avatar(isCouncil: Bool, plate: AnyShapeStyle) -> some View {
    ProfileAvatarArtwork(
      name: resolvedName,
      url: avatarURL,
      previewImage: avatarImage,
      size: avatarSize,
      ringStyle: plate
    )
    .padding(3)
    .background(
      plate,
      in: RoundedRectangle(cornerRadius: avatarSize * 0.22 + 3, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: avatarSize * 0.22 + 3, style: .continuous)
        .strokeBorder(
          isCouncil
            ? AnyShapeStyle(CouncilColor.quietBorder)
            : AnyShapeStyle(MaxColor.lineStrong),
          lineWidth: 1
        )
    }
    .accessibilityHidden(true)
  }

  private func identityText(isCouncil: Bool) -> some View {
    VStack(alignment: .leading, spacing: MaxSpace.xxs) {
      Text(verbatim: resolvedName)
        .font(
          isCouncil
            ? Font.system(.title2, design: .serif, weight: .bold)
            : .system(.title2, design: .rounded, weight: .bold)
        )
        .foregroundStyle(MaxColor.textPrimary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      if !username.isEmpty {
        Text(verbatim: "@\(username)")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textSecondary)
          .lineLimit(2)
          .truncationMode(.middle)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
    .layoutPriority(1)
  }
}

struct ProfileAssetEditingSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let isDemoMode: Bool
  @Binding var avatarPickerItem: PhotosPickerItem?
  @Binding var coverPickerItem: PhotosPickerItem?
  @Binding var expandedDemoKind: ProfileImageKind?
  let chooseDemoArtwork: (DemoProfileArtwork) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text("profile.edit.images")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      if isDemoMode {
        demoButton(kind: .avatar)
        if expandedDemoKind == .avatar {
          DemoArtworkStrip(kind: .avatar, choose: chooseDemoArtwork)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        demoButton(kind: .cover)
        if expandedDemoKind == .cover {
          DemoArtworkStrip(kind: .cover, choose: chooseDemoArtwork)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      } else {
        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
          ProfileImageActionLabel(kind: .avatar)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_profile_edit_avatar")

        PhotosPicker(selection: $coverPickerItem, matching: .images) {
          ProfileImageActionLabel(kind: .cover)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_profile_edit_header")
      }
    }
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
  }

  private func demoButton(kind: ProfileImageKind) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : MaxMotion.quick) {
        expandedDemoKind = expandedDemoKind == kind ? nil : kind
      }
    } label: {
      ProfileImageActionLabel(kind: kind)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(
      kind == .avatar ? "ui_profile_edit_avatar" : "ui_profile_edit_header"
    )
  }
}

private struct ProfileImageActionLabel: View {
  @Environment(\.maxThemePalette) private var palette

  let kind: ProfileImageKind

  @ScaledMetric(relativeTo: .title3) private var plateSize: CGFloat = 40

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: kind == .avatar ? "person.crop.circle" : "photo.on.rectangle.angled")
        .font(.title3)
        .foregroundStyle(palette.accent)
        .frame(width: plateSize, height: plateSize)
        .background(
          MaxColor.surfaceSoft,
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(
          LocalizedStringKey(
            kind == .avatar ? "profile.edit.avatar" : "profile.edit.cover"
          )
        )
          .font(.body.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
        Text(
          LocalizedStringKey(
            kind == .avatar ? "profile.edit.avatar.hint" : "profile.edit.cover.hint"
          )
        )
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .multilineTextAlignment(.leading)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.forward")
        .font(.caption.weight(.semibold))
        .foregroundStyle(MaxColor.textTertiary)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 50)
    .contentShape(Rectangle())
  }
}

private struct DemoArtworkStrip: View {
  let kind: ProfileImageKind
  let choose: (DemoProfileArtwork) -> Void

  private var artwork: [DemoProfileArtwork] {
    DemoProfileArtwork.allCases.filter { $0.kind == kind }
  }

  /// Covers use the one authoritative cover ratio so the strip, the crop editor
  /// and the header never show three different shapes for the same asset.
  private var thumbnailSize: CGSize {
    kind == .avatar
      ? CGSize(width: 78, height: 78)
      : CGSize(width: 132, height: (132 / ProfileCoverMetrics.aspectRatio).rounded())
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MaxSpace.sm) {
        ForEach(Array(artwork.enumerated()), id: \.element.id) { index, item in
          Button {
            choose(item)
          } label: {
            VStack(spacing: MaxSpace.xs) {
              Image(uiImage: DemoArtworkCache.thumbnail(for: item))
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(kind == .avatar
                  ? AnyShape(Circle())
                  : AnyShape(
                    RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
                  ))
              Text(item.titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MaxColor.textSecondary)
                .lineLimit(1)
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_profile_demo_\(kind.rawValue)_\(index)")
        }
      }
      .padding(.vertical, MaxSpace.xs)
    }
    .accessibilityIdentifier("ui_profile_demo_\(kind.rawValue)_choices")
  }
}
