import SwiftUI

struct SettingsView: View {
  private enum Confirmation {
    case signOut
    case demoReset
    case clearCache
  }

  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  @State private var confirmation: Confirmation?
  @State private var isResettingDemo = false
  @State private var isSwitchingAccount = false

  private var showsDeveloperSettings: Bool {
    #if DEBUG
    return true
    #else
    return model.isDemoMode || model.isUITestMode
    #endif
  }

  var body: some View {
    Form {
      identitySection
      appearanceSection
      playbackSection
      downloadsSection
      cachingSection
      privacySection
      accountSection
      if showsDeveloperSettings { developerSection }
      aboutSection
    }
    .scrollContentBackground(.hidden)
    .maxTabContent()
    .navigationTitle("settings.title")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      confirmationTitle,
      isPresented: confirmationBinding,
      titleVisibility: .visible
    ) {
      confirmationActions
    } message: {
      Text(confirmationMessage)
    }
    .accessibilityIdentifier("ui_settings_screen")
  }

  @ViewBuilder
  private var identitySection: some View {
    if let user = model.profileStore.phase.value?.user ?? model.sessionStore.user {
      Section {
        HStack(spacing: MaxSpace.md) {
          ProfileAvatarArtwork(name: user.displayName, url: user.avatarUrl, size: 58)
          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text(verbatim: user.displayName)
              .font(.headline)
              .foregroundStyle(MaxColor.textPrimary)
            if let username = user.username, !username.isEmpty {
              Text(verbatim: "@\(username)")
                .font(.subheadline)
                .foregroundStyle(MaxColor.textSecondary)
                .environment(\.layoutDirection, .leftToRight)
            }
            Text("settings.subtitle")
              .font(.caption)
              .foregroundStyle(MaxColor.textTertiary)
          }
          Spacer(minLength: MaxSpace.sm)
          Image(systemName: "checkmark.shield.fill")
            .font(.title3)
            .foregroundStyle(MaxColor.mint)
            .accessibilityHidden(true)
        }
        .padding(.vertical, MaxSpace.xs)
        .accessibilityElement(children: .combine)
      } header: {
        Text("settings.signed_in_as")
      }
    }
  }

  private var appearanceSection: some View {
    Section {
      AppThemePicker(selection: themeBinding)

      NavigationLink {
        PluginStoreView()
      } label: {
        Label(
          title: { Text("settings.plugins.store") },
          icon: { Image(systemName: "puzzlepiece.extension") }
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(palette.accent)
      }
      .accessibilityIdentifier("ui_settings_plugins_store")

      Picker("settings.language", selection: languageBinding) {
        ForEach(AppLanguage.allCases) { language in
          Text(language.titleKey)
            .tag(language)
            .accessibilityIdentifier("ui_language_\(language.rawValue)")
        }
      }
      .accessibilityIdentifier("ui_settings_language")

      Toggle("settings.reduce_motion", isOn: reduceMotionBinding)
        .accessibilityIdentifier("ui_settings_reduce_motion")
    } header: {
      Text("settings.appearance")
    }
  }

  private static let playbackSpeeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

  private var playbackSection: some View {
    Section {
      Picker("settings.playback_speed", selection: playbackSpeedBinding) {
        ForEach(Self.playbackSpeeds, id: \.self) { speed in
          Text(verbatim: "\(speed.formatted())×").tag(speed)
        }
      }
      .accessibilityIdentifier("ui_settings_playback_speed")

      Picker("Hide Controls After", selection: controlsHideBinding) {
        ForEach([2, 3, 5], id: \.self) { seconds in
          Text(verbatim: "\(seconds)s").tag(seconds)
        }
      }
      .accessibilityIdentifier("ui_settings_controls_hide")

      Toggle("Flow Mode", isOn: flowModeBinding)
        .accessibilityIdentifier("ui_settings_flow_mode")
    } header: {
      Text("settings.playback")
    } footer: {
      Text("Flow Mode plays the next item automatically when a video finishes.")
    }
  }

  private var downloadsSection: some View {
    Section {
      Picker("settings.download_network", selection: downloadNetworkBinding) {
        ForEach(DownloadNetworkPreference.allCases) { preference in
          Text(preference.titleKey).tag(preference)
        }
      }
      .accessibilityIdentifier("ui_settings_download_network")

      NavigationLink {
        OfflineStorageView()
      } label: {
        Label("storage.offline.title", systemImage: "internaldrive")
      }

      Button("transfers.title", systemImage: "arrow.up.arrow.down") {
        model.openTransfers()
      }
    } header: {
      Text("settings.downloads")
    }
  }

  private var privacySection: some View {
    Section {
      NavigationLink {
        PrivacyInformationView()
      } label: {
        Label("privacy.title", systemImage: "hand.raised")
      }

      Toggle(isOn: appLockBinding) {
        Label("Lock the app with Face ID", systemImage: "faceid")
      }
      .accessibilityIdentifier("ui_settings_app_lock")

      NavigationLink {
        DoubleLockSettingsView()
      } label: {
        Label {
          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text("double_lock.title")
            Text(
              LocalizedStringKey(
                model.doubleLockStore.isEnabled
                  ? "double_lock.enabled"
                  : "double_lock.disabled"
              )
            )
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
          }
        } icon: {
          Image(systemName: model.doubleLockStore.isEnabled ? "lock.shield.fill" : "lock.shield")
        }
      }
    } header: {
      Text("settings.privacy")
    }
  }

  private var accountSection: some View {
    Section {
      if !model.isDemoMode {
        ForEach(model.accountStore.accounts) { account in
          accountRow(account)
        }

        Button("Add Account", systemImage: "person.badge.plus") {
          Task { await model.beginAddAccount() }
        }
        .disabled(isSwitchingAccount)
        .accessibilityIdentifier("ui_settings_add_account")
      }

      Button(
        "profile.signout",
        systemImage: "rectangle.portrait.and.arrow.right",
        role: .destructive
      ) {
        confirmation = .signOut
      }
      .accessibilityIdentifier("ui_profile_signout")

      if model.isDemoMode {
        Button("settings.demo_reset", systemImage: "arrow.counterclockwise") {
          confirmation = .demoReset
        }
        .disabled(isResettingDemo)
        .accessibilityIdentifier("ui_demo_reset")
      }
    } header: {
      Text("settings.account")
    } footer: {
      if !model.isDemoMode {
        Text("Tap a saved account to switch to it. Signing out removes the current account from this device.")
      }
    }
  }

  /// One saved account: tap switches to it, the check marks the active one.
  private func accountRow(_ account: StoredAccount) -> some View {
    let isCurrent = account.id == model.sessionStore.user?.id
    return Button {
      guard !isCurrent else { return }
      isSwitchingAccount = true
      Task {
        await model.switchAccount(to: account)
        isSwitchingAccount = false
      }
    } label: {
      HStack(spacing: MaxSpace.sm) {
        ProfileAvatarArtwork(name: account.displayName, url: nil, size: 36)
        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: account.displayName)
            .font(.body.weight(isCurrent ? .semibold : .regular))
            .foregroundStyle(MaxColor.textPrimary)
          if let username = account.username, !username.isEmpty {
            Text(verbatim: "@\(username)")
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .environment(\.layoutDirection, .leftToRight)
          }
        }
        Spacer(minLength: 0)
        if isCurrent {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(palette.accent)
        } else if isSwitchingAccount {
          ProgressView()
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isSwitchingAccount)
    .accessibilityIdentifier("ui_settings_account_\(account.id)")
  }

  private var developerSection: some View {
    Section {
      NavigationLink {
        ServerSettingsView(isPresentedAsSheet: false)
      } label: {
        Label("server.settings", systemImage: "network")
      }
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label("diagnostics.title", systemImage: "stethoscope")
      }
    } header: {
      Text("settings.developer")
    }
  }

  private var aboutSection: some View {
    Section {
      Button("release.whats_new.title", systemImage: "sparkles") {
        model.openWhatsNew()
      }
      LabeledContent("settings.version") {
        Text(verbatim: appVersion)
          .environment(\.layoutDirection, .leftToRight)
      }
    } header: {
      Text("settings.about")
    }
  }

  @ViewBuilder
  private var confirmationActions: some View {
    switch confirmation {
    case .signOut:
      Button("profile.signout", role: .destructive) {
        confirmation = nil
        Task { await model.signOut() }
      }
      .accessibilityIdentifier("ui_profile_signout_confirm")
    case .demoReset:
      Button("settings.demo_reset", role: .destructive) {
        confirmation = nil
        isResettingDemo = true
        Task {
          await model.resetDemo()
          isResettingDemo = false
        }
      }
      .accessibilityIdentifier("ui_demo_reset_confirmation")
    case .clearCache:
      Button("settings.caching.clear_cache", role: .destructive) {
        confirmation = nil
        clearAllCaches()
      }
      .accessibilityIdentifier("ui_settings_clear_cache_confirm")
    case nil:
      EmptyView()
    }
    Button("common.cancel", role: .cancel) { confirmation = nil }
  }

  private var confirmationBinding: Binding<Bool> {
    Binding(
      get: { confirmation != nil },
      set: { if !$0 { confirmation = nil } }
    )
  }

  private var confirmationTitle: LocalizedStringKey {
    switch confirmation {
    case .demoReset: "settings.demo_reset.confirm.title"
    case .clearCache: "settings.caching.clear_cache.confirm.title"
    case .signOut, nil: "profile.signout.confirm.title"
    }
  }

  private var confirmationMessage: LocalizedStringKey {
    switch confirmation {
    case .demoReset: "settings.demo_reset.confirm.message"
    case .clearCache: "settings.caching.clear_cache.confirm.message"
    case .signOut, nil: "profile.signout.confirm.message"
    }
  }

  private var themeBinding: Binding<AppTheme> {
    Binding(
      get: { model.preferencesStore.theme },
      set: { model.preferencesStore.theme = $0 }
    )
  }

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { model.preferencesStore.language },
      set: { model.preferencesStore.language = $0 }
    )
  }

  private var reduceMotionBinding: Binding<Bool> {
    Binding(
      get: { model.preferencesStore.reduceBackgroundMotion },
      set: { model.preferencesStore.reduceBackgroundMotion = $0 }
    )
  }

  private var appLockBinding: Binding<Bool> {
    Binding(
      get: { model.preferencesStore.appLockEnabled },
      set: { enabled in
        model.preferencesStore.appLockEnabled = enabled
        // The person flipping the switch is demonstrably present; arming the
        // gate must not slam it shut on them mid-session.
        if enabled { model.appLockStore.grantForSetup() }
      }
    )
  }

  private var playbackSpeedBinding: Binding<Double> {
    Binding(
      get: { model.preferencesStore.playbackSpeed },
      set: { model.preferencesStore.playbackSpeed = $0 }
    )
  }

  private var controlsHideBinding: Binding<Int> {
    Binding(
      get: { model.preferencesStore.controlsHideSeconds },
      set: { model.preferencesStore.controlsHideSeconds = $0 }
    )
  }

  private var flowModeBinding: Binding<Bool> {
    Binding(
      get: { model.preferencesStore.flowModeAutoAdvance },
      set: { model.preferencesStore.flowModeAutoAdvance = $0 }
    )
  }

  private var downloadNetworkBinding: Binding<DownloadNetworkPreference> {
    Binding(
      get: { model.preferencesStore.downloadNetworkPreference },
      set: { model.preferencesStore.downloadNetworkPreference = $0 }
    )
  }

  private var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "1.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    return "\(version) (\(build))"
  }

  private var cachingSection: some View {
    Section {
      Toggle("settings.caching.enable_thumbnails", isOn: enableThumbnailCacheBinding)
      
      if model.preferencesStore.enableThumbnailCache {
        Picker("settings.caching.thumbnail_limit", selection: thumbnailCacheLimitMBBinding) {
          Text(verbatim: "50 MB").tag(50)
          Text(verbatim: "100 MB").tag(100)
          Text(verbatim: "250 MB").tag(250)
          Text(verbatim: "500 MB").tag(500)
          Text(verbatim: "1 GB").tag(1000)
        }
      }
      
      Toggle("settings.caching.enable_video_precache", isOn: enableVideoPreCacheBinding)
      
      if model.preferencesStore.enableVideoPreCache {
        Picker("settings.caching.video_chunk_size", selection: videoPreCacheSizeMBBinding) {
          Text(verbatim: "1 MB").tag(1)
          Text(verbatim: "2 MB").tag(2)
          Text(verbatim: "5 MB").tag(5)
          Text(verbatim: "10 MB").tag(10)
        }
        
        Stepper(value: videoPrefetchAdjacentCountBinding, in: 1...5) {
          LabeledContent {
            Text(model.preferencesStore.videoPrefetchAdjacentCount.formatted())
          } label: {
            Text("settings.caching.prefetch_adjacent_count")
          }
        }
      }
      
      Button("settings.caching.clear_cache", role: .destructive) {
        confirmation = .clearCache
      }
      .accessibilityIdentifier("ui_settings_clear_cache")
    } header: {
      Text("settings.caching.title")
    }
  }

  private var enableThumbnailCacheBinding: Binding<Bool> {
    Binding(
      get: { model.preferencesStore.enableThumbnailCache },
      set: { model.preferencesStore.enableThumbnailCache = $0 }
    )
  }

  private var thumbnailCacheLimitMBBinding: Binding<Int> {
    Binding(
      get: { model.preferencesStore.thumbnailCacheLimitMB },
      set: { model.preferencesStore.thumbnailCacheLimitMB = $0 }
    )
  }

  private var enableVideoPreCacheBinding: Binding<Bool> {
    Binding(
      get: { model.preferencesStore.enableVideoPreCache },
      set: { model.preferencesStore.enableVideoPreCache = $0 }
    )
  }

  private var videoPreCacheSizeMBBinding: Binding<Int> {
    Binding(
      get: { model.preferencesStore.videoPreCacheSizeMB },
      set: { model.preferencesStore.videoPreCacheSizeMB = $0 }
    )
  }

  private var videoPrefetchAdjacentCountBinding: Binding<Int> {
    Binding(
      get: { model.preferencesStore.videoPrefetchAdjacentCount },
      set: { model.preferencesStore.videoPrefetchAdjacentCount = $0 }
    )
  }

  private func clearAllCaches() {
    // Recursive directory deletion can take seconds for a cache at the
    // configured limit, so it must never run on the main actor.
    Task.detached(priority: .utility) {
      let caches = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      for name in ["MaxVideoPosters", "MaxImageCache"] {
        let directory = caches.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
      }
      // Clear memory caches and any remaining on-disk image entries.
      await MaxImageLoader.shared.removeAll()
      await MaxVideoPosterCache.shared.purge()
    }
  }
}

