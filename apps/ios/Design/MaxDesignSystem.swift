import SwiftUI
import UIKit
import CoreMotion
import Observation

// MARK: - Gyroscope Parallax Observer

/// Device-motion parallax source for the Clouds atmosphere. Only that theme
/// consumes `offset`, so `start()` is reference counted and every caller must
/// pair it with exactly one `stop()`: a single unpaired stop used to kill
/// parallax for every other live surface in the app.
@Observable
@MainActor
final class GyroscopeObserver {
  static let shared = GyroscopeObserver()

  var offset: CGSize = .zero

  private let motionManager = CMMotionManager()
  @ObservationIgnored private var clients = 0
  @ObservationIgnored private var isStarted = false

  private init() {}

  func start() {
    clients += 1
    guard clients == 1, !isStarted else { return }
    guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
    guard motionManager.isDeviceMotionAvailable else { return }
    // 20 Hz is imperceptible across a 20 pt parallax range and costs a third of
    // 60 Hz. Samples are gathered off the main thread and only published when
    // the offset actually moves, so an idle device invalidates nothing.
    motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
    // Deliver on the main queue. The handler closure inherits this @MainActor
    // class's isolation, so running it on a background OperationQueue tripped a
    // Swift 6 executor-isolation assertion (dispatch_assert_queue) and crashed —
    // which bricked the whole app under the Clouds theme, the only caller. At
    // 20 Hz the work is trivial on the main thread.
    motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
      guard let self, let motion else { return }
      let maxOffset: CGFloat = 20.0
      let xOffset = CGFloat(motion.attitude.roll) * 12.0
      let yOffset = CGFloat(motion.attitude.pitch) * 12.0
      let next = CGSize(
        width: min(max(xOffset, -maxOffset), maxOffset),
        height: min(max(yOffset, -maxOffset), maxOffset)
      )
      self.publish(next)
    }
    isStarted = true
  }

  func stop() {
    clients = max(0, clients - 1)
    guard clients == 0, isStarted else { return }
    motionManager.stopDeviceMotionUpdates()
    isStarted = false
    offset = .zero
  }

  private func publish(_ next: CGSize) {
    guard isStarted else { return }
    guard abs(next.width - offset.width) > 0.25
            || abs(next.height - offset.height) > 0.25 else { return }
    offset = next
  }
}

// MARK: - Shared atmosphere clock

/// One clock for every atmosphere layer in the app. Each `MaxLivingBackground`
/// claims it only while it is on screen, foregrounded and allowed to move, so
/// the timer stops entirely when nothing needs it — instead of every live
/// instance driving its own `TimelineView`.
@Observable
@MainActor
final class MaxAtmosphereClock {
  static let shared = MaxAtmosphereClock()

  private(set) var phase: TimeInterval = Date().timeIntervalSinceReferenceDate

  @ObservationIgnored private var clients: Set<UUID> = []
  @ObservationIgnored private var ticker: Task<Void, Never>?

  private init() {}

  func claim(_ client: UUID) {
    clients.insert(client)
    guard ticker == nil else { return }
    ticker = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
          // Low Power Mode freezes the atmosphere; poll cheaply for the exit.
          try? await Task.sleep(for: .seconds(1))
        } else {
          self.phase = Date().timeIntervalSinceReferenceDate
          try? await Task.sleep(for: .milliseconds(83))
        }
      }
    }
  }

  func resign(_ client: UUID) {
    guard clients.remove(client) != nil, clients.isEmpty else { return }
    ticker?.cancel()
    ticker = nil
  }
}

// MARK: - Semantic tokens

enum MaxThemeVariant: String, Sendable {
  case neutralLight
  case neutralDark
  case maxLight
  case maxDark
  case spectrumLight
  case spectrumDark
  case clouds
  case council
  case daydreamLight
  case daydreamDark
  case solarInk
}

struct MaxThemePalette {
  let selectedTheme: AppTheme
  let variant: MaxThemeVariant
  let canvas: Color
  let atmosphericBackground: Color
  let primaryContentSurface: Color
  let elevatedContentSurface: Color
  let primaryText: Color
  let secondaryText: Color
  let tertiaryText: Color
  let separator: Color
  let accent: Color
  let selectedControl: Color
  let destructive: Color
  let warning: Color
  let success: Color
  let disabled: Color
  let mediaOverlay: Color
  let scrim: Color

  var isDark: Bool {
    variant == .neutralDark || variant == .maxDark || variant == .spectrumDark || variant == .council || variant == .daydreamDark || variant == .solarInk
  }

  var isCouncil: Bool { variant == .council }

  /// Foreground for controls that use the semantic accent as a solid fill.
  /// Dark variants intentionally use a bright cyan accent, so white text is
  /// not contrast-safe there.
  var accentForeground: Color {
    switch variant {
    case .neutralLight, .maxLight, .spectrumLight, .clouds, .council, .daydreamLight:
      Color.white
    case .neutralDark, .maxDark, .spectrumDark, .daydreamDark, .solarInk:
      .maxRGB(0x10131A)
    }
  }

  /// Foreground for solid success fills, which invert luminance between the
  /// neutral/Max light and dark palettes.
  var successForeground: Color {
    switch variant {
    case .neutralLight, .maxLight, .spectrumLight, .clouds, .council, .daydreamLight, .solarInk:
      Color.white
    case .neutralDark, .maxDark, .spectrumDark, .daydreamDark:
      .maxRGB(0x10131A)
    }
  }

  static func resolve(
    theme: AppTheme,
    systemColorScheme: ColorScheme,
    increasedContrast: Bool = false
  ) -> MaxThemePalette {
    switch theme {
    case .light:
      neutralLight(increasedContrast: increasedContrast)
    case .dark:
      neutralDark(increasedContrast: increasedContrast)
    case .max:
      systemColorScheme == .dark
        ? maxDark(increasedContrast: increasedContrast)
        : maxLight(increasedContrast: increasedContrast)
    case .spectrum:
      systemColorScheme == .dark
        ? spectrumDark(increasedContrast: increasedContrast)
        : spectrumLight(increasedContrast: increasedContrast)
    case .clouds:
      clouds(increasedContrast: increasedContrast)
    case .council:
      councilDark(increasedContrast: increasedContrast)
    case .daydream:
      systemColorScheme == .dark
        ? daydreamDark(increasedContrast: increasedContrast)
        : daydreamLight(increasedContrast: increasedContrast)
    case .solarInk:
      solarInk(increasedContrast: increasedContrast)
    }
  }

