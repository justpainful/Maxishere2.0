import SwiftUI

// MARK: - Council Design System (CDS)
// Philosophy: Power Through Restraint
// Design DNA: Council Cut, Ember Line, Obsidian Layers, Directional Light
// Behavioral Constraint: Silence Budget

// MARK: - Temperature

enum CouncilTemperature {
  case frozen    // inactive, disabled, unavailable
  case cool      // Vault/Chats default
  case neutral   // ordinary interface
  case warm      // selected, important
  case ember     // active transfer, direct interaction
  case critical  // destructive, failed, dangerous
  case resolved  // temporary success (returns to neutral)
}

extension CouncilTemperature {
  var color: Color {
    switch self {
    case .frozen:   Color(red: 0.35, green: 0.33, blue: 0.35)
    case .cool:     Color(red: 0.76, green: 0.75, blue: 0.76)
    case .neutral:  Color(red: 0.95, green: 0.94, blue: 0.93)
    case .warm:     Color(red: 0.84, green: 0.55, blue: 0.40)
    case .ember:    Color(red: 0.91, green: 0.28, blue: 0.18)
    case .critical: Color(red: 1.00, green: 0.42, blue: 0.42)
    case .resolved: Color(red: 0.70, green: 0.78, blue: 0.72)
    }
  }

  var glowOpacity: Double {
    switch self {
    case .frozen:   0.0
    case .cool:     0.10
    case .neutral:  0.0
    case .warm:     0.28
    case .ember:    0.55
    case .critical: 0.70
    case .resolved: 0.40
    }
  }

  var hasEmberLine: Bool {
    switch self {
    case .frozen, .neutral, .cool: false
    default: true
    }
  }
}

// MARK: - Semantic Color Roles

struct CouncilColor {
  static let voidBackground         = Color(red: 0.020, green: 0.020, blue: 0.024)
  static let raisedBackground       = Color(red: 0.043, green: 0.039, blue: 0.051)
  static let stoneSurface           = Color(red: 0.071, green: 0.063, blue: 0.078)
  static let stoneSurfaceElevated   = Color(red: 0.100, green: 0.090, blue: 0.110)
  static let obsidianSurface        = Color(red: 0.055, green: 0.047, blue: 0.063)
  static let obsidianSurfaceSelected = Color(red: 0.165, green: 0.094, blue: 0.125)
  static let glassTint              = Color(red: 0.76, green: 0.12, blue: 0.18).opacity(0.18)
  static let glassHighlight         = Color.white.opacity(0.08)
  static let primaryText            = Color(red: 0.953, green: 0.941, blue: 0.933)
  static let secondaryText          = Color(red: 0.596, green: 0.576, blue: 0.596)
  static let tertiaryText           = Color(red: 0.420, green: 0.408, blue: 0.420)
  static let coldSilver             = Color(red: 0.796, green: 0.784, blue: 0.780)
  static let warmSilver             = Color(red: 0.855, green: 0.831, blue: 0.812)
  static let quietBorder            = Color(red: 0.165, green: 0.141, blue: 0.161)
  static let royalCrimson           = Color(red: 0.561, green: 0.063, blue: 0.106)
  static let activeCrimson          = Color(red: 0.761, green: 0.122, blue: 0.180)
  static let ember                  = Color(red: 0.910, green: 0.282, blue: 0.176)
  static let critical               = Color(red: 1.00, green: 0.42, blue: 0.42)
  static let resolved               = Color(red: 0.55, green: 0.67, blue: 0.55)
  static let disabled               = Color(red: 0.29, green: 0.28, blue: 0.29)
  static let selection              = Color(red: 0.76, green: 0.12, blue: 0.18).opacity(0.20)
  static let unread                 = Color(red: 0.91, green: 0.28, blue: 0.18)
}

// MARK: - Spacing

struct CouncilSpacing {
  enum Mode {
    case tight       // Chats
    case standard    // Vault, Settings
    case open        // Home, Shared, Profile
    case ceremonial  // Memories, Double Lock
  }

  static func vertical(_ mode: Mode) -> CGFloat {
    switch mode {
    case .tight:      10
    case .standard:   16
    case .open:       24
    case .ceremonial: 44
    }
  }

  static func horizontal(_ mode: Mode) -> CGFloat {
    switch mode {
    case .tight:      12
    case .standard:   16
    case .open:       20
    case .ceremonial: 32
    }
  }
}

// MARK: - Typography

struct CouncilTypography {
  static let display  = Font.system(.largeTitle, design: .serif, weight: .bold)
  static let title    = Font.system(.title2, design: .default, weight: .semibold)
  static let headline = Font.system(.headline, design: .default, weight: .semibold)
  static let body     = Font.system(.body, design: .default, weight: .regular)
  static let caption  = Font.system(.caption, design: .default, weight: .regular)
  static let eyebrow  = Font.system(.caption, design: .default, weight: .semibold)
  static let mono     = Font.system(.caption, design: .monospaced, weight: .medium)
}

