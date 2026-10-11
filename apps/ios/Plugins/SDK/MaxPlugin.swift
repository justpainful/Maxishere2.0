import SwiftUI

/// Base interface for all Max Plugins.
protocol MaxPlugin: AnyObject, Sendable {
  var manifest: MaxPluginManifest { get }
  var context: MaxPluginContext { get }
  
  /// Called on application start or when the plugin is loaded/initialized.
  @MainActor
  func register(using context: MaxPluginContext) throws
  
  /// Return custom settings configuration view, or nil if none.
  @MainActor
  func settingsView() -> AnyView?
  
  /// Render custom brand icon inside the store/settings views, or nil for default.
  @MainActor
  func iconView() -> AnyView?
  
  /// Render card preview background, or nil for default.
  @MainActor
  func previewBackground() -> AnyView?
}

extension MaxPlugin {
  func settingsView() -> AnyView? { nil }
  func iconView() -> AnyView? { nil }
  func previewBackground() -> AnyView? { nil }
}

/// Specialized plugin targeting interface styling, custom shaders, and particle emitters.
/// Implementers of this protocol must preserve Max's Liquid Glass Design System integrity.
/// 
/// ## Visual Integrity Constraints:
/// - **Background Blur**: Gaussian blur radii should be clamped between `3` and `30` points.
/// - **Opacity & Transparency**: Transparent surface overlays must maintain an opacity range of `0.15` to `0.92`. Values below `0.15` violate W3C contrast standards for core text labels.
/// - **Glow & Border Intensity**: Glow radii (shadows, outline stroke lights) must not exceed `15` points to prevent performance degradation on low-power devices.
protocol MaxVisualPlugin: MaxPlugin {
  @MainActor
  func overridePalette(for coreTheme: AppTheme, systemColorScheme: ColorScheme) -> MaxThemePalette?
  
  @MainActor
  func overlayView() -> AnyView?
  
  @MainActor
  func takeoverTransitionView(phase: CGFloat) -> AnyView?
  
  @MainActor
  func themeSwatchView() -> AnyView
  
  @MainActor
  func decorateCardBackground(
    palette: MaxThemePalette,
    cornerRadius: CGFloat,
    gyroOffset: CGSize,
    reduceTransparency: Bool
  ) -> AnyView

  @MainActor
  func decorateTabIndicator(palette: MaxThemePalette) -> AnyView
  
  @MainActor
  func decorateTabBarContainer(palette: MaxThemePalette, reduceTransparency: Bool) -> AnyView

  @MainActor
  func navigationContribution() -> NavigationContribution?
}

extension MaxVisualPlugin {
  func overridePalette(for coreTheme: AppTheme, systemColorScheme: ColorScheme) -> MaxThemePalette? { nil }
  func overlayView() -> AnyView? { nil }
  func takeoverTransitionView(phase: CGFloat) -> AnyView? { nil }
  func navigationContribution() -> NavigationContribution? { nil }
}


