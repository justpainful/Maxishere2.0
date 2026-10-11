import SwiftUI

/// Declarative catalog containing all compiled-in visual and feature plugins.
enum BundledPluginCatalog {
  static func makeAll() -> [any MaxPlugin] {
    [
      ChromaticPlugin(),
      WinterIsComingPlugin(),
      HalloweenPlugin(),
      ActivityInsightsPlugin(),
      QuickActionsPlugin(),
      ExternalDataLabPlugin()
    ]
  }
}


