import SwiftUI

struct HalloweenColor {
  public static let pumpkin = Color(red: 1.0, green: 0.46, blue: 0.09) // Orange
  public static let witchPurple = Color(red: 0.51, green: 0.13, blue: 0.81) // Purple
  public static let deepShadow = Color(red: 0.06, green: 0.05, blue: 0.08) // Ink Black
  public static let toxicGreen = Color(red: 0.25, green: 0.82, blue: 0.16)
}

final class HalloweenPlugin: MaxVisualPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Team", email: "support@max.app", website: "https://max.app")
    let icon = PluginIcon(
      light: AssetReference(type: "system", name: "sparkles.rectangle.stack"),
      dark: AssetReference(type: "system", name: "sparkles.rectangle.stack"),
      monochrome: nil,
      animated: nil
    )
    let hero = PluginHero(
      title: "Halloween Spooky Hub",
      subtitle: "Eerie purple glows and shadow-mist",
      backgroundAsset: AssetReference(type: "color", name: "witchPurple")
    )
    
    let preview = PluginPreview(
      name: "halloween_preview_1",
      type: "interactive",
      title: "Spooky Glass Live View",
      asset: AssetReference(type: "system", name: "sparkles"),
      aspectRatio: "16:9"
    )

    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.halloween",
      name: "Halloween",
      version: "1.0.0",
      description: "A spooky, mysterious seasonal layout with purple and orange glowing glass highlights.",
      longDescription: "Enter the shadows. Max takes on a deep mysterious vibe featuring dark velvet surfaces, pulsing orange and purple glass card borders, and drifting shadow-fog animation.",
      author: author,
      category: .seasonal,
      tags: ["halloween", "seasonal", "spooky", "dark"],
      icon: icon,
      hero: hero,
      previews: [preview],
      capabilities: [.theme, .navigationStyle, .cardStyle, .transitions],
      permissions: [.modifyAppearance, .modifyNavigation, .useHaptics],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.halloween")
  }

  func register(using context: MaxPluginContext) throws {
    // Registrations if any
  }

  func overridePalette(for coreTheme: AppTheme, systemColorScheme: ColorScheme) -> MaxThemePalette? {
    return MaxThemePalette(
      selectedTheme: coreTheme,
      variant: .neutralDark,
      canvas: HalloweenColor.deepShadow,
      atmosphericBackground: HalloweenColor.witchPurple.opacity(0.12),
      primaryContentSurface: Color(red: 0.11, green: 0.09, blue: 0.14),
      elevatedContentSurface: Color(red: 0.15, green: 0.12, blue: 0.20),
      primaryText: Color(red: 0.95, green: 0.94, blue: 0.96),
      secondaryText: Color(red: 0.95, green: 0.94, blue: 0.96).opacity(0.7),
      tertiaryText: Color(red: 0.95, green: 0.94, blue: 0.96).opacity(0.45),
      separator: HalloweenColor.witchPurple.opacity(0.25),
      accent: HalloweenColor.pumpkin,
      selectedControl: HalloweenColor.witchPurple.opacity(0.35),
      destructive: Color.red,
      warning: HalloweenColor.pumpkin,
      success: HalloweenColor.toxicGreen,
      disabled: Color.gray,
      mediaOverlay: Color.black.opacity(0.8),
      scrim: Color.black.opacity(0.6)
    )
  }

  func navigationContribution() -> NavigationContribution? {
    return nil
  }

  func overlayView() -> AnyView? {
    AnyView(
      SpookyFogView()
    )
  }

  func takeoverTransitionView(phase: CGFloat) -> AnyView? {
    AnyView(
      GeometryReader { geo in
        let size = geo.size
        ZStack {
          Color.black
            .ignoresSafeArea()
          
          RadialGradient(
            colors: [HalloweenColor.witchPurple.opacity(0.65), .clear],
            center: .center,
            startRadius: 5,
            endRadius: phase * size.width * 0.7
          )
          .ignoresSafeArea()
          
          Image(systemName: "sparkles.rectangle.stack")
            .font(.system(size: 140))
            .foregroundStyle(HalloweenColor.pumpkin.opacity(0.4))
            .scaleEffect(0.6 + phase * 0.4)
            .opacity(Double(phase))
          
          VStack {
            Text(verbatim: "HALLOWEEN")
              .font(.system(size: 38, weight: .black, design: .serif))
              .foregroundStyle(HalloweenColor.pumpkin)
              .tracking(6)
              .shadow(color: HalloweenColor.pumpkin.opacity(0.6), radius: 10)
              .opacity(phase > 0.65 ? 1.0 : 0.0)
              .scaleEffect(phase > 0.65 ? 1.0 : 0.5)
          }
        }
      }
    )
  }

  func settingsView() -> AnyView? {
    AnyView(HalloweenSettingsView())
  }

  func iconView() -> AnyView? {
    let systemName = manifest.icon.light.name
    return AnyView(
      ZStack {
        Color.clear
        Image(systemName: systemName)
          .font(.title)
          .foregroundStyle(HalloweenColor.pumpkin)
          .shadow(color: HalloweenColor.pumpkin, radius: 6)
      }
    )
  }

  func previewBackground() -> AnyView? {
    AnyView(
      LinearGradient(colors: [HalloweenColor.witchPurple, HalloweenColor.deepShadow], startPoint: .top, endPoint: .bottom)
    )
  }

  func themeSwatchView() -> AnyView {
    AnyView(
      LinearGradient(colors: [HalloweenColor.witchPurple, HalloweenColor.pumpkin], startPoint: .top, endPoint: .bottom)
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
              .regular.tint(HalloweenColor.witchPurple.opacity(0.16)),
              in: shape
            )
        } else {
          shape.fill(palette.primaryContentSurface.opacity(0.92))
        }

        shape.stroke(
          LinearGradient(
            colors: [HalloweenColor.pumpkin, HalloweenColor.witchPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1.5
        )
      }
      .background {
        shape
          .fill(HalloweenColor.witchPurple.opacity(0.15))
          .blur(radius: 14)
          .padding(4)
      }
    )
  }

  func decorateTabIndicator(palette: MaxThemePalette) -> AnyView {
    AnyView(
      Capsule()
        .fill(HalloweenColor.witchPurple.opacity(0.4))
        .overlay {
          Capsule()
            .stroke(HalloweenColor.pumpkin, lineWidth: 1.2)
            .shadow(color: HalloweenColor.pumpkin, radius: 4)
        }
    )
  }

  func decorateTabBarContainer(palette: MaxThemePalette, reduceTransparency: Bool) -> AnyView {
    let shape = Capsule()
    return AnyView(
      ZStack {
        shape
          .fill(HalloweenColor.deepShadow.opacity(0.8))
        
        if #available(iOS 26.0, *) {
          Color.clear
            .glassEffect(.regular.tint(HalloweenColor.witchPurple.opacity(0.15)), in: shape)
        }
        
        shape
          .stroke(
            LinearGradient(
              colors: [HalloweenColor.pumpkin, HalloweenColor.witchPurple],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1.5
          )
          .shadow(color: HalloweenColor.witchPurple.opacity(0.5), radius: 6)
      }
    )
  }
}