  private static func neutralLight(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .light,
      variant: .neutralLight,
      canvas: .maxRGB(0xF7F8FA),
      atmosphericBackground: .maxRGB(0xF7F8FA),
      primaryContentSurface: .maxRGB(0xFFFFFF),
      elevatedContentSurface: .maxRGB(0xEEF1F4),
      primaryText: .maxRGB(0x10131A),
      secondaryText: .maxRGB(increasedContrast ? 0x303640 : 0x525866),
      tertiaryText: .maxRGB(increasedContrast ? 0x454B56 : 0x656C78),
      separator: .maxRGB(0x10131A, opacity: increasedContrast ? 0.26 : 0.14),
      accent: .maxRGB(increasedContrast ? 0x004F73 : 0x00658C),
      selectedControl: .maxRGB(0xE1EEF4),
      destructive: .maxRGB(0xC52B30),
      warning: .maxRGB(0x9A5400),
      success: .maxRGB(0x147A43),
      disabled: .maxRGB(0x8B919B),
      mediaOverlay: .maxRGB(0x10131A, opacity: 0.72),
      scrim: .maxRGB(0x10131A, opacity: 0.38)
    )
  }

  private static func neutralDark(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .dark,
      variant: .neutralDark,
      canvas: .maxRGB(0x111318),
      atmosphericBackground: .maxRGB(0x111318),
      primaryContentSurface: .maxRGB(0x1C2027),
      elevatedContentSurface: .maxRGB(0x272C35),
      primaryText: .maxRGB(0xF3F3F7),
      secondaryText: .maxRGB(increasedContrast ? 0xE2E4EA : 0xBEC2D0),
      tertiaryText: .maxRGB(increasedContrast ? 0xC7CBD5 : 0x969DAC),
      separator: .maxRGB(0xF3F3F7, opacity: increasedContrast ? 0.30 : 0.16),
      accent: .maxRGB(increasedContrast ? 0xA9E5FA : 0x78C8E8),
      selectedControl: .maxRGB(0x2C3E4A),
      destructive: .maxRGB(0xFF7972),
      warning: .maxRGB(0xFFB454),
      success: .maxRGB(0x62D68E),
      disabled: .maxRGB(0x747B88),
      mediaOverlay: .maxRGB(0x000000, opacity: 0.76),
      scrim: .maxRGB(0x000000, opacity: 0.56)
    )
  }

  private static func maxLight(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .max,
      variant: .maxLight,
      canvas: .maxRGB(0xF2F9FA),
      atmosphericBackground: .maxRGB(0x7ECBEF),
      primaryContentSurface: .maxRGB(0xF9FAFB),
      elevatedContentSurface: .maxRGB(0xFFFFFF),
      primaryText: .maxRGB(0x10131A),
      secondaryText: .maxRGB(increasedContrast ? 0x303640 : 0x525866),
      tertiaryText: .maxRGB(increasedContrast ? 0x444A54 : 0x656C78),
      separator: .maxRGB(0x10131A, opacity: increasedContrast ? 0.28 : 0.15),
      accent: .maxRGB(increasedContrast ? 0x004F73 : 0x00658C),
      selectedControl: .maxRGB(0xDCECF2),
      destructive: .maxRGB(0xC52B30),
      warning: .maxRGB(0x925000),
      success: .maxRGB(0x147A43),
      disabled: .maxRGB(0x858C97),
      mediaOverlay: .maxRGB(0x10131A, opacity: 0.74),
      scrim: .maxRGB(0x11182A, opacity: 0.42)
    )
  }

  private static func maxDark(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .max,
      variant: .maxDark,
      canvas: .maxRGB(0x161E33),
      atmosphericBackground: .maxRGB(0x32396B),
      primaryContentSurface: .maxRGB(0x202B48),
      elevatedContentSurface: .maxRGB(0x2E365E),
      primaryText: .maxRGB(0xF3F3F7),
      secondaryText: .maxRGB(increasedContrast ? 0xE3E5ED : 0xBEC2D0),
      tertiaryText: .maxRGB(increasedContrast ? 0xC9CDDA : 0x979EB2),
      separator: .maxRGB(0xF3F3F7, opacity: increasedContrast ? 0.32 : 0.18),
      accent: .maxRGB(increasedContrast ? 0xB9EDFF : 0x78C8E8),
      selectedControl: .maxRGB(0x38417E),
      destructive: .maxRGB(0xFF8A7A),
      warning: .maxRGB(0xF2B35F),
      success: .maxRGB(0x6FDBA0),
      disabled: .maxRGB(0x747B91),
      mediaOverlay: .maxRGB(0x050711, opacity: 0.80),
      scrim: .maxRGB(0x050711, opacity: 0.62)
    )
  }

  private static func spectrumLight(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .spectrum,
      variant: .spectrumLight,
      canvas: .maxRGB(0xF7F4FC),
      atmosphericBackground: .maxRGB(0xF3D5FF),
      primaryContentSurface: .maxRGB(0xFCFAFF),
      elevatedContentSurface: .maxRGB(0xFFFFFF),
      primaryText: .maxRGB(0x1A0C2B),
      secondaryText: .maxRGB(increasedContrast ? 0x2A124A : 0x614882),
      tertiaryText: .maxRGB(increasedContrast ? 0x482470 : 0x8A72A8),
      separator: .maxRGB(0x1A0C2B, opacity: increasedContrast ? 0.28 : 0.15),
      accent: .maxRGB(0x8A46E5),
      selectedControl: .maxRGB(0xF2EAFB),
      destructive: .maxRGB(0xC52B30),
      warning: .maxRGB(0x925000),
      success: .maxRGB(0x147A43),
      disabled: .maxRGB(0x9A8EAA),
      mediaOverlay: .maxRGB(0x10131A, opacity: 0.74),
      scrim: .maxRGB(0x11182A, opacity: 0.42)
    )
  }

  private static func spectrumDark(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .spectrum,
      variant: .spectrumDark,
      canvas: .maxRGB(0x120C1F),
      atmosphericBackground: .maxRGB(0x27193D),
      primaryContentSurface: .maxRGB(0x1E1430),
      elevatedContentSurface: .maxRGB(0x2A1D42),
      primaryText: .maxRGB(0xF6F2FF),
      secondaryText: .maxRGB(increasedContrast ? 0xECE5FF : 0xC0B5D9),
      tertiaryText: .maxRGB(increasedContrast ? 0xD1C5F9 : 0x9B8FB6),
      separator: .maxRGB(0xF6F2FF, opacity: increasedContrast ? 0.32 : 0.18),
      accent: .maxRGB(0xA86BFC),
      selectedControl: .maxRGB(0x3B2861),
      destructive: .maxRGB(0xFF8A7A),
      warning: .maxRGB(0xF2B35F),
      success: .maxRGB(0x6FDBA0),
      disabled: .maxRGB(0x7D7293),
      mediaOverlay: .maxRGB(0x0C0717, opacity: 0.80),
      scrim: .maxRGB(0x0C0717, opacity: 0.62)
    )
  }

  private static func clouds(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .clouds,
      variant: .clouds,
      canvas: .maxRGB(0xF5FAFF),
      atmosphericBackground: .maxRGB(0xDDF2FF),
      primaryContentSurface: .maxRGB(0xFFFFFF, opacity: 0.72),
      elevatedContentSurface: .maxRGB(0xF8F4FF, opacity: 0.84),
      primaryText: .maxRGB(0x17345A),
      secondaryText: .maxRGB(increasedContrast ? 0x294560 : 0x49647D),
      tertiaryText: .maxRGB(increasedContrast ? 0x40576F : 0x687E93),
      separator: .maxRGB(0x315F8E, opacity: increasedContrast ? 0.30 : 0.16),
      accent: .maxRGB(increasedContrast ? 0x3152A8 : 0x526DD5),
      selectedControl: .maxRGB(0xE7E9FF, opacity: 0.86),
      destructive: .maxRGB(0xC52B55),
      warning: .maxRGB(0x8B5B00),
      success: .maxRGB(0x147A67),
      disabled: .maxRGB(0x8A9BAA),
      mediaOverlay: .maxRGB(0x142B47, opacity: 0.70),
      scrim: .maxRGB(0x274463, opacity: 0.34)
    )
  }

  private static func councilDark(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .council,
      variant: .council,
      canvas: .maxRGB(0x050506),
      atmosphericBackground: .maxRGB(0x0B0A0D),
      primaryContentSurface: .maxRGB(0x121014),
      elevatedContentSurface: .maxRGB(0x1A1720),
      primaryText: .maxRGB(0xF3F0EE),
      secondaryText: .maxRGB(increasedContrast ? 0xC8C5C4 : 0x989398),
      tertiaryText: .maxRGB(increasedContrast ? 0xADA9A8 : 0x6B686B),
      separator: .maxRGB(0xF3F0EE, opacity: increasedContrast ? 0.22 : 0.12),
      accent: .maxRGB(increasedContrast ? 0xE53040 : 0xC21F2E),
      selectedControl: .maxRGB(0x2A1820),
      destructive: .maxRGB(0xFF6B6B),
      warning: .maxRGB(0xE8482D),
      success: .maxRGB(0x8CA88A),
      disabled: .maxRGB(0x4A474A),
      mediaOverlay: .maxRGB(0x000000, opacity: 0.82),
      scrim: .maxRGB(0x000000, opacity: 0.68)
    )
  }

  private static func daydreamLight(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .daydream,
      variant: .daydreamLight,
      canvas: .maxRGB(0xEEEBD3),
      atmosphericBackground: .maxRGB(0xF5F0DE),
      primaryContentSurface: .maxRGB(0xFAF6E8),
      elevatedContentSurface: .maxRGB(0xFFFBEF),
      primaryText: .maxRGB(0x292825),
      secondaryText: .maxRGB(increasedContrast ? 0x3C3A35 : 0x69665C),
      tertiaryText: .maxRGB(increasedContrast ? 0x525048 : 0x89867C),
      separator: .maxRGB(0x292825, opacity: increasedContrast ? 0.20 : 0.10),
      accent: .maxRGB(increasedContrast ? 0xBF4F42 : 0xE66B5B),
      selectedControl: .maxRGB(0xEFE9D4),
      destructive: .maxRGB(0xBF3B2A),
      warning: .maxRGB(0x8A6200),
      success: .maxRGB(0x2E7B65),
      disabled: .maxRGB(0xA8A59C),
      mediaOverlay: .maxRGB(0x292825, opacity: 0.72),
      scrim: .maxRGB(0x292825, opacity: 0.38)
    )
  }

  private static func daydreamDark(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .daydream,
      variant: .daydreamDark,
      canvas: .maxRGB(0x171817),
      atmosphericBackground: .maxRGB(0x1E201E),
      primaryContentSurface: .maxRGB(0x242522),
      elevatedContentSurface: .maxRGB(0x2B2C28),
      primaryText: .maxRGB(0xF1E8D5),
      secondaryText: .maxRGB(increasedContrast ? 0xD8CFBC : 0xB8AF9F),
      tertiaryText: .maxRGB(increasedContrast ? 0xC0B8A5 : 0x8A8278),
      separator: .maxRGB(0xF1E8D5, opacity: increasedContrast ? 0.18 : 0.09),
      accent: .maxRGB(increasedContrast ? 0xE57E72 : 0xD96C5E),
      selectedControl: .maxRGB(0x2E2E2A),
      destructive: .maxRGB(0xFF8A7A),
      warning: .maxRGB(0xE8A840),
      success: .maxRGB(0x62B49E),
      disabled: .maxRGB(0x6A6860),
      mediaOverlay: .maxRGB(0x0E0F0E, opacity: 0.80),
      scrim: .maxRGB(0x0E0F0E, opacity: 0.62)
    )
  }

  /// Semantic Solar Ink tokens: warm yellow only carries focus and identity.
  private static func solarInk(increasedContrast: Bool) -> MaxThemePalette {
    MaxThemePalette(
      selectedTheme: .solarInk, variant: .solarInk,
      canvas: .maxRGB(0x0D0D0D), atmosphericBackground: .maxRGB(0x111111),
      primaryContentSurface: .maxRGB(0x171717, opacity: 0.92), elevatedContentSurface: .maxRGB(0x242424, opacity: 0.94),
      primaryText: .maxRGB(0xFFF4DC), secondaryText: .maxRGB(increasedContrast ? 0xDDD2BD : 0xB6AD9E),
      tertiaryText: .maxRGB(increasedContrast ? 0xAAA192 : 0x6D6D6D), separator: .maxRGB(0xFFF4DC, opacity: increasedContrast ? 0.24 : 0.12),
      accent: .maxRGB(0xFFC400), selectedControl: .maxRGB(0x3A310E), destructive: .maxRGB(0xFF7A6E),
      warning: .maxRGB(0xFFD84D), success: .maxRGB(0x82D6A3), disabled: .maxRGB(0x6D6D6D),
      mediaOverlay: .maxRGB(0x000000, opacity: 0.80), scrim: .maxRGB(0x000000, opacity: 0.68)
    )
  }
}

