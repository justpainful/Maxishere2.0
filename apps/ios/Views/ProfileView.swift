import SwiftUI

struct ProfileView: View {
  private enum Destination: Identifiable {
    case edit(MaxUser)

    var id: String { "edit-profile" }
  }

  @Environment(MaxAppModel.self) private var model
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette

  @State private var destination: Destination?

  private var user: MaxUser? {
    model.profileStore.phase.value?.user ?? model.sessionStore.user
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ProfileHeroView(user: user, edit: presentEditor)

        PluginExtensionPointView(pointId: "profile:afterHeader")

        VStack(alignment: .leading, spacing: MaxSpace.xl) {
          ProfileDestinationsSection(openWhatsNew: { model.openWhatsNew() })
          profileContent
          ProfileAccountSettingsSection()
        }
        .padding(.horizontal, MaxSpace.md)
        .padding(.top, MaxSpace.lg)
      }
    }
    .navigationTitle("tab.profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          SettingsView()
        } label: {
          Image(systemName: "gearshape")
            .font(.body.weight(.semibold))
            .foregroundStyle(MaxColor.textPrimary)
        }
        .accessibilityIdentifier("ui_profile_nav_settings")
      }
    }
    .refreshable { await model.profileStore.load() }
    .task {
      guard model.profileStore.phase.value == nil,
            !model.profileStore.phase.isLoading else { return }
      await model.profileStore.load()
    }
    .sheet(item: $destination) { destination in
      switch destination {
      case .edit(let user): EditProfileView(user: user)
      }
    }
    .maxTabContent()
    .councilLight(.profile)
    .accessibilityIdentifier("ui_profile_screen")
  }

  @ViewBuilder
  private var profileContent: some View {
    if let profile = model.profileStore.phase.value {
      ProfileStatsSection(profile: profile)
      ProfileFavoritesSection(items: profile.favorites, open: model.openPlayer(for:))
      ProfileRatingsSection(ratings: profile.personal.personalRatings)
    } else if model.profileStore.phase.isLoading {
      ProfileLoadingPlaceholder()
    } else if model.profileStore.phase.errorMessage != nil {
      ProductErrorView(error: profileLoadError) {
        Task { await model.profileStore.load() }
      }
    }
  }

  private var profileLoadError: ProductError {
    let offline = !model.networkMonitor.isOnline
    return ProductError(
      area: .profile,
      code: offline ? .offline : .serverUnavailable,
      title: String(localized: offline
        ? "error.product.offline.title"
        : "error.product.server.title"),
      reason: String(localized: offline
        ? "error.product.offline.reason"
        : "profile.load_error.reason"),
      recoverySuggestion: String(localized: "error.product.retry")
    )
  }

  private func presentEditor() {
    guard let user else { return }
    destination = .edit(user)
  }
}

private struct ProfileHeroView: View {
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette

  let user: MaxUser?
  let edit: () -> Void

  @ScaledMetric(relativeTo: .title) private var scaledAvatarSize: CGFloat = 96

  private var displayName: String {
    user?.displayName ?? String(localized: "profile.default_name")
  }

  private var avatarSize: CGFloat {
    min(max(scaledAvatarSize, 92), 116)
  }