// MARK: - Motion

struct CouncilMotion {
  static let instant   = Animation.easeOut(duration: 0.13)
  static let normal    = Animation.smooth(duration: 0.24)
  static let royal     = Animation.smooth(duration: 0.42)
  static let cinematic = Animation.easeInOut(duration: 0.85)
}

// MARK: - Depth Hierarchy

enum CouncilDepth: Int {
  case void     = 0
  case stone    = 1
  case obsidian = 2
  case glass    = 3
  case ceremony = 4
}

extension CouncilDepth {
  var surface: Color {
    switch self {
    case .void:     CouncilColor.voidBackground
    case .stone:    CouncilColor.stoneSurface
    case .obsidian: CouncilColor.obsidianSurface
    case .glass:    CouncilColor.glassTint
    case .ceremony: Color.clear
    }
  }
}

// MARK: - Directional Light

struct CouncilLightEnvironment {
  var direction: UnitPoint
  var temperature: CouncilTemperature
  var reach: Double
  var response: Double
  var intensity: Double

  static let home     = CouncilLightEnvironment(
    direction: .topLeading, temperature: .warm, reach: 0.75, response: 0.40, intensity: 0.22
  )
  static let vault    = CouncilLightEnvironment(
    direction: .top, temperature: .cool, reach: 0.45, response: 0.60, intensity: 0.16
  )
  static let shared   = CouncilLightEnvironment(
    direction: .leading, temperature: .neutral, reach: 0.55, response: 0.70, intensity: 0.14
  )
  static let chats    = CouncilLightEnvironment(
    direction: .top, temperature: .cool, reach: 0.35, response: 0.85, intensity: 0.10
  )
  static let memories = CouncilLightEnvironment(
    direction: .trailing, temperature: .warm, reach: 0.90, response: 0.30, intensity: 0.30
  )
  static let profile  = CouncilLightEnvironment(
    direction: .topLeading, temperature: .neutral, reach: 0.60, response: 0.50, intensity: 0.18
  )

  func gradient() -> LinearGradient {
    let highlight = Color.white.opacity(intensity)
    let shadow    = Color.black.opacity(intensity * 0.5)
    return LinearGradient(
      colors: [highlight, Color.clear, shadow],
      startPoint: direction,
      endPoint: opposite
    )
  }

  private var opposite: UnitPoint {
    switch direction {
    case .top:         return .bottom
    case .topLeading:  return .bottomTrailing
    case .topTrailing: return .bottomLeading
    case .leading:     return .trailing
    case .trailing:    return .leading
    default:           return .bottom
    }
  }
}

private struct CouncilLightEnvironmentKey: EnvironmentKey {
  static let defaultValue = CouncilLightEnvironment.vault
}

extension EnvironmentValues {
  var councilLight: CouncilLightEnvironment {
    get { self[CouncilLightEnvironmentKey.self] }
    set { self[CouncilLightEnvironmentKey.self] = newValue }
  }
}

// MARK: - Council Cut Shape

struct CouncilCutShape: Shape {
  var cornerRadius: CGFloat
  var cutDepth: CGFloat
  var isRTL: Bool

  init(cornerRadius: CGFloat = 18, cutDepth: CGFloat = 20, isRTL: Bool = false) {
    self.cornerRadius = cornerRadius
    self.cutDepth = cutDepth
    self.isRTL = isRTL
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r   = min(cornerRadius, rect.width / 2, rect.height / 2)
    let cut = min(cutDepth, rect.width / 3, rect.height / 3)

    if isRTL {
      // Cut at top-trailing, soft at bottom-leading
      path.move(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
      path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                  radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - cut * 0.5))
      path.addQuadCurve(to: CGPoint(x: rect.minX + cut * 0.5, y: rect.maxY),
                        control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
      path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                  radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
      path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
    } else {
      // Cut at top-leading, soft at bottom-trailing
      path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
      path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                  radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r - cut * 0.5))
      path.addQuadCurve(to: CGPoint(x: rect.maxX - cut * 0.5, y: rect.maxY),
                        control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
      path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                  radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
      path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.minY))
    }
    path.closeSubpath()
    return path
  }
}

// MARK: - Ember Line

enum EmberLineBehavior {
  case `static`
  case selection
  case unread
  case progress(Double)
  case focus
  case pulseOnce
  case successOnce
  case failure
  case connection
}

struct CouncilEmberLine: View {
  let behavior: EmberLineBehavior
  let edge: Edge
  var temperature: CouncilTemperature = .warm

  @State private var pulseOpacity: Double = 1.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled

  var body: some View {
    GeometryReader { geo in
      let isHorizontal = edge == .top || edge == .bottom
      let total = isHorizontal ? geo.size.width : geo.size.height
      ZStack {
        RoundedRectangle(cornerRadius: 0.75)
          .fill(lineGradient)
          .frame(
            width:  isHorizontal ? filledLength(total: total) : 1.5,
            height: isHorizontal ? 1.5 : filledLength(total: total)
          )
          .opacity(lineOpacity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment)
    }
    .onAppear(perform: handleAppear)
    .accessibilityHidden(true)
  }

  private var edgeAlignment: Alignment {
    switch edge {
    case .top:      .top
    case .bottom:   .bottom
    case .leading:  .leading
    case .trailing: .trailing
    }
  }

  private func filledLength(total: CGFloat) -> CGFloat {
    if case .progress(let p) = behavior { return total * CGFloat(max(0, min(1, p))) }
    return total
  }

  private var lineGradient: LinearGradient {
    let base = temperature.color
    switch behavior {
    case .failure:
      return LinearGradient(
        colors: [CouncilColor.critical, CouncilColor.critical.opacity(0.4)],
        startPoint: .leading, endPoint: .trailing
      )
    case .successOnce:
      return LinearGradient(
        colors: [CouncilColor.coldSilver, CouncilColor.warmSilver],
        startPoint: .leading, endPoint: .trailing
      )
    case .progress:
      return LinearGradient(
        colors: [base, CouncilColor.ember, base.opacity(0.6)],
        startPoint: .leading, endPoint: .trailing
      )
    default:
      return LinearGradient(
        colors: [base.opacity(0.3), base, base.opacity(0.3)],
        startPoint: .leading, endPoint: .trailing
      )
    }
  }

  private var lineOpacity: Double {
    switch behavior {
    case .pulseOnce, .successOnce: return pulseOpacity
    default: return temperature.glowOpacity > 0 ? 1.0 : 0.0
    }
  }

  private func handleAppear() {
    switch behavior {
    case .pulseOnce, .successOnce:
      guard !reduceMotion, motionEnabled else {
        pulseOpacity = 0
        return
      }
      // The reset and the fade must land in different render passes. SwiftUI
      // interpolates from the last *rendered* value, so writing 1 then 0 in a
      // single tick makes every appearance after the first a silent 0 -> 0.
      var reset = Transaction()
      reset.disablesAnimations = true
      withTransaction(reset) { pulseOpacity = 1.0 }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(CouncilMotion.royal.delay(0.1)) { pulseOpacity = 0 }
      }
    default: break
    }
  }
}

// MARK: - Council Surface

struct CouncilSurface<Content: View>: View {
  let depth: CouncilDepth
  let cornerRadius: CGFloat
  let useCut: Bool
  let content: Content

  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.layoutDirection) private var layoutDirection

  init(
    depth: CouncilDepth = .stone,
    cornerRadius: CGFloat = 16,
    useCut: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.depth = depth
    self.cornerRadius = cornerRadius
    self.useCut = useCut
    self.content = content()
  }

  var body: some View {
    content.background { background }
  }

  @ViewBuilder
  private var background: some View {
    if appTheme == .council {
      if useCut {
        CouncilCutShape(cornerRadius: cornerRadius, cutDepth: 20, isRTL: layoutDirection == .rightToLeft)
          .fill(depth.surface)
      } else {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(depth.surface)
      }
    } else {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(palette.primaryContentSurface)
    }
  }
}

// MARK: - Council Atmospheric Background