private extension Color {
  static func maxRGB(_ hex: UInt32, opacity: Double = 1) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

private struct MaxThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = AppTheme.max
}

private struct MaxThemePaletteEnvironmentKey: EnvironmentKey {
  static let defaultValue = MaxThemePalette.resolve(
    theme: .max,
    systemColorScheme: .light
  )
}

extension EnvironmentValues {
  var appTheme: AppTheme {
    get { self[MaxThemeEnvironmentKey.self] }
    set { self[MaxThemeEnvironmentKey.self] = newValue }
  }

  var maxThemePalette: MaxThemePalette {
    get { self[MaxThemePaletteEnvironmentKey.self] }
    set { self[MaxThemePaletteEnvironmentKey.self] = newValue }
  }
}

struct MaxThemeHost<Content: View>: View {
  let theme: AppTheme
  let content: Content

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false

  init(theme: AppTheme, @ViewBuilder content: () -> Content) {
    self.theme = theme
    self.content = content()
  }

  var body: some View {
    let resolved = MaxThemePalette.resolve(
      theme: theme,
      systemColorScheme: colorScheme,
      increasedContrast: colorSchemeContrast == .increased
    )
    let palette = PluginStore.shared.activeVisualPlugin?.overridePalette(for: theme, systemColorScheme: colorScheme) ?? resolved
    content
      .environment(\.appTheme, theme)
      .environment(\.maxThemePalette, palette)
      // One source of truth for motion: the system switch and the in-app
      // preference now gate every animation that reads `\.maxMotionEnabled`.
      .environment(\.maxMotionEnabled, !(reduceMotion || calmBackground))
      .tint(palette.accent)
  }
}

