import SwiftUI

struct WinterColor {
  public static let iceBlue = Color(red: 0.88, green: 0.94, blue: 1.0)
  public static let coldCyan = Color(red: 0.47, green: 0.78, blue: 0.91)
  public static let silver = Color(red: 0.75, green: 0.79, blue: 0.85)
  public static let deepFrost = Color(red: 0.07, green: 0.12, blue: 0.22)
  public static let polarLight = Color(red: 0.05, green: 0.08, blue: 0.14)
}

final class WinterIsComingPlugin: MaxVisualPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Team", email: "support@max.app", website: "https://max.app")
    let icon = PluginIcon(
      light: AssetReference(type: "system", name: "snowflake"),
      dark: AssetReference(type: "system", name: "snowflake"),
      monochrome: nil,
      animated: nil
    )
    let hero = PluginHero(
      title: "Winter Is Coming",
      subtitle: "Frost-glazed surfaces and drifting northern lights",
      backgroundAsset: AssetReference(type: "color", name: "deepFrost")
    )
    
    let preview = PluginPreview(
      name: "winter_preview_1",
      type: "interactive",
      title: "Frosted Glass Live View",
      asset: AssetReference(type: "system", name: "snowflake.circle"),
      aspectRatio: "16:9"
    )

    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.winter-is-coming",
      name: "Winter Is Coming",
      version: "1.0.0",
      description: "A cold, cinematic winter layout with frosted glass highlights and subtle snow particles.",
      longDescription: "Bring a quiet, wintry depth to Max. Liquid glass transforms into a frosted crystal material, accompanied by soft silver-blue light glows, slow-drifting snow dust, and arctic tones.",
      author: author,
      category: .seasonal,
      tags: ["winter", "cold", "frost", "cinematic"],
      icon: icon,
      hero: hero,
      previews: [preview],
      capabilities: [.theme, .navigationStyle, .cardStyle, .viewerStyle, .transitions],
      permissions: [.modifyAppearance, .modifyNavigation, .useHaptics],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.winter-is-coming")
  }

  func register(using context: MaxPluginContext) throws {
    // Dynamic registries can be added here
  }

  func overridePalette(for coreTheme: AppTheme, systemColorScheme: ColorScheme) -> MaxThemePalette? {
    let isDark = systemColorScheme == .dark
    
    return MaxThemePalette(
      selectedTheme: coreTheme,
      variant: isDark ? .neutralDark : .neutralLight,
      canvas: isDark ? WinterColor.polarLight : WinterColor.iceBlue,
      atmosphericBackground: isDark ? WinterColor.deepFrost : WinterColor.iceBlue.opacity(0.8),
      primaryContentSurface: isDark ? Color(red: 0.08, green: 0.12, blue: 0.20) : Color.white.opacity(0.85),
      elevatedContentSurface: isDark ? Color(red: 0.12, green: 0.18, blue: 0.28) : Color.white,
      primaryText: isDark ? Color.white : WinterColor.deepFrost,
      secondaryText: isDark ? Color.white.opacity(0.7) : WinterColor.deepFrost.opacity(0.7),
      tertiaryText: isDark ? Color.white.opacity(0.5) : WinterColor.deepFrost.opacity(0.5),
      separator: WinterColor.silver.opacity(0.3),
      accent: WinterColor.coldCyan,
      selectedControl: WinterColor.coldCyan.opacity(isDark ? 0.25 : 0.15),
      destructive: Color(red: 0.9, green: 0.3, blue: 0.3),
      warning: Color(red: 0.9, green: 0.6, blue: 0.2),
      success: Color(red: 0.3, green: 0.8, blue: 0.5),
      disabled: Color.gray,
      mediaOverlay: Color.black.opacity(0.75),
      scrim: Color.black.opacity(0.5)
    )
  }

  func navigationContribution() -> NavigationContribution? {
    return nil
  }

  func overlayView() -> AnyView? {
    AnyView(
      SnowParticleView()
    )
  }

  func takeoverTransitionView(phase: CGFloat) -> AnyView? {
    AnyView(
      GeometryReader { geo in
        let size = geo.size
        ZStack {
          Color(red: 0.05, green: 0.08, blue: 0.14)
            .ignoresSafeArea()
            .opacity(Double(phase))
          
          Image(systemName: "snowflake")
            .font(.system(size: 160))
            .foregroundStyle(WinterColor.coldCyan.opacity(0.25))
            .scaleEffect(1.0 + (1.0 - phase) * 2.0)
            .rotationEffect(.degrees(Double(phase) * 90.0))
            .opacity(Double(phase))
          
          VStack {
            Text(verbatim: "WINTER IS COMING")
              .font(.system(size: 32, weight: .bold, design: .monospaced))
              .tracking(10)
              .foregroundStyle(Color.white)
              .opacity(phase > 0.5 ? 1.0 : 0.0)
              .scaleEffect(phase > 0.5 ? 1.0 : 0.8)
          }
        }
      }
    )
  }

  func settingsView() -> AnyView? {
    AnyView(WinterSettingsView())
  }

  func iconView() -> AnyView? {
    let systemName = manifest.icon.light.name
    return AnyView(
      ZStack {
        Color.clear
        Image(systemName: systemName)
          .font(.title)
          .foregroundStyle(WinterColor.coldCyan)
          .shadow(color: WinterColor.iceBlue, radius: 4)
      }
    )
  }

  func previewBackground() -> AnyView? {
    AnyView(
      LinearGradient(colors: [WinterColor.deepFrost, WinterColor.coldCyan], startPoint: .top, endPoint: .bottom)
    )
  }

  func themeSwatchView() -> AnyView {
    AnyView(
      LinearGradient(colors: [WinterColor.deepFrost, WinterColor.coldCyan], startPoint: .top, endPoint: .bottom)
    )
  }

  func decorateCardBackground(
    palette: MaxThemePalette,
    cornerRadius: CGFloat,
    gyroOffset: CGSize,
    reduceTransparency: Bool
  ) -> AnyView {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return AnyView(
      ZStack {
        if reduceTransparency {
          shape.fill(palette.primaryContentSurface.opacity(0.96))
        } else if #available(iOS 26.0, *) {
          Color.clear
            .glassEffect(
              .regular.tint(WinterColor.iceBlue.opacity(0.18)),
              in: shape
            )
        } else {
          shape.fill(palette.primaryContentSurface.opacity(0.92))
        }
        
        shape
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.35),
                WinterColor.iceBlue.opacity(0.2),
                Color.clear
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
              Color.white.opacity(0.8),
              WinterColor.silver,
              WinterColor.coldCyan.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1.2
        )
      }
      .background {
        shape
          .fill(WinterColor.coldCyan.opacity(0.12))
          .blur(radius: 12)
          .padding(4)
      }
    )
  }

  func decorateTabIndicator(palette: MaxThemePalette) -> AnyView {
    AnyView(
      Capsule()
        .fill(WinterColor.coldCyan.opacity(0.2))
        .overlay {
          Capsule()
            .stroke(WinterColor.silver, lineWidth: 1)
        }
    )
  }

  func decorateTabBarContainer(palette: MaxThemePalette, reduceTransparency: Bool) -> AnyView {
    let shape = Capsule()
    return AnyView(
      ZStack {
        shape
          .fill(WinterColor.polarLight.opacity(0.6))
        
        if #available(iOS 26.0, *) {
          Color.clear
            .glassEffect(.regular.tint(WinterColor.iceBlue.opacity(0.12)), in: shape)
        }
        
        shape
          .stroke(WinterColor.silver.opacity(0.6), lineWidth: 1.2)
      }
    )
  }
}

