import Foundation
import Observation
import SwiftUI

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
  case light
  case dark
  case max
  case spectrum
  case clouds
  case council
  case daydream
  case solarInk

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .light: "settings.theme.light"
    case .dark: "settings.theme.dark"
    case .max: "settings.theme.max"
    case .spectrum: "settings.theme.spectrum"
    case .clouds: "settings.theme.clouds"
    case .council: "settings.theme.council"
    case .daydream: "settings.theme.daydream"
    case .solarInk: "settings.theme.solarInk"
    }
  }

  var descriptionKey: LocalizedStringKey {
    switch self {
    case .light: "settings.theme.light.description"
    case .dark: "settings.theme.dark.description"
    case .max: "settings.theme.max.description"
    case .spectrum: "settings.theme.spectrum.description"
    case .clouds: "settings.theme.clouds.description"
    case .council: "settings.theme.council.description"
    case .daydream: "settings.theme.daydream.description"
    case .solarInk: "settings.theme.solarInk.description"
    }
  }

  var forcedColorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .max, .spectrum, .daydream: nil
    case .clouds: .light
    case .council, .solarInk: .dark
    }
  }

  static func persistedValue(_ rawValue: String?) -> AppTheme {
    switch rawValue {
    case AppTheme.light.rawValue:
      .light
    case AppTheme.dark.rawValue:
      .dark
    case AppTheme.max.rawValue, "system":
      .max
    case AppTheme.spectrum.rawValue:
      .spectrum
    case AppTheme.clouds.rawValue:
      .clouds
    case AppTheme.council.rawValue:
      .council
    case AppTheme.daydream.rawValue:
      .daydream
    case AppTheme.solarInk.rawValue:
      .solarInk
    default:
      .max
    }
  }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
  case system
  case english = "en"
  case arabic = "ar"
  case russian = "ru"

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .system: "settings.language.system"
    case .english: "settings.language.en"
    case .arabic: "settings.language.ar"
    case .russian: "settings.language.ru"
    }
  }

  var localeIdentifier: String? {
    switch self {
    case .system: nil
    case .english: "en"
    case .arabic: "ar"
    case .russian: "ru"
    }
  }
}

enum DownloadNetworkPreference: String, Codable, CaseIterable, Identifiable, Sendable {
  case wifiOnly
  case wifiAndCellular

  var id: String { rawValue }
  var allowsCellular: Bool { self == .wifiAndCellular }

  var titleKey: LocalizedStringKey {
    switch self {
    case .wifiOnly: "settings.download_network.wifiOnly"
    case .wifiAndCellular: "settings.download_network.wifiAndCellular"
    }
  }
}

@MainActor
@Observable
final class AppPreferencesStore {
  private enum Key {
    static let appearance = "app.max.preferences.appearance"
    static let language = "app.max.preferences.language"
    static let playbackSpeed = "app.max.preferences.playbackSpeed"
    static let controlsHideSeconds = "app.max.preferences.controlsHideSeconds"
    static let flowModeAutoAdvance = "app.max.preferences.flowModeAutoAdvance"
    static let downloadNetwork = "app.max.preferences.downloadNetwork"
    static let reduceBackgroundMotion = "app.max.preferences.reduceBackgroundMotion"
    static let appLockEnabled = "app.max.preferences.appLockEnabled"
    static let lastRootTab = "app.max.preferences.lastRootTab"
    static let nicknames = "app.max.preferences.nicknames"
    static let blockedUsers = "app.max.preferences.blockedUsers"
    // Black Council - The Gathering
    static let councilGatheringShown = "app.max.preferences.council_gathering_shown"
    
    // Caching
    static let enableThumbnailCache = "app.max.preferences.enableThumbnailCache"
    static let thumbnailCacheLimitMB = "app.max.preferences.thumbnailCacheLimitMB"
    static let enableVideoPreCache = "app.max.preferences.enableVideoPreCache"
    static let videoPreCacheSizeMB = "app.max.preferences.videoPreCacheSizeMB"
    static let videoPrefetchAdjacentCount = "app.max.preferences.videoPrefetchAdjacentCount"
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var isLoading = true