enum MaxSemanticRole {
  case canvas
  case atmosphericBackground
  case primaryContentSurface
  case elevatedContentSurface
  case primaryText
  case secondaryText
  case tertiaryText
  case separator
  case selectedControl
  case destructive
  case warning
  case success
  case disabled
  case mediaOverlay
  case scrim
}

struct MaxSemanticStyle: ShapeStyle {
  let role: MaxSemanticRole
  let opacityValue: Double

  init(_ role: MaxSemanticRole, opacity: Double = 1) {
    self.role = role
    self.opacityValue = opacity
  }

  func resolve(in environment: EnvironmentValues) -> Color {
    color(from: environment.maxThemePalette).opacity(opacityValue)
  }

  func withOpacity(_ opacity: Double) -> MaxSemanticStyle {
    MaxSemanticStyle(role, opacity: opacityValue * opacity)
  }

  private func color(from palette: MaxThemePalette) -> Color {
    switch role {
    case .canvas: palette.canvas
    case .atmosphericBackground: palette.atmosphericBackground
    case .primaryContentSurface: palette.primaryContentSurface
    case .elevatedContentSurface: palette.elevatedContentSurface
    case .primaryText: palette.primaryText
    case .secondaryText: palette.secondaryText
    case .tertiaryText: palette.tertiaryText
    case .separator: palette.separator
    case .selectedControl: palette.selectedControl
    case .destructive: palette.destructive
    case .warning: palette.warning
    case .success: palette.success
    case .disabled: palette.disabled
    case .mediaOverlay: palette.mediaOverlay
    case .scrim: palette.scrim
    }
  }
}

enum MaxColor {
  static let sky = Color(red: 0.333, green: 0.741, blue: 0.922)
  static let periwinkle = Color(red: 0.663, green: 0.682, blue: 0.949)
  static let lavender = Color(red: 0.788, green: 0.722, blue: 0.957)
  static let rose = Color(red: 0.910, green: 0.659, blue: 0.835)
  static let amber = Color(red: 0.851, green: 0.604, blue: 0.345)
  static let deepNavy = Color(red: 0.067, green: 0.094, blue: 0.165)
  static let midnight = Color(red: 0.145, green: 0.169, blue: 0.314)
  static let violet = Color(red: 0.384, green: 0.396, blue: 0.714)
  static let coral = Color(red: 0.863, green: 0.502, blue: 0.396)

  static var accent: Color {
    let themeRaw = UserDefaults.standard.string(forKey: "app.max.preferences.appearance") ?? "clouds"
    let theme = AppTheme(rawValue: themeRaw) ?? .clouds
    // Determine color scheme from UITraitCollection (safe in nonisolated context)
    let isDark = UITraitCollection.current.userInterfaceStyle == .dark
    let colorScheme: ColorScheme = isDark ? .dark : .light
    let resolved = MaxThemePalette.resolve(
      theme: theme,
      systemColorScheme: colorScheme,
      increasedContrast: false
    )
    return resolved.accent
  }
  static let textPrimary = MaxSemanticStyle(.primaryText)
  static let textSecondary = MaxSemanticStyle(.secondaryText)
  static let textTertiary = MaxSemanticStyle(.tertiaryText)
  static let canvas = MaxSemanticStyle(.canvas)
  static let atmosphericBackground = MaxSemanticStyle(.atmosphericBackground)
  static let canvasRaised = MaxSemanticStyle(.elevatedContentSurface)
  static let surface = MaxSemanticStyle(.primaryContentSurface)
  static let surfaceStrong = MaxSemanticStyle(.elevatedContentSurface)
  static let surfaceSoft = MaxSemanticStyle(.selectedControl)
  static let controlBase = MaxSemanticStyle(.selectedControl)
  static let controlBaseStrong = MaxSemanticStyle(.elevatedContentSurface)
  static var controlTint: Color {
    accent
  }
  static let selectedControl = MaxSemanticStyle(.selectedControl)
  static let line = MaxSemanticStyle(.separator, opacity: 0.72)
  static let lineStrong = MaxSemanticStyle(.separator)
  static let highlight = MaxSemanticStyle(.selectedControl)
  static let mint = MaxSemanticStyle(.success)
  static let warning = MaxSemanticStyle(.warning)
  static let danger = MaxSemanticStyle(.destructive)
  static let disabled = MaxSemanticStyle(.disabled)
  static let mediaOverlay = MaxSemanticStyle(.mediaOverlay)
  static let scrim = MaxSemanticStyle(.scrim)
}

/// Compact rendering of the Max app mark for places where the full app icon
/// would be visually too heavy (release experiences, badges, and headers).
/// It deliberately mirrors the yellow field and dark sparkle used by the app
/// icon, keeping product identity independent from an external image lookup.
struct MaxIdentityMark: View {
  let size: CGFloat

