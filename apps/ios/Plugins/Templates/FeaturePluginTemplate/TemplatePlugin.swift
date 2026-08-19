import SwiftUI

/// Template plugin for Max developer onboarding.
final class TemplatePlugin: MaxPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Developer Name", email: "developer@example.com", website: nil)
    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.example.plugin.my-feature",
      name: "My Feature Plugin",
      version: "1.0.0",
      description: "Short description of what My Feature Plugin adds to Max.",
      longDescription: "Detailed description explaining custom views, routes, widgets, or widgets registered.",
      author: author,
      category: .utility,
      tags: ["utility", "custom"],
      icon: PluginIcon(
        light: AssetReference(type: "system", name: "puzzlepiece.fill"),
        dark: AssetReference(type: "system", name: "puzzlepiece.fill"),
        monochrome: nil,
        animated: nil
      ),
      hero: nil,
      previews: [],
      capabilities: [.customRoute, .customWidget, .settingsPage],
      permissions: [.readPublicMetadata],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.example.plugin.my-feature")
  }

  func register(using context: MaxPluginContext) throws {
    // Register custom routes, widgets or actions here.
    // Example:
    // context.routes.register(id: "my-route", title: "My Route", iconName: "star") { _ in
    //   AnyView(Text(verbatim: "Hello from template plugin!"))
    // }
  }

  func settingsView() -> AnyView? {
    AnyView(
      Text(verbatim: "Settings panel for My Feature Plugin")
        .padding()
    )
  }
}