private struct AppThemePicker: View {
  @Binding var selection: AppTheme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      Text("settings.theme.core_group")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(palette.primaryText)
        .padding(.top, MaxSpace.xs)

      ForEach(AppTheme.allCases) { theme in
        let isSelected = (selection == theme) && (PluginStore.shared.activeVisualPluginId == nil)
        Button {
          PluginStore.shared.deactivateVisualPlugin()
          selection = theme
        } label: {
          HStack(spacing: MaxSpace.md) {
            ThemeSwatch(theme: theme, systemColorScheme: colorScheme)

            VStack(alignment: .leading, spacing: MaxSpace.xxs) {
              Text(theme.titleKey)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primaryText)
              Text(theme.descriptionKey)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.leading)
            }

            Spacer(minLength: MaxSpace.xs)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
          }
          .padding(MaxSpace.sm)
          .contentShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
          isSelected ? palette.selectedControl : palette.primaryContentSurface,
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
            .stroke(isSelected ? palette.accent : palette.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ui_theme_\(theme.rawValue)")
      }

      let installedVisualPlugins = PluginStore.shared.availablePlugins.filter {
        $0.manifest.capabilities.contains(.theme) && PluginStore.shared.installedPluginIds.contains($0.manifest.id)
      }

      if !installedVisualPlugins.isEmpty {
        Text("settings.theme.plugin_group")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(palette.primaryText)
          .padding(.top, MaxSpace.sm)

        ForEach(installedVisualPlugins, id: \.manifest.id) { plugin in
          let isSelected = PluginStore.shared.activeVisualPluginId == plugin.manifest.id
          Button {
            if isSelected {
              PluginStore.shared.deactivateVisualPlugin()
            } else {
              PluginTakeoverCoordinator.shared.startTakeover(targetPluginId: plugin.manifest.id)
            }
          } label: {
            HStack(spacing: MaxSpace.md) {
              pluginSwatch(for: plugin)
                .frame(width: 48, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

              VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                Text(plugin.manifest.name)
                  .font(.body.weight(.semibold))
                  .foregroundStyle(palette.primaryText)
                Text(plugin.manifest.description)
                  .font(.caption)
                  .foregroundStyle(palette.secondaryText)
                  .multilineTextAlignment(.leading)
              }

              Spacer(minLength: MaxSpace.xs)
              Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
            }
            .padding(MaxSpace.sm)
            .contentShape(RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous))
          }
          .buttonStyle(.plain)
          .background(
            isSelected ? palette.selectedControl : palette.primaryContentSurface,
            in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
              .stroke(isSelected ? palette.accent : palette.separator, lineWidth: 1)
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(isSelected ? .isSelected : [])
          .accessibilityIdentifier("ui_plugin_theme_\(plugin.manifest.id)")
        }
      }
    }
  }

  @ViewBuilder
  private func pluginSwatch(for plugin: any MaxPlugin) -> some View {
    if let visual = plugin as? any MaxVisualPlugin {
      visual.themeSwatchView()
    } else {
      palette.elevatedContentSurface
    }
  }
}