  var body: some View {
    Image(systemName: "sparkle")
      .font(.system(size: size * 0.58, weight: .black, design: .rounded))
      .foregroundStyle(Color.black)
      .frame(width: size, height: size)
      .background(Color(red: 1, green: 0.77, blue: 0.02), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
      .accessibilityHidden(true)
  }
}

enum MaxSpace {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let sm: CGFloat = 12
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 32
  static let xxl: CGFloat = 44
  /// Keeps the last scrollable content clear of iOS 26's floating tab bar.
  static let tabBarClearance: CGFloat = 104
}

enum MaxRadius {
  static let small: CGFloat = 12
  static let medium: CGFloat = 18
  static let large: CGFloat = 26
  static let pill: CGFloat = 999
}

enum MaxShadow {
  static let control = Color.black.opacity(0.12)
  static let surface = Color.clear
}

enum MaxTypography {
  static let eyebrow = Font.caption.weight(.semibold)
  static let screenTitle = Font.largeTitle.weight(.bold)
  static let sectionTitle = Font.headline
  static let body = Font.body
  static let caption = Font.caption
}

enum MaxMotion {
  static let quick = Animation.snappy(duration: 0.22)
  static let standard = Animation.smooth(duration: 0.34)

  /// Single gate for every animation in the app. Pass the value of
  /// `@Environment(\.maxMotionEnabled)`; the result is `nil` — i.e. instant —
  /// whenever the system Reduce Motion switch or the in-app calm-motion
  /// preference is on.
  static func animation(_ animation: Animation?, enabled: Bool) -> Animation? {
    enabled ? animation : nil
  }
}

private struct MaxMotionEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  /// False when either the system Reduce Motion switch or the in-app
  /// "Reduce Motion" preference is on. Injected once by `MaxThemeHost`.
  var maxMotionEnabled: Bool {
    get { self[MaxMotionEnabledKey.self] }
    set { self[MaxMotionEnabledKey.self] = newValue }
  }
}

private struct MaxGatedAnimationModifier<Value: Equatable>: ViewModifier {
  let animation: Animation?
  let value: Value

  @Environment(\.maxMotionEnabled) private var motionEnabled

  func body(content: Content) -> some View {
    content.animation(MaxMotion.animation(animation, enabled: motionEnabled), value: value)
  }
}

extension View {
  /// `.animation(_:value:)` routed through the shared motion gate, so the
  /// change is instant when motion is reduced.
  func maxAnimation<Value: Equatable>(
    _ animation: Animation? = MaxMotion.quick,
    value: Value
  ) -> some View {
    modifier(MaxGatedAnimationModifier(animation: animation, value: value))
  }
}

enum MaxControlSize {
  case compact
  case navigation
  case primary

  var visualSize: CGFloat {
    switch self {
    case .compact: 44
    case .navigation: 48
    case .primary: 56
    }
  }

  var iconSize: CGFloat {
    switch self {
    case .compact: 17
    case .navigation: 19
    case .primary: 22
    }
  }
}

enum MaxControlTone {
  case standard
  case selected
  case prominent
}

// MARK: - Atmospheric background

/// Reference-image color atmosphere. This is artwork, not a control material;
/// it may extend under safe areas while every foreground control remains native.
struct MaxLivingBackground: View {
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false
  @State private var clientID = UUID()
  @State private var isOnScreen = false
  @State private var didStartMotion = false

  private var showsAtmosphere: Bool {
    appTheme == .max || appTheme == .spectrum || appTheme == .clouds
      || appTheme == .council || appTheme == .daydream || appTheme == .solarInk
  }

  /// The atmosphere only moves while this instance is on screen, the scene is
  /// foregrounded, and no accessibility or in-app calm preference applies.
  private var isAnimating: Bool {
    showsAtmosphere
      && isOnScreen
      && scenePhase == .active
      && !(reduceMotion || calmBackground || reduceTransparency)
  }