struct HalloweenSettingsView: View {
  @State private var enableFog = true
  @State private var pulseIntensity = 0.5

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text(verbatim: "Halloween Settings")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      Toggle(isOn: $enableFog) {
        Text(verbatim: "Enable Spooky Fog Effect")
      }
      .toggleStyle(SwitchToggleStyle(tint: HalloweenColor.pumpkin))
      
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: "Glow Pulse Speed: \(Int(pulseIntensity * 100))%")
          .font(.subheadline)
        Slider(value: $pulseIntensity, in: 0...1)
          .tint(HalloweenColor.pumpkin)
      }
    }
    .padding()
    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
  }
}

// Spooky Fog particles
struct FogParticle: Identifiable {
  let id = UUID()
  var x: CGFloat
  var y: CGFloat
  var vx: CGFloat
  var size: CGFloat
  var opacity: Double
}

struct SpookyFogView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("app.max.preferences.reduceBackgroundMotion") private var calmBackground = false
  
  @State private var particles: [FogParticle] = []

  var body: some View {
    if reduceMotion || calmBackground {
      EmptyView()
    } else {
      TimelineView(.animation(minimumInterval: 1.0/30.0, paused: false)) { timeline in
        Canvas { context, size in
          updateParticles(in: size)
          for p in particles {
            context.opacity = p.opacity
            let rect = CGRect(x: p.x, y: p.y, width: p.size, height: p.size)
            context.fill(Path(ellipseIn: rect), with: .color(HalloweenColor.witchPurple.opacity(0.2)))
          }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      }
    }
  }

  private func updateParticles(in size: CGSize) {
    if particles.isEmpty {
      for _ in 0..<12 {
        particles.append(
          FogParticle(
            x: CGFloat.random(in: -50...size.width),
            y: size.height - CGFloat.random(in: 40...200),
            vx: CGFloat.random(in: 0.3...1.2),
            size: CGFloat.random(in: 120...240),
            opacity: Double.random(in: 0.08...0.22)
          )
        )
      }
    } else {
      for index in particles.indices {
        particles[index].x += particles[index].vx
        if particles[index].x > size.width {
          particles[index].x = -200
        }
      }
    }
  }
}