  var body: some View {
    let isCouncil = appTheme == .council
    return VStack(alignment: .leading, spacing: 0) {
      // Landscape narrows the band instead of flattening it: the cover keeps
      // the exact ratio the crop editor exported, so it is never re-cropped.
      Color.clear
        .aspectRatio(ProfileCoverMetrics.aspectRatio, contentMode: .fit)
        .frame(maxWidth: ProfileCoverMetrics.maxWidth)
        .overlay {
          ProfileHeaderArtwork(url: user?.coverUrl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
          LinearGradient(
            colors: [.clear, palette.scrim.opacity(0.35)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 48)
          .allowsHitTesting(false)
        }
        .clipped()
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: MaxSpace.md) {
        ViewThatFits(in: .horizontal) {
          identityRow(isCouncil: isCouncil)

          VStack(alignment: .leading, spacing: MaxSpace.md) {
            HStack(alignment: .top, spacing: MaxSpace.md) {
              avatar(isCouncil: isCouncil)
              Spacer(minLength: MaxSpace.xs)
              editButton
            }
            identityText(isCouncil: isCouncil)
          }
        }

        if let bio = user?.bio, !bio.isEmpty {
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
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.md)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ui_profile_header")
  }

  private func identityRow(isCouncil: Bool) -> some View {
    HStack(alignment: .center, spacing: MaxSpace.md) {
      avatar(isCouncil: isCouncil)
      identityText(isCouncil: isCouncil)
      Spacer(minLength: MaxSpace.xs)
      editButton
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func avatar(isCouncil: Bool) -> some View {
    let plate: AnyShapeStyle = isCouncil
      ? AnyShapeStyle(CouncilColor.obsidianSurface)
      : AnyShapeStyle(MaxColor.surface)
    // The ring takes the plate's own style so the two read as one band instead
    // of two near-identical near-blacks on Council.
    return ProfileAvatarArtwork(
      name: displayName,
      url: user?.avatarUrl,
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
  }

  private func identityText(isCouncil: Bool) -> some View {
    VStack(alignment: .leading, spacing: MaxSpace.xxs) {
      Text(verbatim: displayName)
        .font(
          isCouncil
            ? Font.system(.title2, design: .serif, weight: .bold)
            : .system(.title2, design: .rounded, weight: .bold)
        )
        .foregroundStyle(
          isCouncil
            ? AnyShapeStyle(CouncilColor.primaryText)
            : AnyShapeStyle(MaxColor.textPrimary)
        )
        .fixedSize(horizontal: false, vertical: true)

      if let username = user?.username, !username.isEmpty {
        Text(verbatim: "@\(username)")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(
            isCouncil
              ? AnyShapeStyle(CouncilColor.secondaryText)
              : AnyShapeStyle(MaxColor.textSecondary)
          )
          .lineLimit(2)
          .truncationMode(.middle)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
    .layoutPriority(1)
  }

  private var editButton: some View {
    Button(action: edit) {
      Image(systemName: "pencil")
        .font(.body.weight(.semibold))
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.glass)
    .tint(palette.accent)
    .disabled(user == nil)
    .accessibilityLabel(Text("profile.edit.action"))
    .accessibilityIdentifier("ui_profile_edit")
  }
}

private struct ProfileDestinationsSection: View {
  @Environment(\.maxThemePalette) private var palette

  let openWhatsNew: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      NavigationLink {
        SettingsView()
      } label: {
        ProfileCompactDestinationCard(
          title: "settings.title",
          subtitle: "settings.subtitle",
          symbol: "gearshape.fill",
          accent: palette.accent
        )
      }
      .accessibilityIdentifier("ui_profile_goto_settings_tile")

      Button(action: openWhatsNew) {
        ProfileCompactDestinationCard(
          title: "release.whats_new.title",
          subtitle: "release.whats_new.subtitle",
          symbol: "sparkles",
          accent: palette.warning
        )
      }
      .accessibilityIdentifier("ui_profile_whats_new_tile")
    }
    .buttonStyle(.plain)
  }
}

private struct ProfileCompactDestinationCard: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  let symbol: String
  let accent: Color

  @ScaledMetric(relativeTo: .headline) private var plateSize: CGFloat = 38

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      HStack {
        Image(systemName: symbol)
          .font(.headline.weight(.semibold))
          .foregroundStyle(accent)
          .frame(width: plateSize, height: plateSize)
          .background(
            accent.opacity(0.10),
            in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
          )
        Spacer()
        Image(systemName: "arrow.up.forward")
          .font(.caption.weight(.bold))
          .foregroundStyle(MaxColor.textTertiary)
      }

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(title)
          .font(.body.weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)

        Text(subtitle)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
  }
}

private struct ProfileStatsSection: View {
  let profile: MobileProfileResponse

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "profile.stats", subtitle: "profile.stats.subtitle")

      VStack(spacing: MaxSpace.sm) {
        ProfilePrimaryMetricCard(
          title: "profile.stat.watch_time",
          value: formattedWatchTime(profile.stats.totalWatchSeconds),
          symbol: "clock.fill"
        )

        HStack(spacing: MaxSpace.sm) {
          ProfileCompactMetricCard(
            title: "profile.stat.files",
            value: profile.storage.fileCount.formatted(),
            symbol: "doc.on.doc"
          )

          ProfileCompactMetricCard(
            title: "profile.stat.viewed",
            value: profile.stats.totalViewed.formatted(),
            symbol: "eye.fill"
          )
        }

        ProfileStorageMetricCard(
          value: profile.storage.usedBytes.byteString
        )
      }
    }
  }

  private func formattedWatchTime(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(seconds)) ?? "0"
  }
}

private struct ProfilePrimaryMetricCard: View {
  @Environment(\.maxThemePalette) private var palette
  let title: LocalizedStringKey
  let value: String
  let symbol: String

  @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 74