  var body: some View {
    ZStack {
      Rectangle().fill(MaxColor.canvas)

      if showsAtmosphere {
        MaxAtmosphereLayer(
          palette: palette,
          colors: MaxAtmosphereMesh.colors(for: palette),
          showsClouds: appTheme == .clouds,
          isAnimating: isAnimating
        )
        .opacity(contrast == .increased ? 0.72 : 1)

        // A stable reading field keeps ordinary text predictable without
        // turning the whole screen into a card or imitating Liquid Glass.
        LinearGradient(
          colors: [
            palette.primaryContentSurface.opacity(reduceTransparency ? 0.82 : 0.50),
            palette.primaryContentSurface.opacity(reduceTransparency ? 0.72 : 0.34),
            palette.primaryContentSurface.opacity(reduceTransparency ? 0.78 : 0.44),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
    .onAppear { isOnScreen = true }
    .onDisappear {
      isOnScreen = false
      releaseMotionSources()
    }
    .onChange(of: isAnimating, initial: true) { _, animating in
      guard animating else {
        releaseMotionSources()
        return
      }
      MaxAtmosphereClock.shared.claim(clientID)
      // Only Clouds reads the motion sensor, and `start()` is reference
      // counted, so this instance must balance its own call exactly once.
      if appTheme == .clouds, !didStartMotion {
        didStartMotion = true
        GyroscopeObserver.shared.start()
      }
    }
  }

  private func releaseMotionSources() {
    MaxAtmosphereClock.shared.resign(clientID)
    if didStartMotion {
      didStartMotion = false
      GyroscopeObserver.shared.stop()
    }
  }
}

/// Isolates the shared-clock read so only the mesh re-renders on each tick.
/// The palette-derived color ramp is built by the parent and passed in, instead
/// of being rebuilt nine colors at a time twelve times a second.
private struct MaxAtmosphereLayer: View {
  let palette: MaxThemePalette
  let colors: [Color]
  let showsClouds: Bool
  let isAnimating: Bool

  var body: some View {
    // The ternary short-circuits, so an idle layer never observes the clock
    // and is never invalidated by it.
    let phase: TimeInterval = isAnimating ? MaxAtmosphereClock.shared.phase : 0
    ZStack {
      MaxAtmosphereMesh(palette: palette, colors: colors, phase: phase)
      if showsClouds {
        CloudVolumeOverlay(palette: palette, phase: phase, parallaxEnabled: isAnimating)
      }
    }
  }
}

private struct MaxAtmosphereMesh: View {
  let palette: MaxThemePalette
  let colors: [Color]
  let phase: TimeInterval

  var body: some View {
    MeshGradient(
      width: 3,
      height: 3,
      points: points,
      colors: colors,
      background: palette.canvas,
      smoothsColors: true
    )
  }

  private var points: [SIMD2<Float>] {
    let slow = Float(sin(phase / 13)) * 0.045
    let slower = Float(cos(phase / 17)) * 0.038
    return [
      .init(0, 0), .init(0.50 + slower, 0), .init(1, 0),
      .init(0, 0.46 + slow), .init(0.50 + slow, 0.52 + slower), .init(1, 0.48 - slow),
      .init(0, 1), .init(0.50 - slower, 1), .init(1, 1),
    ]
  }

  /// Palette-derived color ramp. Hoisted out of the animated body: it never
  /// reads `phase`, so rebuilding it on every frame was pure waste.
  static func colors(for palette: MaxThemePalette) -> [Color] {
    if palette.selectedTheme == .daydream {
      let coral = Color(red: 0.85, green: 0.42, blue: 0.37)
      let mint  = Color(red: 0.38, green: 0.71, blue: 0.62)
      let warm  = Color(red: 0.91, green: 0.78, blue: 0.43)
      let lav   = Color(red: 0.70, green: 0.60, blue: 0.82)
      if palette.isDark {
        return [
          coral.opacity(0.22),
          palette.canvas,
          mint.opacity(0.18),
          palette.primaryContentSurface,
          coral.opacity(0.12),
          mint.opacity(0.20),
          lav.opacity(0.15),
          palette.elevatedContentSurface,
          warm.opacity(0.14),
        ]
      } else {
        return [
          coral.opacity(0.18),
          palette.atmosphericBackground,
          mint.opacity(0.16),
          palette.primaryContentSurface,
          coral.opacity(0.10),
          mint.opacity(0.16),
          warm.opacity(0.14),
          palette.elevatedContentSurface,
          lav.opacity(0.14),
        ]
      }
    }

    if palette.selectedTheme == .council {
      return [
        Color(red: 0.020, green: 0.020, blue: 0.022),
        Color(red: 0.045, green: 0.025, blue: 0.035),
        Color(red: 0.030, green: 0.018, blue: 0.022),
        Color(red: 0.025, green: 0.022, blue: 0.030),
        Color(red: 0.055, green: 0.035, blue: 0.042),
        Color(red: 0.038, green: 0.018, blue: 0.025),
        Color(red: 0.015, green: 0.015, blue: 0.018),
        Color(red: 0.030, green: 0.028, blue: 0.030),
        Color(red: 0.065, green: 0.025, blue: 0.030),
      ]
    }

    if palette.selectedTheme == .clouds {
      return [
        Color(red: 0.78, green: 0.92, blue: 1.00),
        Color(red: 0.94, green: 0.91, blue: 1.00),
        Color(red: 1.00, green: 0.91, blue: 0.96),
        Color(red: 0.87, green: 0.96, blue: 1.00),
        palette.primaryContentSurface,
        Color(red: 0.89, green: 0.87, blue: 1.00),
        Color(red: 0.96, green: 0.98, blue: 1.00),
        palette.elevatedContentSurface,
        Color(red: 1.00, green: 0.94, blue: 0.97),
      ]
    }

    if palette.selectedTheme == .spectrum {
      let red = Color(red: 0.98, green: 0.40, blue: 0.40)
      let orange = Color(red: 0.98, green: 0.60, blue: 0.35)
      let yellow = Color(red: 0.96, green: 0.82, blue: 0.30)
      let green = Color(red: 0.40, green: 0.85, blue: 0.55)
      let blue = Color(red: 0.35, green: 0.70, blue: 0.96)
      let indigo = Color(red: 0.55, green: 0.50, blue: 0.94)
      let violet = Color(red: 0.80, green: 0.50, blue: 0.90)

      if palette.isDark {
        return [
          red.opacity(0.35),
          orange.opacity(0.35),
          yellow.opacity(0.30),
          green.opacity(0.35),
          palette.primaryContentSurface,
          blue.opacity(0.35),
          indigo.opacity(0.35),
          palette.canvas,
          violet.opacity(0.35)
        ]
      } else {
        return [
          red.opacity(0.24),
          orange.opacity(0.24),
          yellow.opacity(0.22),
          green.opacity(0.24),
          palette.primaryContentSurface,
          blue.opacity(0.24),
          indigo.opacity(0.24),
          palette.elevatedContentSurface,
          violet.opacity(0.24)
        ]
      }
    }

    if palette.isDark {
      return [
        MaxColor.deepNavy,
        MaxColor.midnight,
        MaxColor.violet.opacity(0.82),
        MaxColor.sky.opacity(0.46),
        palette.primaryContentSurface,
        MaxColor.periwinkle.opacity(0.66),
        MaxColor.midnight,
        palette.canvas,
        MaxColor.coral.opacity(0.52),
      ]
    }

    return [
      MaxColor.sky,
      MaxColor.periwinkle,
      MaxColor.lavender,
      MaxColor.sky.opacity(0.74),
      palette.primaryContentSurface,
      MaxColor.rose.opacity(0.78),
      MaxColor.periwinkle.opacity(0.70),
      palette.elevatedContentSurface,
      MaxColor.amber.opacity(0.66),
    ]
  }
}

/// Slow, low-amplitude motion gives Clouds a living parallax feel without
/// depending on motion-sensor permission or making the reading plane unstable.
private struct CloudVolumeOverlay: View {
  let palette: MaxThemePalette
  let phase: TimeInterval
  let parallaxEnabled: Bool

  var body: some View {
    // Short-circuits so the motion sensor is never observed while parallax is
    // suppressed (Reduce Motion, calm background, off-screen, backgrounded).
    let gyroOffset: CGSize = parallaxEnabled ? GyroscopeObserver.shared.offset : .zero
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = proxy.size.height
      ZStack {
        cloud(width: width * 0.78, height: height * 0.23)
          .offset(
            x: -width * 0.24 + CGFloat(sin(phase / 15)) * 16 + gyroOffset.width * 1.5,
            y: -height * 0.30 + CGFloat(cos(phase / 19)) * 12 + gyroOffset.height * 1.5
          )
        cloud(width: width * 0.92, height: height * 0.26)
          .offset(
            x: width * 0.30 + CGFloat(cos(phase / 18)) * 14 + gyroOffset.width * 1.0,
            y: height * 0.06 + CGFloat(sin(phase / 21)) * 18 + gyroOffset.height * 1.0
          )
        cloud(width: width * 0.70, height: height * 0.20)
          .offset(
            x: -width * 0.18 + CGFloat(sin(phase / 23)) * 12 + gyroOffset.width * 0.5,
            y: height * 0.36 + CGFloat(cos(phase / 17)) * 14 + gyroOffset.height * 0.5
          )
      }
      .frame(width: width, height: height)
    }
    .blendMode(.screen)
    .allowsHitTesting(false)
  }

  private func cloud(width: CGFloat, height: CGFloat) -> some View {
    Ellipse()
      .fill(
        RadialGradient(
          colors: [
            Color.white.opacity(0.72),
            palette.elevatedContentSurface.opacity(0.34),
            palette.accent.opacity(0.04),
            .clear,
          ],
          center: .center,
          startRadius: 8,
          endRadius: max(width, height) * 0.48
        )
      )
      .frame(width: width, height: height)
      .blur(radius: 18)
  }
}

struct MaxScreen<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack(alignment: .top) {
      MaxLivingBackground()
        .ignoresSafeArea()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ignoresSafeArea()
  }
}

private struct MaxTabContentModifier: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    let clearance = dynamicTypeSize.isAccessibilitySize ? MaxSpace.tabBarClearance * 1.8 : MaxSpace.tabBarClearance
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .contentMargins(.bottom, clearance, for: .scrollContent)
      .background {
        MaxLivingBackground()
          .ignoresSafeArea()
      }
  }
}

