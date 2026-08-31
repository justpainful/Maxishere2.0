import SwiftUI

final class QuickActionsPlugin: MaxPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Lab", email: "quickactions@max.app", website: nil)
    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.quick-actions",
      name: "Quick Actions",
      version: "0.9.0-experimental",
      description: "Adds configurable shortcut actions to your Home view for faster navigation.",
      longDescription: "Navigate Max faster. This experimental utility plugin registers convenient quick-action shortcut buttons (to Vault, Library, Chats, or Settings) and integrates with the central action system.",
      author: author,
      category: .utility,
      tags: ["experimental", "utility", "navigation"],
      icon: PluginIcon(
        light: AssetReference(type: "system", name: "bolt.fill"),
        dark: AssetReference(type: "system", name: "bolt.fill"),
        monochrome: nil,
        animated: nil
      ),
      hero: nil,
      previews: [],
      capabilities: [.customWidget, .settingsPage],
      permissions: [.modifyNavigation, .useHaptics],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.quick-actions")
  }

  func register(using context: MaxPluginContext) throws {
    // Register actions
    context.actions.register(
      id: "go-vault",
      title: "Open Vault",
      iconName: "lock.shield.fill",
      placement: .quickActions
    ) { [weak self] in
      self?.context.haptics.triggerImpact(.medium)
      Task { @MainActor [weak self] in
        self?.context.navigation?.selectTab(tabId: "vault")
      }
    }

    context.actions.register(
      id: "go-library",
      title: "Open Library",
      iconName: "folder.fill.badge.gearshape",
      placement: .quickActions
    ) { [weak self] in
      self?.context.haptics.triggerImpact(.medium)
      Task { @MainActor [weak self] in
        self?.context.navigation?.selectTab(tabId: "library")
      }
    }

    context.actions.register(
      id: "go-chats",
      title: "Open Chats",
      iconName: "bubble.left.and.bubble.right.fill",
      placement: .quickActions
    ) { [weak self] in
      self?.context.haptics.triggerImpact(.medium)
      Task { @MainActor [weak self] in
        self?.context.navigation?.selectTab(tabId: "chats")
      }
    }

    context.actions.register(
      id: "go-settings",
      title: "Open Settings",
      iconName: "gearshape.fill",
      placement: .quickActions
    ) { [weak self] in
      self?.context.haptics.triggerImpact(.medium)
      Task { @MainActor [weak self] in
        self?.context.navigation?.openRoute(routeId: "settings")
      }
    }

    // Register Home Widget
    context.widgets.register(
      id: "quickactions:widget",
      pointId: "home:afterHero",
      title: "Quick Access Panel",
      accessibilityLabel: "Quick Actions Shortcuts Widget"
    ) { [weak self] in
      AnyView(QuickActionsWidget(context: self?.context ?? MaxPluginContext(pluginId: "com.max.plugin.quick-actions")))
    }
  }

  func settingsView() -> AnyView? {
    AnyView(QuickActionsSettingsView(context: context))
  }
}

// MARK: - Quick Actions Widget UI
struct QuickActionsWidget: View {
  let context: MaxPluginContext
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      Text(verbatim: "Quick Access Panel")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(palette.primaryText)
      
      let allActions = PluginStore.shared.actionContributions(for: .quickActions)
      
      // Load configuration from sandboxed storage
      let configuredString = context.storage.string(forKey: "selected_shortcuts") ?? "go-vault,go-library,go-chats"
      let configuredIds = configuredString.split(separator: ",").map(String.init)
      let maxCount = context.storage.integer(forKey: "max_action_count")
      let limit = maxCount > 0 ? maxCount : 3
      
      // Filter and order based on configured list, clamping to limit
      let orderedActions = configuredIds.compactMap { id in
        allActions.first(where: { $0.actionId == id })
      }.prefix(limit)

      if orderedActions.isEmpty {
        Text(verbatim: "No shortcuts configured")
          .font(.caption)
          .foregroundStyle(palette.tertiaryText)
      } else {
        HStack(spacing: MaxSpace.sm) {
          ForEach(orderedActions) { action in
            Button {
              Task {
                await action.perform()
              }
            } label: {
              VStack(spacing: MaxSpace.xs) {
                Image(systemName: action.iconName)
                  .font(.headline)
                  .foregroundStyle(palette.accent)
                  .frame(width: 44, height: 44)
                  .background(palette.selectedControl, in: Circle())
                
                Text(verbatim: action.title)
                  .font(.caption2.weight(.medium))
                  .foregroundStyle(palette.secondaryText)
                  .lineLimit(1)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, MaxSpace.xs)
              .background(palette.elevatedContentSurface)
              .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small))
              .overlay {
                RoundedRectangle(cornerRadius: MaxRadius.small)
                  .stroke(palette.separator, lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(MaxSpace.md)
    .background(palette.primaryContentSurface)
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MaxRadius.medium)
        .stroke(palette.separator, lineWidth: 1)
    }
  }
}

// MARK: - Configurable Settings View
struct QuickActionsSettingsView: View {
  let context: MaxPluginContext

  @State private var showVault = true
  @State private var showLibrary = true
  @State private var showChats = true
  @State private var showSettings = false
  @State private var maxCount = 3

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      Text(verbatim: "Configure Quick Actions Shortcuts")
        .font(.headline)
        .foregroundStyle(MaxColor.textPrimary)

      VStack(spacing: MaxSpace.sm) {
        Toggle("Show Vault Shield", isOn: $showVault)
        Toggle("Show Library Folder", isOn: $showLibrary)
        Toggle("Show Chat Bubbles", isOn: $showChats)
        Toggle("Show Settings Gear", isOn: $showSettings)
      }
      .toggleStyle(SwitchToggleStyle(tint: MaxColor.periwinkle))

      Stepper("Maximum Displayed: \(maxCount)", value: $maxCount, in: 1...4)
        .font(.subheadline)

      Button(action: saveConfiguration) {
        Text(verbatim: "Save Shortcuts Settings")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.vertical, MaxSpace.xs)
          .frame(maxWidth: .infinity)
          .background(MaxColor.sky, in: Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding()
    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    .onAppear(perform: loadConfiguration)
  }

  private func loadConfiguration() {
    let configuredString = context.storage.string(forKey: "selected_shortcuts") ?? "go-vault,go-library,go-chats"
    let ids = configuredString.split(separator: ",").map(String.init)
    showVault = ids.contains("go-vault")
    showLibrary = ids.contains("go-library")
    showChats = ids.contains("go-chats")
    showSettings = ids.contains("go-settings")
    
    let count = context.storage.integer(forKey: "max_action_count")
    maxCount = count > 0 ? count : 3
  }

  private func saveConfiguration() {
    var ids: [String] = []
    if showVault { ids.append("go-vault") }
    if showLibrary { ids.append("go-library") }
    if showChats { ids.append("go-chats") }
    if showSettings { ids.append("go-settings") }
    
    let configuredString = ids.joined(separator: ",")
    context.storage.set(configuredString, forKey: "selected_shortcuts")
    context.storage.set(maxCount, forKey: "max_action_count")
    context.haptics.triggerNotification(.success)
  }
}