  var body: some View {
    HStack(alignment: .center, spacing: MaxSpace.md) {
      VStack(alignment: .leading, spacing: MaxSpace.xs) {
        Label(title, systemImage: symbol)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textSecondary)

        // Without a line limit the scale factor never engages and "12h 34m"
        // wraps to two lines instead of shrinking.
        Text(verbatim: value)
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
          .foregroundStyle(MaxColor.textPrimary)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }

      Spacer(minLength: MaxSpace.md)

      ZStack {
        Circle()
          .fill(palette.accent.opacity(0.12))
          .frame(width: badgeSize, height: badgeSize)

        Image(systemName: "waveform.path.ecg")
          .font(.title2.weight(.semibold))
          .foregroundStyle(palette.accent)
      }
      .accessibilityHidden(true)
    }
    .padding(MaxSpace.lg)
    .background(
      LinearGradient(
        colors: [palette.primaryContentSurface, palette.accent.opacity(0.07)],
        startPoint: .leading,
        endPoint: .trailing
      ),
      in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
  }
}

private struct ProfileCompactMetricCard: View {
  @Environment(\.maxThemePalette) private var palette

  let title: LocalizedStringKey
  let value: String
  let symbol: String

  @ScaledMetric(relativeTo: .headline) private var plateSize: CGFloat = 38

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Image(systemName: symbol)
        .font(.headline.weight(.semibold))
        .foregroundStyle(palette.accent)
        .frame(width: plateSize, height: plateSize)
        .background(
          palette.accent.opacity(0.10),
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: value)
          .font(.title2.weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)

        Text(title)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
  }
}

private struct ProfileStorageMetricCard: View {
  @Environment(\.maxThemePalette) private var palette

  let value: String

  @ScaledMetric(relativeTo: .headline) private var plateSize: CGFloat = 42

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: "internaldrive.fill")
        .font(.headline.weight(.semibold))
        .foregroundStyle(palette.accent)
        .frame(width: plateSize, height: plateSize)
        .background(
          palette.accent.opacity(0.10),
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text("profile.stat.storage")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)

        Text(verbatim: value)
          .font(.headline.weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)
          .monospacedDigit()
      }

      Spacer(minLength: 0)

      Image(systemName: "circle.dotted")
        .font(.title2)
        .foregroundStyle(MaxColor.textTertiary)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.md)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
  }
}

private struct ProfileFavoritesSection: View {
  let items: [MaxMediaItem]
  let open: (MaxMediaItem) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "profile.favorites", subtitle: "profile.favorites.subtitle")

      if items.isEmpty {
        MaxEmptyState(
          title: "profile.favorites.empty",
          subtitle: "profile.favorites.empty.subtitle",
          symbol: "heart"
        )
      } else {
        // A plain VStack, deliberately not a lazy one. This shelf sits inside
        // the profile's own lazy stack, and a lazy stack nested in another one
        // reports a provisional height for rows it has not measured yet — which
        // is what let these cards draw on top of one another as the profile
        // scrolled. Four rows are cheap to build eagerly.
        VStack(spacing: MaxSpace.sm) {
          ForEach(items.prefix(4)) { item in
            Button { open(item) } label: {
              ProfileFavoriteRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_profile_favorite_\(item.id)")
          }
        }
      }
    }
  }
}

/// One favourite, sized so every row in the shelf is identical.
///
/// The generic `MaxMediaRow` grows with its title, so a two-line filename made
/// one card taller than its neighbours and the shelf lost its rhythm. Here the
/// thumbnail is a fixed square and the text is capped at one line each, which
/// keeps the row height constant no matter what the file is called.
private struct ProfileFavoriteRow: View {
  let item: MaxMediaItem

  @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 56

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      MaxMediaPoster(item: item, compact: true, showsMetadata: false)
        .frame(width: thumbnailSize, height: thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))

      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: item.displayTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(verbatim: subtitle)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      Image(systemName: "chevron.forward")
        .font(.caption.weight(.bold))
        .foregroundStyle(MaxColor.textTertiary)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.displayTitle))
  }

  private var subtitle: String {
    let kind = String(
      localized: item.kind.lowercased() == "video" ? "media.kind.video" : "media.kind.media"
    )
    guard let duration = item.duration, duration > 0 else { return kind }
    return "\(kind) · \(duration.minuteString)"
  }
}