  var nicknames: [String: String] {
    didSet {
      if let data = try? JSONEncoder().encode(nicknames) {
        persist(data, forKey: Key.nicknames)
      }
    }
  }

  var blockedUserIDs: Set<String> {
    didSet {
      let array = Array(blockedUserIDs)
      if let data = try? JSONEncoder().encode(array) {
        persist(data, forKey: Key.blockedUsers)
      }
    }
  }

  var theme: AppTheme {
    didSet { persist(theme.rawValue, forKey: Key.appearance) }
  }

  var language: AppLanguage {
    didSet { persist(language.rawValue, forKey: Key.language) }
  }

  var playbackSpeed: Double {
    didSet {
      let normalized = Self.normalizedPlaybackSpeed(playbackSpeed)
      if playbackSpeed != normalized {
        playbackSpeed = normalized
        return
      }
      persist(playbackSpeed, forKey: Key.playbackSpeed)
    }
  }

  /// Player chrome idle delay, in seconds (2, 3 or 5 — the legacy app's choices).
  var controlsHideSeconds: Int {
    didSet {
      let normalized = Self.normalizedControlsHideSeconds(controlsHideSeconds)
      if controlsHideSeconds != normalized {
        controlsHideSeconds = normalized
        return
      }
      persist(controlsHideSeconds, forKey: Key.controlsHideSeconds)
    }
  }

  /// Flow Mode: when a video ends, count down and play the next one.
  var flowModeAutoAdvance: Bool {
    didSet { persist(flowModeAutoAdvance, forKey: Key.flowModeAutoAdvance) }
  }

  var downloadNetworkPreference: DownloadNetworkPreference {
    didSet { persist(downloadNetworkPreference.rawValue, forKey: Key.downloadNetwork) }
  }

  var reduceBackgroundMotion: Bool {
    didSet { persist(reduceBackgroundMotion, forKey: Key.reduceBackgroundMotion) }
  }

  /// Face ID gate over the whole app: launch and foreground must pass the
  /// device-owner check before content shows.
  var appLockEnabled: Bool {
    didSet { persist(appLockEnabled, forKey: Key.appLockEnabled) }
  }

  var lastRootTab: String {
    didSet { persist(lastRootTab, forKey: Key.lastRootTab) }
  }

  // Caching
  var enableThumbnailCache: Bool {
    didSet { persist(enableThumbnailCache, forKey: Key.enableThumbnailCache) }
  }

  var thumbnailCacheLimitMB: Int {
    didSet { persist(thumbnailCacheLimitMB, forKey: Key.thumbnailCacheLimitMB) }
  }

  var enableVideoPreCache: Bool {
    didSet { persist(enableVideoPreCache, forKey: Key.enableVideoPreCache) }
  }

  var videoPreCacheSizeMB: Int {
    didSet { persist(videoPreCacheSizeMB, forKey: Key.videoPreCacheSizeMB) }
  }

  var videoPrefetchAdjacentCount: Int {
    didSet { persist(videoPrefetchAdjacentCount, forKey: Key.videoPrefetchAdjacentCount) }
  }

  // MARK: - Black Council: The Gathering