struct WinterSettingsView: View {
  @State private var showSnow = true
  @State private var frostIntensity = 0.5

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text(verbatim: "Winter Is Coming Settings")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      Toggle(isOn: $showSnow) {
        Text(verbatim: "Show Snow Particles")
      }
      .toggleStyle(SwitchToggleStyle(tint: WinterColor.coldCyan))
      
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: "Frost Glass Intensity: \(Int(frostIntensity * 100))%")
          .font(.subheadline)
        Slider(value: $frostIntensity, in: 0...1)
          .tint(WinterColor.coldCyan)
      }
    }
    .padding()
    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
  }
}

// Lightweight Snow Particle Effect using SwiftUI TimelineView (respects low power & reduce motion)
struct SnowParticle: Identifiable {
  let id = UUID()
  var x: CGFloat
  var y: CGFloat
  var speed: CGFloat
  var size: CGFloat
  var opacity: Double
}

struct SnowParticleView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false
  
  @State private var particles: [SnowParticle] = []
  
  var body: some View {
    if reduceMotion || calmBackground {
      EmptyView()
    } else {
      TimelineView(.animation(minimumInterval: 1.0/30.0, paused: false)) { timeline in
        Canvas { context, size in
          updateParticles(in: size)
          for particle in particles {
            let rect = CGRect(x: particle.x, y: particle.y, width: particle.size, height: particle.size)
            context.opacity = particle.opacity
            context.fill(Path(ellipseIn: rect), with: .color(.white))
          }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      }
    }
  }
  
  private func updateParticles(in size: CGSize) {
    if particles.isEmpty {
      for _ in 0..<35 {
        particles.append(
          SnowParticle(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: -size.height...size.height),
            speed: CGFloat.random(in: 1.0...2.5),
            size: CGFloat.random(in: 2...5),
            opacity: Double.random(in: 0.3...0.7)
          )
        )
      }
    } else {
      for index in particles.indices {
        particles[index].y += particles[index].speed
        if particles[index].y > size.height {
          particles[index].y = -10
          particles[index].x = CGFloat.random(in: 0...size.width)
        }
      }
    }
  }
}