private struct MaxScreenBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background {
        MaxLivingBackground()
          .ignoresSafeArea()
      }
  }
}

extension View {
  /// Applies the shared atmosphere and enough scroll clearance for the native
  /// floating tab bar. Use only for views presented inside the root TabView.
  func maxTabContent() -> some View {
    modifier(MaxTabContentModifier())
  }

  /// Applies the selected theme's full-viewport atmosphere to pushed screens
  /// and presentations that don't need root-tab clearance.
  func maxScreenBackground() -> some View {
    modifier(MaxScreenBackgroundModifier())
  }
}

// MARK: - Plain content layer

struct MaxContentSurface<Content: View>: View {
  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette

  let padding: CGFloat
  let content: Content

  init(padding: CGFloat = MaxSpace.md, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background {
        if appTheme == .clouds {
          CloudGlassBackground(
            palette: palette,
            cornerRadius: MaxRadius.medium
          )
        } else if appTheme == .council {
          RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            .fill(CouncilColor.stoneSurface)
            .overlay {
              RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
                .stroke(CouncilColor.quietBorder, lineWidth: 1)
            }
        } else {
          RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            .fill(MaxColor.surface)
        }
      }
  }
}

/// Clouds-only volumetric surface. Native Liquid Glass is isolated here so all
/// other themes keep their established opaque content hierarchy.
private struct CloudGlassBackground: View {
  let palette: MaxThemePalette
  let cornerRadius: CGFloat

  var body: some View {
    MaxLiquidGlassCard(cornerRadius: cornerRadius) {
      Color.clear
    }
  }
}

// MARK: - Premium Liquid Glass Card and Modifiers

/// A premium liquid glass card component with shifting specular reflections,
/// multi-layered borders, and gyroscopic depth effects.
struct MaxLiquidGlassCard<Content: View>: View {
  let cornerRadius: CGFloat
  let content: Content

  @Environment(\.maxThemePalette) private var palette
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false

  init(cornerRadius: CGFloat = MaxRadius.medium, @ViewBuilder content: () -> Content) {
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let gyroOffset = reduceMotion || calmBackground ? .zero : GyroscopeObserver.shared.offset

    content
      .background {
        if let visual = PluginStore.shared.activeVisualPlugin as? any MaxVisualPlugin {
          visual.decorateCardBackground(
            palette: palette,
            cornerRadius: cornerRadius,
            gyroOffset: gyroOffset,
            reduceTransparency: reduceTransparency
          )
        } else {
          StandardLiquidGlassCardBackground(
            shape: shape,
            palette: palette,
            gyroOffset: gyroOffset,
            reduceTransparency: reduceTransparency
          )
        }
      }
  }
}

/// Core implementation of standard Liquid Glass background styling.
struct StandardLiquidGlassCardBackground: View {
  let shape: RoundedRectangle
  let palette: MaxThemePalette
  let gyroOffset: CGSize
  let reduceTransparency: Bool

  init(shape: RoundedRectangle, palette: MaxThemePalette, gyroOffset: CGSize, reduceTransparency: Bool) {
    self.shape = shape
    self.palette = palette
    self.gyroOffset = gyroOffset
    self.reduceTransparency = reduceTransparency
  }

  var body: some View {
    ZStack {
      if reduceTransparency {
        shape.fill(palette.primaryContentSurface.opacity(0.96))
      } else if #available(iOS 26.0, *) {
        Color.clear
          .glassEffect(
            .regular.tint(Color.white.opacity(0.18)),
            in: shape
          )
      } else {
        shape.fill(palette.primaryContentSurface.opacity(0.92))
      }

      shape
        .fill(
          LinearGradient(
            colors: [
              Color.white.opacity(0.32),
              palette.primaryContentSurface.opacity(0.20),
              palette.selectedControl.opacity(0.08),
            ],
            startPoint: UnitPoint(
              x: 0.1 + Double(gyroOffset.width / 150.0),
              y: 0.1 + Double(gyroOffset.height / 150.0)
            ),
            endPoint: UnitPoint(
              x: 0.9 + Double(gyroOffset.width / 150.0),
              y: 0.9 + Double(gyroOffset.height / 150.0)
            )
          )
        )

      shape.stroke(
        LinearGradient(
          colors: [
            Color.white.opacity(0.96),
            palette.accent.opacity(0.34),
            Color.white.opacity(0.24)
          ],
          startPoint: UnitPoint(
            x: 0.0 - Double(gyroOffset.width / 100.0),
            y: 0.0 - Double(gyroOffset.height / 100.0)
          ),
          endPoint: UnitPoint(
            x: 1.0 - Double(gyroOffset.width / 100.0),
            y: 1.0 - Double(gyroOffset.height / 100.0)
          )
        ),
        lineWidth: 1.2
      )

      shape
        .stroke(palette.accent.opacity(0.14), lineWidth: 6)
        .offset(x: -gyroOffset.width * 0.25, y: -gyroOffset.height * 0.25)
        .blur(radius: 4)
        .clipShape(shape)
    }
    .background {
      shape
        .fill(palette.accent.opacity(0.16))
        .blur(radius: 16)
        .padding(6)
        .offset(x: gyroOffset.width * 0.35, y: gyroOffset.height * 0.35)
    }
    .shadow(color: Color.white.opacity(0.56), radius: 6, x: -2, y: -2)
    .shadow(
      color: palette.accent.opacity(0.14),
      radius: 18,
      x: gyroOffset.width * 0.4,
      y: 10 + gyroOffset.height * 0.4
    )
  }
}