  var hasShownCouncilGathering: Bool {
    get { defaults.bool(forKey: Key.councilGatheringShown) }
    set { defaults.set(newValue, forKey: Key.councilGatheringShown) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let nicknamesData = defaults.data(forKey: Key.nicknames),
       let decoded = try? JSONDecoder().decode([String: String].self, from: nicknamesData) {
      self.nicknames = decoded
    } else {
      self.nicknames = [:]
    }

    if let blockedData = defaults.data(forKey: Key.blockedUsers),
       let decoded = try? JSONDecoder().decode([String].self, from: blockedData) {
      self.blockedUserIDs = Set(decoded)
    } else {
      self.blockedUserIDs = []
    }

    let storedTheme = defaults.string(forKey: Key.appearance)
    self.theme = AppTheme.persistedValue(storedTheme)
    self.language = AppLanguage(
      rawValue: defaults.string(forKey: Key.language) ?? ""
    ) ?? .system

    let savedSpeed = defaults.object(forKey: Key.playbackSpeed) as? NSNumber
    self.playbackSpeed = Self.normalizedPlaybackSpeed(savedSpeed?.doubleValue ?? 1)
    let savedHide = defaults.object(forKey: Key.controlsHideSeconds) as? NSNumber
    self.controlsHideSeconds = Self.normalizedControlsHideSeconds(savedHide?.intValue ?? 2)
    self.flowModeAutoAdvance = defaults.bool(forKey: Key.flowModeAutoAdvance)
    self.downloadNetworkPreference = DownloadNetworkPreference(
      rawValue: defaults.string(forKey: Key.downloadNetwork) ?? ""
    ) ?? .wifiOnly
    self.reduceBackgroundMotion = defaults.object(forKey: Key.reduceBackgroundMotion) == nil
      ? false
      : defaults.bool(forKey: Key.reduceBackgroundMotion)
    self.appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
    self.lastRootTab = defaults.string(forKey: Key.lastRootTab) ?? "vault"
    
    // Caching Initializers
    self.enableThumbnailCache = defaults.object(forKey: Key.enableThumbnailCache) == nil ? true : defaults.bool(forKey: Key.enableThumbnailCache)
    self.thumbnailCacheLimitMB = defaults.object(forKey: Key.thumbnailCacheLimitMB) == nil ? 250 : defaults.integer(forKey: Key.thumbnailCacheLimitMB)
    self.enableVideoPreCache = defaults.object(forKey: Key.enableVideoPreCache) == nil ? true : defaults.bool(forKey: Key.enableVideoPreCache)
    self.videoPreCacheSizeMB = defaults.object(forKey: Key.videoPreCacheSizeMB) == nil ? 2 : defaults.integer(forKey: Key.videoPreCacheSizeMB)
    self.videoPrefetchAdjacentCount = defaults.object(forKey: Key.videoPrefetchAdjacentCount) == nil ? 2 : defaults.integer(forKey: Key.videoPrefetchAdjacentCount)
    
    self.isLoading = false

    // The retired "system" option already followed the device appearance. Max
    // preserves that behavior while adding the branded light/dark atmosphere.
    if storedTheme == "system" {
      defaults.set(AppTheme.max.rawValue, forKey: Key.appearance)
    }
  }

  var allowsCellularDownloads: Bool {
    downloadNetworkPreference.allowsCellular
  }

  var colorScheme: ColorScheme? {
    theme.forcedColorScheme
  }

  var locale: Locale {
    language.localeIdentifier.map { Locale(identifier: $0) } ?? .current
  }

  var layoutDirection: LayoutDirection {
    switch language {
    case .arabic:
      .rightToLeft
    case .english:
      .leftToRight
    case .russian:
      .leftToRight
    case .system:
      Locale.Language(
        identifier: Locale.current.language.languageCode?.identifier ?? "en"
      ).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
  }

  var playbackRate: Float {
    get { Float(playbackSpeed) }
    set { playbackSpeed = Double(newValue) }
  }

  var allowCellularDownloads: Bool {
    get { downloadNetworkPreference.allowsCellular }
    set {
      downloadNetworkPreference = newValue ? .wifiAndCellular : .wifiOnly
    }
  }

  var calmBackground: Bool {
    get { reduceBackgroundMotion }
    set { reduceBackgroundMotion = newValue }
  }

  func reset() {
    theme = .max
    language = .system
    playbackSpeed = 1
    controlsHideSeconds = 2
    flowModeAutoAdvance = false
    downloadNetworkPreference = .wifiOnly
    reduceBackgroundMotion = false
    appLockEnabled = false
    lastRootTab = "vault"
    enableThumbnailCache = true
    thumbnailCacheLimitMB = 250
    enableVideoPreCache = true
    videoPreCacheSizeMB = 2
    videoPrefetchAdjacentCount = 2
  }

  private func persist(_ value: Any, forKey key: String) {
    guard !isLoading else { return }
    defaults.set(value, forKey: key)
  }

  private static func normalizedPlaybackSpeed(_ value: Double) -> Double {
    guard value.isFinite else { return 1 }
    let supported: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    return supported.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1
  }

  private static func normalizedControlsHideSeconds(_ value: Int) -> Int {
    [2, 3, 5].contains(value) ? value : 2
  }
}
