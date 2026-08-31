import SwiftUI

struct ChromaticColor {
  public static let red = Color(red: 1.0, green: 0.09, blue: 0.12)
  public static let orange = Color(red: 1.0, green: 0.45, blue: 0.09)
  public static let yellow = Color(red: 1.0, green: 0.91, blue: 0.07)
  public static let green = Color(red: 0.16, green: 0.79, blue: 0.26)
  public static let cyan = Color(red: 0.07, green: 0.74, blue: 0.93)
  public static let blue = Color(red: 0.09, green: 0.41, blue: 0.91)
  public static let purple = Color(red: 0.44, green: 0.20, blue: 0.91)
  public static let magenta = Color(red: 0.95, green: 0.17, blue: 0.61)
  public static let ink = Color(red: 0.04, green: 0.04, blue: 0.04)
  public static let paper = Color(red: 1.0, green: 0.996, blue: 0.992)
  public static let blush = Color(red: 1.0, green: 0.56, blue: 0.77)
}

final class ChromaticPlugin: MaxVisualPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Team", email: "support@max.app", website: "https://max.app")
    let icon = PluginIcon(
      light: AssetReference(type: "system", name: "paintpalette.fill"),
      dark: AssetReference(type: "system", name: "paintpalette.fill"),
      monochrome: nil,
      animated: nil
    )
    let hero = PluginHero(
      title: "Chromatic Marker Scribble",
      subtitle: "Playful marker strokes and chaotic color trails",
      backgroundAsset: AssetReference(type: "color", name: "blush")
    )
    
    let preview1 = PluginPreview(
      name: "chromatic_preview_1",
      type: "interactive",
      title: "Chromatic Marker Scribble Live View",
      asset: AssetReference(type: "system", name: "paintpalette"),
      aspectRatio: "16:9"
    )

    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.chromatic",
      name: "Chromatic",
      version: "1.0.0",
      description: "A playful marker-drawn theme with chaotic color trails and hand-sketched UI borders.",
      longDescription: "Turn your Max interface into a beautiful sketchbook! Experience hand-sketched outlines, paint indicator lights, and marker scribbles that trail after your taps. It's colorful, bold, and entirely non-corporate.",
      author: author,
      category: .appearance,
      tags: ["marker", "playful", "sketch", "colorful"],
      icon: icon,
      hero: hero,
      previews: [preview1],
      capabilities: [.theme, .navigationStyle, .cardStyle, .emptyStateStyle, .transitions],
      permissions: [.modifyAppearance, .modifyNavigation, .useHaptics],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.chromatic")
  }

  func register(using context: MaxPluginContext) throws {
    // Visual theme registrations if any
  }

  func overridePalette(for coreTheme: AppTheme, systemColorScheme: ColorScheme) -> MaxThemePalette? {
    let isDark = systemColorScheme == .dark
    
    return MaxThemePalette(
      selectedTheme: coreTheme,
      variant: isDark ? .neutralDark : .neutralLight,
      canvas: isDark ? ChromaticColor.ink : ChromaticColor.paper,
      atmosphericBackground: isDark ? ChromaticColor.purple.opacity(0.15) : ChromaticColor.blush.opacity(0.25),
      primaryContentSurface: isDark ? Color(white: 0.12) : Color.white,
      elevatedContentSurface: isDark ? Color(white: 0.18) : ChromaticColor.paper,
      primaryText: isDark ? ChromaticColor.paper : ChromaticColor.ink,
      secondaryText: isDark ? ChromaticColor.paper.opacity(0.7) : ChromaticColor.ink.opacity(0.7),
      tertiaryText: isDark ? ChromaticColor.paper.opacity(0.5) : ChromaticColor.ink.opacity(0.5),
      separator: ChromaticColor.ink.opacity(isDark ? 0.3 : 0.15),
      accent: ChromaticColor.magenta,
      selectedControl: ChromaticColor.blush.opacity(0.3),
      destructive: ChromaticColor.red,
      warning: ChromaticColor.orange,
      success: ChromaticColor.green,
      disabled: Color.gray,
      mediaOverlay: Color.black.opacity(0.6),
      scrim: Color.black.opacity(0.4)
    )
  }

  func navigationContribution() -> NavigationContribution? {
    return NavigationContribution(
      reorder: ["shared", "vault", "library", "chats", "profile"],
      hiddenOptionalItems: nil
    )
  }

  func overlayView() -> AnyView? {
    AnyView(
      Canvas { context, size in
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.1, y: size.height * 0.15))
        path.addQuadCurve(to: CGPoint(x: size.width * 0.4, y: size.height * 0.12), control: CGPoint(x: size.width * 0.25, y: size.height * 0.08))
        path.addQuadCurve(to: CGPoint(x: size.width * 0.3, y: size.height * 0.22), control: CGPoint(x: size.width * 0.38, y: size.height * 0.18))
        context.stroke(path, with: .color(ChromaticColor.yellow.opacity(0.12)), lineWidth: 8)
      }
      .allowsHitTesting(false)
    )
  }

  func takeoverTransitionView(phase: CGFloat) -> AnyView? {
    AnyView(
      GeometryReader { geo in
        let size = geo.size
        let colors = [ChromaticColor.red, ChromaticColor.orange, ChromaticColor.yellow, ChromaticColor.green, ChromaticColor.cyan, ChromaticColor.blue, ChromaticColor.purple, ChromaticColor.magenta]
        
        ZStack {
          ForEach(0..<colors.count, id: \.self) { i in
            let angle = Double(i) * (360.0 / Double(colors.count))
            let length = phase * size.width * 0.8
            
            Path { path in
              path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
              let dx = length * cos(angle * .pi / 180)
              let dy = length * sin(angle * .pi / 180)
              
              var currentX = size.width / 2
              var currentY = size.height / 2
              let steps = 6
              for step in 1...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let targetX = (size.width / 2) + dx * ratio + CGFloat.random(in: -15...15)
                let targetY = (size.height / 2) + dy * ratio + CGFloat.random(in: -15...15)
                path.addLine(to: CGPoint(x: targetX, y: targetY))
                currentX = targetX
                currentY = targetY
              }
            }
            .stroke(colors[i].opacity(0.85), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
          }
          
          VStack {
            Text(verbatim: "Chromatic")
              .font(.system(size: 42, weight: .black, design: .serif))
              .foregroundStyle(ChromaticColor.ink)
              .padding(24)
              .background(ChromaticColor.paper, in: RoundedRectangle(cornerRadius: 16))
              .rotationEffect(.degrees(-4))
              .scaleEffect(phase > 0.6 ? 1.0 : 0.2)
              .opacity(phase > 0.6 ? 1.0 : 0.0)
          }
        }
      }
    )
  }

  func settingsView() -> AnyView? {
    AnyView(ChromaticSettingsView())
  }

  func iconView() -> AnyView? {
    let systemName = manifest.icon.light.name
    return AnyView(
      ZStack {
        Circle()
          .fill(ChromaticColor.blush.opacity(0.6))
        
        Image(systemName: systemName)
          .font(.title2)
          .foregroundStyle(ChromaticColor.magenta)
          .offset(x: -3, y: -3)
        
        Image(systemName: systemName)
          .font(.title2)
          .foregroundStyle(ChromaticColor.cyan)
          .offset(x: 3, y: 3)
          .blendMode(.multiply)
      }
    )
  }

  func previewBackground() -> AnyView? {
    AnyView(
      LinearGradient(colors: [ChromaticColor.red, ChromaticColor.yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
  }

  func themeSwatchView() -> AnyView {
    AnyView(
      LinearGradient(colors: [ChromaticColor.red, ChromaticColor.yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
  }

  func decorateCardBackground(
    palette: MaxThemePalette,
    cornerRadius: CGFloat,
    gyroOffset: CGSize,
    reduceTransparency: Bool
  ) -> AnyView {
    AnyView(
      ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(palette.primaryContentSurface)
        HandDrawnBorder(cornerRadius: cornerRadius, color: ChromaticColor.ink, lineWidth: 2)
      }
    )
  }

  func decorateTabIndicator(palette: MaxThemePalette) -> AnyView {
    AnyView(
      Capsule()
        .fill(ChromaticColor.yellow.opacity(0.45))
        .overlay {
          Capsule()
            .stroke(ChromaticColor.ink, lineWidth: 1.5)
        }
    )
  }

  func decorateTabBarContainer(palette: MaxThemePalette, reduceTransparency: Bool) -> AnyView {
    let shape = Capsule()
    return AnyView(
      shape
        .fill(ChromaticColor.paper)
        .overlay {
          shape.stroke(ChromaticColor.ink, lineWidth: 2)
        }
    )
  }
}

// Scoped settings View
struct ChromaticSettingsView: View {
  @State private var densityIndex = 1 // 0: Soft, 1: Playful, 2: Chaos

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text(verbatim: "Chromatic Settings")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      Picker(selection: $densityIndex) {
        Text(verbatim: "Soft").tag(0)
        Text(verbatim: "Playful").tag(1)
        Text(verbatim: "Chaos").tag(2)
      } label: {
        Text(verbatim: "Scribble Intensity")
      }
      .pickerStyle(.segmented)
      
      Text(verbatim: "Controls how chaotic and colorful the marker scribbles look. Under Chaos, elements have double stroke thickness and larger hit areas.")
        .font(.caption)
        .foregroundStyle(MaxColor.textSecondary)
    }
    .padding()
    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
  }
}

// Hand-Drawn border overlay for cards
struct HandDrawnBorder: View {
  let cornerRadius: CGFloat
  let color: Color
  let lineWidth: CGFloat

  init(cornerRadius: CGFloat = 12, color: Color = ChromaticColor.ink, lineWidth: CGFloat = 2) {
    self.cornerRadius = cornerRadius
    self.color = color
    self.lineWidth = lineWidth
  }

  var body: some View {
    GeometryReader { geo in
      Path { path in
        let w = geo.size.width
        let h = geo.size.height
        
        path.move(to: CGPoint(x: -2, y: 1))
        path.addQuadCurve(to: CGPoint(x: w + 2, y: -1), control: CGPoint(x: w / 2, y: CGFloat.random(in: -3...3)))
        
        path.move(to: CGPoint(x: w - 1, y: -2))
        path.addQuadCurve(to: CGPoint(x: w + 1, y: h + 2), control: CGPoint(x: w + CGFloat.random(in: -3...3), y: h / 2))

        path.move(to: CGPoint(x: w + 2, y: h - 1))
        path.addQuadCurve(to: CGPoint(x: -2, y: h + 1), control: CGPoint(x: w / 2, y: h + CGFloat.random(in: -3...3)))

        path.move(to: CGPoint(x: 1, y: h + 2))
        path.addQuadCurve(to: CGPoint(x: -1, y: -2), control: CGPoint(x: CGFloat.random(in: -3...3), y: h / 2))
      }
      .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
  }
}