/// General-purpose gyroscopic parallax modifier.
struct MaxGyroParallaxModifier: ViewModifier {
  let amount: CGFloat
  
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false

  func body(content: Content) -> some View {
    let offset = reduceMotion || calmBackground ? .zero : GyroscopeObserver.shared.offset
    content
      .offset(x: offset.width * amount, y: offset.height * amount)
  }
}

/// General-purpose inner shadow modifier.
struct MaxInnerShadowModifier<S: Shape>: ViewModifier {
  let shape: S
  let color: Color
  let radius: CGFloat
  let offset: CGSize

  func body(content: Content) -> some View {
    content
      .overlay {
        shape
          .stroke(color, lineWidth: radius * 2)
          .offset(offset)
          .blur(radius: radius)
          .clipShape(shape)
      }
  }
}

extension View {
  func maxGyroParallax(amount: CGFloat = 1.0) -> some View {
    modifier(MaxGyroParallaxModifier(amount: amount))
  }

  func maxInnerShadow<S: Shape>(
    _ shape: S,
    color: Color = .black.opacity(0.2),
    radius: CGFloat = 4,
    offset: CGSize = .zero
  ) -> some View {
    modifier(MaxInnerShadowModifier(shape: shape, color: color, radius: radius, offset: offset))
  }
}

/// Compatibility name used by older feature views. It is deliberately a plain,
/// opaque content surface; Liquid Glass never belongs on ordinary content cards.
struct MaxSurfaceCard<Content: View>: View {
  let padding: CGFloat
  let content: Content

  init(
    prominence: Double = 1,
    padding: CGFloat = MaxSpace.md,
    @ViewBuilder content: () -> Content
  ) {
    _ = prominence
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    MaxContentSurface(padding: padding) { content }
  }
}

// MARK: - Native Liquid Glass control layer

/// Native iOS 26 Liquid Glass for the few custom controls that cannot be a
/// standard Button, toolbar item, tab, menu, or sheet.
struct MaxControlMaterial<ShapeType: Shape>: View {
  let shape: ShapeType
  let tone: MaxControlTone
  let interactive: Bool

  init(
    _ shape: ShapeType,
    tone: MaxControlTone = .standard,
    interactive: Bool = false
  ) {
    self.shape = shape
    self.tone = tone
    self.interactive = interactive
  }

  var body: some View {
    Color.clear
      .glassEffect(glass, in: shape)
  }

  private var glass: Glass {
    let base: Glass
    switch tone {
    case .standard:
      base = .regular
    case .selected:
      base = .regular.tint(MaxColor.periwinkle.opacity(0.45))
    case .prominent:
      base = .regular.tint(MaxColor.accent)
    }
    return interactive ? base.interactive() : base
  }
}

struct MaxFloatingSurface<Content: View>: View {
  let horizontalPadding: CGFloat
  let verticalPadding: CGFloat
  let content: Content

  init(
    horizontalPadding: CGFloat = MaxSpace.md,
    verticalPadding: CGFloat = MaxSpace.sm,
    @ViewBuilder content: () -> Content
  ) {
    self.horizontalPadding = horizontalPadding
    self.verticalPadding = verticalPadding
    self.content = content()
  }

  var body: some View {
    content
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .glassEffect(.regular, in: .capsule)
  }
}

struct MaxControlCluster<Content: View>: View {
  let padding: CGFloat
  let content: Content

  init(padding: CGFloat = MaxSpace.sm, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .glassEffect(
        .regular,
        in: .rect(cornerRadius: MaxRadius.large)
      )
  }
}

// MARK: - Type and actions

struct MaxTitleBlock: View {
  let eyebrow: LocalizedStringKey
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      Text(eyebrow)
        .font(MaxTypography.eyebrow)
        .foregroundStyle(MaxColor.accent)
        .textCase(.uppercase)
      Text(title)
        .font(MaxTypography.screenTitle)
        .foregroundStyle(MaxColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle)
        .font(MaxTypography.body)
        .foregroundStyle(MaxColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Retained for feature compatibility; implemented with Apple's native glass.
struct MaxPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 52)
      .padding(.horizontal, MaxSpace.md)
      .glassEffect(
        .regular.tint(MaxColor.accent).interactive(),
        in: .rect(cornerRadius: MaxRadius.medium)
      )
      .opacity(configuration.isPressed ? 0.82 : 1)
  }
}

struct MaxSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 50)
      .padding(.horizontal, MaxSpace.md)
      .glassEffect(
        .regular.interactive(),
        in: .rect(cornerRadius: MaxRadius.medium)
      )
      .opacity(configuration.isPressed ? 0.82 : 1)
  }
}

/// Keeps disabled toolbar actions legible while preserving the native disabled
/// accessibility trait. UIKit's default disabled tint can fall below contrast
/// thresholds when it sits over bright Liquid Glass.
struct MaxToolbarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    MaxToolbarButtonStyleBody(configuration: configuration)
  }
}

private struct MaxToolbarButtonStyleBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    configuration.label
      .foregroundStyle(isEnabled ? palette.accent : palette.secondaryText)
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

struct MaxChip: View {
  let title: LocalizedStringKey
  let isSelected: Bool
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Text(title)
      .font(MaxTypography.caption.weight(.semibold))
      .foregroundStyle(isSelected ? palette.accentForeground : palette.primaryText)
      .padding(.horizontal, MaxSpace.sm)
      .padding(.vertical, MaxSpace.xs)
      .background(
        isSelected ? palette.accent : palette.selectedControl,
        in: Capsule(style: .continuous)
      )
  }
}

struct MaxSectionHeader: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey?
  let actionTitle: LocalizedStringKey?
  let action: (() -> Void)?

  init(
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil,
    actionTitle: LocalizedStringKey? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.actionTitle = actionTitle
    self.action = action
  }

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: MaxSpace.md) {
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(title)
          .font(MaxTypography.sectionTitle)
          .foregroundStyle(MaxColor.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(MaxTypography.caption)
            .foregroundStyle(MaxColor.textSecondary)
        }
      }
      Spacer(minLength: MaxSpace.sm)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .font(.subheadline.weight(.semibold))
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
    }
  }
}