struct CouncilAtmosphericBackground: View {
  @Environment(\.councilLight) private var light
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    ZStack {
      CouncilColor.voidBackground.ignoresSafeArea()
      if !reduceTransparency {
        LinearGradient(
          colors: [
            light.temperature.color.opacity(0.04 * light.intensity),
            Color.clear,
            Color.black.opacity(0.20)
          ],
          startPoint: light.direction,
          endPoint: opposite(of: light.direction)
        )
        .ignoresSafeArea()
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func opposite(of point: UnitPoint) -> UnitPoint {
    switch point {
    case .top:         return .bottom
    case .topLeading:  return .bottomTrailing
    case .topTrailing: return .bottomLeading
    case .leading:     return .trailing
    case .trailing:    return .leading
    default:           return .bottom
    }
  }
}

// MARK: - Council Button Style

struct CouncilButtonStyle: ButtonStyle {
  let temperature: CouncilTemperature

  init(temperature: CouncilTemperature = .neutral) {
    self.temperature = temperature
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(labelColor)
      .frame(maxWidth: .infinity, minHeight: 52)
      .padding(.horizontal, 16)
      .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.80 : 1)
      .animation(CouncilMotion.instant, value: configuration.isPressed)
  }

  private var labelColor: Color {
    switch temperature {
    case .critical: CouncilColor.critical
    case .resolved: CouncilColor.resolved
    default:        CouncilColor.primaryText
    }
  }

  private var bg: LinearGradient {
    switch temperature {
    case .ember:
      return LinearGradient(
        colors: [CouncilColor.royalCrimson, CouncilColor.activeCrimson],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
    default:
      return LinearGradient(
        colors: [CouncilColor.stoneSurface, CouncilColor.obsidianSurface],
        startPoint: .top, endPoint: .bottom
      )
    }
  }

  private var borderColor: Color {
    switch temperature {
    case .ember:    CouncilColor.activeCrimson.opacity(0.60)
    case .critical: CouncilColor.critical.opacity(0.40)
    case .warm:     CouncilColor.warmSilver.opacity(0.20)
    default:        CouncilColor.quietBorder
    }
  }
}

// MARK: - Council Empty State

struct CouncilEmptyState: View {
  let symbol: String
  let titleKey: LocalizedStringKey
  let subtitleKey: LocalizedStringKey?
  let actionKey: LocalizedStringKey?
  let action: (() -> Void)?

  @Environment(\.appTheme) private var appTheme
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.layoutDirection) private var layoutDirection

  init(
    symbol: String,
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil,
    actionTitle: LocalizedStringKey? = nil,
    action: (() -> Void)? = nil
  ) {
    self.symbol = symbol
    self.titleKey = title
    self.subtitleKey = subtitle
    self.actionKey = actionTitle
    self.action = action
  }

  var body: some View {
    let isCouncil = appTheme == .council
    VStack(spacing: isCouncil ? 28 : 16) {
      ZStack {
        if isCouncil {
          CouncilCutShape(
            cornerRadius: 24,
            cutDepth: 28,
            isRTL: layoutDirection == .rightToLeft
          )
          .fill(
            LinearGradient(
              colors: [CouncilColor.obsidianSurface, CouncilColor.stoneSurface],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
          .frame(width: 88, height: 88)
          .overlay {
            CouncilCutShape(cornerRadius: 24, cutDepth: 28, isRTL: layoutDirection == .rightToLeft)
              .stroke(CouncilColor.quietBorder, lineWidth: 1)
          }
        }
        Image(systemName: symbol)
          .font(.system(size: 32, weight: .light))
          .foregroundStyle(isCouncil ? CouncilColor.tertiaryText : palette.tertiaryText)
      }
      VStack(spacing: 8) {
        Text(titleKey)
          .font(isCouncil ? CouncilTypography.headline : .headline)
          .foregroundStyle(isCouncil ? CouncilColor.secondaryText : palette.primaryText)
          .multilineTextAlignment(.center)
        if let subtitleKey {
          Text(subtitleKey)
            .font(.subheadline)
            .foregroundStyle(isCouncil ? CouncilColor.tertiaryText : palette.secondaryText)
            .multilineTextAlignment(.center)
        }
      }
      if let actionKey, let action {
        if isCouncil {
          Button(action: action) { Text(actionKey) }
            .buttonStyle(CouncilButtonStyle(temperature: .warm))
            .padding(.horizontal, 32)
        } else {
          Button(action: action) { Text(actionKey) }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
        }
      }
    }
    .padding(isCouncil ? 44 : 24)
  }
}

// MARK: - Council Loading Shimmer

struct CouncilLoadingShimmer: View {
  let width: CGFloat?
  let height: CGFloat
  let cornerRadius: CGFloat

  @State private var phase: CGFloat = -1
  @Environment(\.appTheme) private var appTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled

  init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 8) {
    self.width = width
    self.height = height
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    let base = appTheme == .council ? CouncilColor.stoneSurface : Color.gray.opacity(0.2)
    let shim = appTheme == .council ? CouncilColor.stoneSurfaceElevated : Color.gray.opacity(0.35)
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(
        LinearGradient(
          colors: [base, shim, base],
          startPoint: UnitPoint(x: phase, y: 0),
          endPoint: UnitPoint(x: phase + 1, y: 0)
        )
      )
      .frame(width: width, height: height)
      .onAppear {
        guard !reduceMotion, motionEnabled else { return }
        // `phase` only ever moved -1 -> 1, so a second appearance saw no state
        // delta and the shimmer froze at its end position. Rewinding on
        // disappear also cancels the otherwise immortal repeatForever.
        phase = -1
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
          phase = 1
        }
      }
      .onDisappear {
        withAnimation(nil) { phase = -1 }
      }
      .accessibilityHidden(true)
  }
}

// MARK: - View Extensions for Council

extension View {
  /// Applies the council light environment for this screen.
  func councilLight(_ env: CouncilLightEnvironment) -> some View {
    self.environment(\.councilLight, env)
  }
}