private struct ThemeSwatch: View {
  let theme: AppTheme
  let systemColorScheme: ColorScheme

  var body: some View {
    let palette = MaxThemePalette.resolve(
      theme: theme,
      systemColorScheme: systemColorScheme
    )

    ZStack {
      swatchBackground(palette: palette)
      Image(systemName: symbolName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(iconColor(palette: palette))
        .frame(width: 30, height: 30)
        .background(
          palette.primaryContentSurface.opacity(
            theme == .max || theme == .spectrum || theme == .clouds || theme == .daydream || theme == .solarInk ? 0.82 : 1
          ),
          in: Circle()
        )
    }
    .frame(width: 48, height: 48)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(palette.separator, lineWidth: 1)
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func swatchBackground(palette: MaxThemePalette) -> some View {
    if theme == .clouds {
      MeshGradient(
        width: 2,
        height: 2,
        points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
        colors: [
          Color(red: 0.74, green: 0.91, blue: 1.00),
          Color(red: 0.92, green: 0.88, blue: 1.00),
          Color.white,
          Color(red: 1.00, green: 0.88, blue: 0.95),
        ],
        background: palette.canvas,
        smoothsColors: true
      )
    } else if theme == .solarInk {
      ZStack {
        Color(red: 0.051, green: 0.051, blue: 0.051)
        Circle().fill(Color(red: 1, green: 0.77, blue: 0).opacity(0.68)).blur(radius: 7).frame(width: 27, height: 27).offset(x: 14, y: -12)
        Capsule().fill(Color.black.opacity(0.72)).frame(width: 56, height: 13).rotationEffect(.degrees(-20)).offset(x: -9, y: 14)
      }
    } else if theme == .council {
      ZStack {
        Color(red: 0.020, green: 0.020, blue: 0.024)
        LinearGradient(
          colors: [
            Color(red: 0.56, green: 0.06, blue: 0.11).opacity(0.45),
            Color.clear,
            Color(red: 0.02, green: 0.02, blue: 0.02)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    } else if theme == .max {
      MeshGradient(
        width: 2,
        height: 2,
        points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
        colors: palette.isDark
          ? [MaxColor.deepNavy, MaxColor.violet, MaxColor.sky, MaxColor.coral]
          : [MaxColor.sky, MaxColor.lavender, MaxColor.periwinkle, MaxColor.amber],
        background: palette.canvas,
        smoothsColors: true
      )
    } else if theme == .spectrum {
      MeshGradient(
        width: 2,
        height: 2,
        points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
        colors: [
          Color(red: 0.98, green: 0.40, blue: 0.40),
          Color(red: 0.96, green: 0.82, blue: 0.30),
          Color(red: 0.35, green: 0.70, blue: 0.96),
          Color(red: 0.80, green: 0.50, blue: 0.90)
        ],
        background: palette.canvas,
        smoothsColors: true
      )
    } else if theme == .daydream {
      MeshGradient(
        width: 2,
        height: 2,
        points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
        colors: palette.isDark
          ? [
            Color(red: 0.09, green: 0.09, blue: 0.09),
            Color(red: 0.85, green: 0.42, blue: 0.37).opacity(0.55),
            Color(red: 0.38, green: 0.71, blue: 0.62).opacity(0.45),
            Color(red: 0.17, green: 0.18, blue: 0.17)
          ]
          : [
            Color(red: 0.93, green: 0.92, blue: 0.83),
            Color(red: 0.90, green: 0.42, blue: 0.36).opacity(0.45),
            Color(red: 0.41, green: 0.75, blue: 0.65).opacity(0.45),
            Color(red: 0.96, green: 0.94, blue: 0.87)
          ],
        background: palette.canvas,
        smoothsColors: true
      )
    } else {
      palette.canvas
    }
  }

  private var symbolName: String {
    switch theme {
    case .light: "sun.max.fill"
    case .dark: "moon.fill"
    case .max: "sparkles"
    case .spectrum: "paintpalette.fill"
    case .clouds: "cloud.sun.fill"
    case .council: "crown"
    case .solarInk: "sun.max.fill"
    case .daydream: "leaf.fill"
    }
  }

  private func iconColor(palette: MaxThemePalette) -> Color {
    switch theme {
    case .max, .spectrum, .clouds, .daydream: palette.primaryText
    case .council: Color(red: 0.91, green: 0.28, blue: 0.18)
    case .solarInk: Color(red: 1, green: 0.77, blue: 0)
    default: palette.accent
    }
  }
}

private struct OfflineStorageView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @State private var isConfirmingRemoval = false
  @State private var pendingRemoval: LocalDownload?

  var body: some View {
    List {
      Section("storage.offline.summary") {
        LabeledContent(
          "storage.offline.used",
          value: model.transferStore.usedBytes.byteString
        )
        LabeledContent(
          "storage.offline.items",
          value: model.transferStore.items.count.formatted()
        )
      }

      if model.transferStore.items.isEmpty {
        Section {
          ContentUnavailableView(
            "storage.offline.empty",
            systemImage: "arrow.down.circle",
            description: Text("storage.offline.empty.subtitle")
          )
        }
      } else {
        Section("storage.offline.files") {
          ForEach(model.transferStore.items) { item in
            HStack(spacing: MaxSpace.md) {
              Image(systemName: item.kind == "video" ? "play.rectangle" : "doc")
                .foregroundStyle(palette.accent)
              VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                Text(verbatim: item.title)
                  .font(.body.weight(.semibold))
                  .lineLimit(2)
                Text(verbatim: item.sizeBytes.byteString)
                  .font(.caption)
                  .foregroundStyle(MaxColor.textSecondary)
              }
              Spacer(minLength: 0)
              Button("action.remove_download", systemImage: "trash", role: .destructive) {
                pendingRemoval = item
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
            }
          }
        }

        Section {
          Button("storage.offline.remove_all", role: .destructive) {
            isConfirmingRemoval = true
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .maxScreenBackground()
    .navigationTitle("storage.offline.title")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "storage.offline.remove_all.confirm.title",
      isPresented: $isConfirmingRemoval,
      titleVisibility: .visible
    ) {
      Button("storage.offline.remove_all", role: .destructive) {
        model.transferStore.removeAllDownloads()
      }
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("storage.offline.remove_all.confirm.message")
    }
    .confirmationDialog(
      "action.remove_download.confirm.title",
      isPresented: pendingRemovalBinding,
      titleVisibility: .visible,
      presenting: pendingRemoval
    ) { item in
      Button("action.remove_download", role: .destructive) {
        model.transferStore.remove(item)
        pendingRemoval = nil
      }
      Button("common.cancel", role: .cancel) { pendingRemoval = nil }
    } message: { item in
      Text(verbatim: item.title)
    }
  }

  private var pendingRemovalBinding: Binding<Bool> {
    Binding(
      get: { pendingRemoval != nil },
      set: { if !$0 { pendingRemoval = nil } }
    )
  }
}

private struct PrivacyInformationView: View {
  var body: some View {
    List {
      Section("privacy.no_tracking") {
        Label("privacy.no_tracking.detail", systemImage: "checkmark.shield")
      }

      Section("privacy.server_data") {
        PrivacyRow(title: "privacy.account", symbol: "person.crop.circle")
        PrivacyRow(title: "privacy.uploads", symbol: "square.and.arrow.up")
        PrivacyRow(title: "privacy.messages", symbol: "bubble.left.and.bubble.right")
        PrivacyRow(title: "privacy.activity", symbol: "clock.arrow.circlepath")
      }

      Section("privacy.device_data") {
        PrivacyRow(title: "privacy.keychain", symbol: "key")
        PrivacyRow(title: "privacy.offline", symbol: "internaldrive")
        PrivacyRow(title: "privacy.photos", symbol: "photo.on.rectangle")
      }

      Section {
        Text("privacy.server_notice")
          .font(.footnote)
          .foregroundStyle(MaxColor.textSecondary)
      }
    }
    .scrollContentBackground(.hidden)
    .maxScreenBackground()
    .navigationTitle("privacy.title")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PrivacyRow: View {
  let title: LocalizedStringKey
  let symbol: String

  var body: some View {
    Label(title, systemImage: symbol)
  }
}

struct ServerSettingsView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var isPresentedAsSheet = true

  @State private var urlString = ""
  @State private var isSaving = false
  @State private var isConfirmingChange = false
  @State private var serverCheck: ServerCheckState = .idle

  var body: some View {
    Group {
      if isPresentedAsSheet {
        NavigationStack { form }
      } else {
        form
      }
    }
    .onAppear {
      if urlString.isEmpty { urlString = model.serverURLString }
    }
  }

  private var form: some View {
    Form {
      Section {
        TextField("server.url", text: $urlString)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .environment(\.layoutDirection, .leftToRight)
          .accessibilityIdentifier("ui_server_url")
      } header: {
        Text("server.address")
      } footer: {
        Text("server.footer")
      }

      if let error = model.configurationError {
        Section {
          Label {
            Text(verbatim: error)
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
          }
          .foregroundStyle(MaxColor.danger)
        }
      }

      Section {
        Button {
          checkServer()
        } label: {
          Label(
            serverCheck.title,
            systemImage: serverCheck.symbol
          )
        }
        .disabled(serverCheck == .checking || urlString.isEmpty)
        .accessibilityIdentifier("ui_server_check")

        Button("server.save") {
          if model.sessionStore.isAuthenticated,
             urlString.trimmingCharacters(in: .whitespacesAndNewlines) != model.serverURLString {
            isConfirmingChange = true
          } else {
            save()
          }
        }
        .disabled(isSaving || urlString.isEmpty)
      }
    }
    .scrollContentBackground(.hidden)
    .maxScreenBackground()
    .navigationTitle("server.settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if isPresentedAsSheet {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
      }
    }
    .confirmationDialog(
      "server.change.confirm.title",
      isPresented: $isConfirmingChange,
      titleVisibility: .visible
    ) {
      Button("server.change", role: .destructive, action: save)
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("server.change.confirm.message")
    }
  }

  private func save() {
    isSaving = true
    Task {
      let saved = await model.updateBaseURL(urlString)
      isSaving = false
      if saved, isPresentedAsSheet { dismiss() }
    }
  }

  private func checkServer() {
    guard let url = MaxConfiguration.validHTTPURL(from: urlString) else {
      serverCheck = .failed
      return
    }
    serverCheck = .checking
    Task {
      var request = URLRequest(url: url.appendingPathComponent("api/v2/bootstrap"))
      request.httpMethod = "GET"
      request.timeoutInterval = 12
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          serverCheck = .failed
          return
        }
        // 401/403 only proves that the tunnel answers. When this device is
        // signed in, also probe one real media URL with a Range request; that
        // is the contract AVPlayer requires for video playback.
        guard (200..<500).contains(http.statusCode) else {
          serverCheck = .failed
          return
        }
        if model.sessionStore.isAuthenticated,
           let item = model.libraryStore.catalogItems.first(where: { $0.kind == "video" })
             ?? model.libraryStore.catalogItems.first,
           let mediaURL = item.mediaUrl {
          try await model.apiClient.preflightMediaStream(url: mediaURL)
        }
        serverCheck = .reachable
      } catch {
        serverCheck = .failed
      }
    }
  }
}

private enum ServerCheckState: Equatable {
  case idle, checking, reachable, failed

  var title: LocalizedStringKey {
    switch self {
    case .idle: "server.check"
    case .checking: "server.checking"
    case .reachable: "server.reachable"
    case .failed: "server.unreachable"
    }
  }

  var symbol: String {
    switch self {
    case .idle, .checking: "network"
    case .reachable: "checkmark.circle.fill"
    case .failed: "xmark.circle.fill"
    }
  }
}

private struct DiagnosticsView: View {
  @Environment(MaxAppModel.self) private var model

  var body: some View {
    List {
      Section("diagnostics.connection") {
        LabeledContent("diagnostics.network") {
          Label(
            model.networkMonitor.isOnline ? "diagnostics.online" : "diagnostics.offline",
            systemImage: model.networkMonitor.isOnline ? "checkmark.circle.fill" : "wifi.slash"
          )
          .foregroundStyle(model.networkMonitor.isOnline ? MaxColor.mint : MaxColor.warning)
        }
        LabeledContent("diagnostics.server") {
          Text(verbatim: model.serverURLString)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .environment(\.layoutDirection, .leftToRight)
        }
      }

      Section("diagnostics.identity") {
        LabeledContent("settings.bundle_id") {
          Text(verbatim: Bundle.main.bundleIdentifier ?? "app.max.iphone")
            .font(.caption.monospaced())
            .environment(\.layoutDirection, .leftToRight)
        }
        LabeledContent("diagnostics.target", value: "Max")
        LabeledContent("diagnostics.platform") {
          Text(verbatim: "iOS 26+")
            .environment(\.layoutDirection, .leftToRight)
        }
      }

      Section("diagnostics.capabilities") {
        DiagnosticCapabilityRow(title: "diagnostics.uploads", available: true)
        DiagnosticCapabilityRow(
          title: "diagnostics.downloads",
          available: model.sessionStore.capabilities?.manualDownloads ?? false
        )
        DiagnosticCapabilityRow(
          title: "diagnostics.access_requests",
          available: model.sessionStore.capabilities?.requestAccess ?? false
        )
        DiagnosticCapabilityRow(
          title: "diagnostics.push",
          available: model.sessionStore.capabilities?.pushNotifications ?? false
        )
        DiagnosticCapabilityRow(
          title: "diagnostics.calls",
          available: (model.sessionStore.capabilities?.voiceCalls ?? false)
            || (model.sessionStore.capabilities?.videoCalls ?? false)
        )
      }

      Section("diagnostics.explanations") {
        Text("diagnostics.capabilities_explanation")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .scrollContentBackground(.hidden)
    .maxScreenBackground()
    .navigationTitle("diagnostics.title")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct DiagnosticCapabilityRow: View {
  let title: LocalizedStringKey
  let available: Bool
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    LabeledContent(title) {
      Label(
        available ? "diagnostics.available" : "diagnostics.not_available",
        systemImage: available ? "checkmark.circle.fill" : "minus.circle"
      )
      .foregroundStyle(available ? palette.success : palette.secondaryText)
    }
  }
}