private struct ProfileRatingsSection: View {
  let ratings: [ProfileRating]

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "profile.ratings", subtitle: "profile.ratings.subtitle")

      if ratings.isEmpty {
        MaxEmptyState(
          title: "profile.ratings.empty",
          subtitle: "profile.ratings.empty.subtitle",
          symbol: "star"
        )
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: MaxSpace.sm) {
            ForEach(ratings.prefix(8)) { rating in
              ProfileRatingCard(rating: rating)
            }
          }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
        // Reset the tab-bar clearance inherited from `.maxTabContent()`; it
        // belongs to the outer vertical scroll view, not this carousel.
        .contentMargins(.bottom, 0, for: .scrollContent)
      }
    }
  }
}

private struct ProfileRatingCard: View {
  let rating: ProfileRating

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      HStack {
        Image(systemName: "star.fill")
          .foregroundStyle(MaxColor.warning)

        Spacer(minLength: MaxSpace.sm)

        if let score = rating.score {
          Text(verbatim: score.formatted(.number.precision(.fractionLength(0...1))))
            .font(.headline.monospacedDigit().weight(.bold))
            .foregroundStyle(MaxColor.textPrimary)
        }
      }

      Text(verbatim: title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MaxColor.textPrimary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(MaxSpace.md)
    .frame(width: 170, height: 126, alignment: .topLeading)
    // Clipped, not merely framed: a fixed frame does not stop an oversized title
    // from drawing past the card's background and over its neighbour.
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  /// The rated file's name without its extension. `ProfileRating` carries the
  /// stored filename, so the raw value reads `IMG_2201.MOV` on the card.
  private var title: String {
    guard let name = rating.name, !name.isEmpty else {
      return String(localized: "common.media")
    }
    return name.asMediaDisplayName
  }
}

private struct ProfileLoadingPlaceholder: View {
  var body: some View {
    // `.redacted(.placeholder)` is a no-op on plain shapes, so the slabs used
    // to sit dead still. The shared shimmer animates and already honours
    // Reduce Motion.
    VStack(spacing: MaxSpace.sm) {
      CouncilLoadingShimmer(height: 148, cornerRadius: 26)

      HStack(spacing: MaxSpace.sm) {
        CouncilLoadingShimmer(height: 132, cornerRadius: 24)
        CouncilLoadingShimmer(height: 132, cornerRadius: 24)
      }

      CouncilLoadingShimmer(height: 84, cornerRadius: 24)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("profile.loading"))
    .accessibilityAddTraits(.updatesFrequently)
  }
}

private struct ProfileAccountSettingsSection: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @State private var confirmsSignOut = false

  /// Mirrors `ProfileAccountRow`'s icon plate so the divider inset keeps
  /// matching the row text at every Dynamic Type size.
  @ScaledMetric(relativeTo: .body) private var plateSize: CGFloat = 36

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      MaxSectionHeader(title: "settings.title", subtitle: "settings.account")

      VStack(spacing: 0) {
        NavigationLink {
          SettingsView()
        } label: {
          ProfileAccountRow(
            title: "settings.title",
            symbol: "gearshape.fill",
            foregroundStyle: palette.accent,
            textStyle: palette.primaryText,
            showsChevron: true
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_profile_goto_settings")

        Divider()
          .padding(.leading, plateSize + MaxSpace.md)

        Button(role: .destructive) {
          confirmsSignOut = true
        } label: {
          ProfileAccountRow(
            title: "profile.signout",
            symbol: "rectangle.portrait.and.arrow.right",
            foregroundStyle: palette.destructive,
            textStyle: palette.destructive,
            showsChevron: false
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_profile_signout")
      }
      .padding(.horizontal, MaxSpace.md)
      .background(
        MaxColor.surface,
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
      )
    }
    .confirmationDialog(
      "profile.signout.confirm.title",
      isPresented: $confirmsSignOut,
      titleVisibility: .visible
    ) {
      Button("profile.signout", role: .destructive) {
        confirmsSignOut = false
        Task { await model.signOut() }
      }
      .accessibilityIdentifier("ui_profile_signout_confirm")

      Button("common.cancel", role: .cancel) {
        confirmsSignOut = false
      }
    } message: {
      Text("profile.signout.confirm.message")
    }
  }
}

private struct ProfileAccountRow: View {
  let title: LocalizedStringKey
  let symbol: String
  let foregroundStyle: Color
  let textStyle: Color
  let showsChevron: Bool

  @ScaledMetric(relativeTo: .body) private var plateSize: CGFloat = 36

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(foregroundStyle)
        .frame(width: plateSize, height: plateSize)
        .background(
          foregroundStyle.opacity(0.10),
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )

      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(textStyle)

      Spacer(minLength: 0)

      if showsChevron {
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.bold))
          .foregroundStyle(MaxColor.textTertiary)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, MaxSpace.sm)
    .contentShape(Rectangle())
  }
}
