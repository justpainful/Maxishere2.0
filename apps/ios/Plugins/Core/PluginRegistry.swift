import SwiftUI
import Observation
import Combine

struct NavigationContribution: Codable, Sendable, Hashable {
  let reorder: [String]?
  let hiddenOptionalItems: [String]?
}

@Observable
@MainActor
final class PluginStore {
  public static let shared = PluginStore()

  // Discovered bundled plugins
  public private(set) var availablePlugins: [any MaxPlugin] = []
  
  // States of each plugin
  public private(set) var pluginStates: [String: PluginState] = [:]
  
  // Scoped setting changes publisher for bindings
  var settingsUpdated = PassthroughSubject<String, Never>()

  // Centralized Generic Contributions
  public private(set) var routeContributions: [String: PluginRouteContribution] = [:]
  public private(set) var widgetContributions: [String: [PluginWidgetContribution]] = [:]
  public private(set) var actionContributions: [String: [PluginActionContribution]] = [:]

  // Navigation target route ID
  var activeRouteId: String?

  // Active visual plugin
  var activeVisualPluginId: String? {
    didSet {
      UserDefaults.standard.set(activeVisualPluginId, forKey: "app.max.plugins.activeVisualPluginId")
    }
  }

  // Set of installed plugin IDs
  public private(set) var installedPluginIds: Set<String> = [] {
    didSet {
      UserDefaults.standard.set(Array(installedPluginIds), forKey: "app.max.plugins.installedPluginIds")
    }
  }

  // Set of active feature plugin IDs
  public private(set) var activeFeaturePluginIds: Set<String> = [] {
    didSet {
      UserDefaults.standard.set(Array(activeFeaturePluginIds), forKey: "app.max.plugins.activeFeaturePluginIds")
    }
  }

  // Accepted permissions per plugin
  private var acceptedPermissions: [String: Set<String>] = [:] {
    didSet {
      let mapped = acceptedPermissions.mapValues { Array($0) }
      if let data = try? JSONEncoder().encode(mapped) {
        UserDefaults.standard.set(data, forKey: "app.max.plugins.acceptedPermissions")
      }
    }
  }

  // Logs list for diagnostics
  public private(set) var diagnosticLogs: [String] = []

  private init() {
    loadRegistry()
  }

  private func loadRegistry() {
    logDiagnostic("plugin.registry.booting", level: "info")
    
    // Load persisted installation states
    let savedInstalled = UserDefaults.standard.stringArray(forKey: "app.max.plugins.installedPluginIds") ?? []
    self.installedPluginIds = Set(savedInstalled)

    let savedActiveFeatures = UserDefaults.standard.stringArray(forKey: "app.max.plugins.activeFeaturePluginIds") ?? []
    self.activeFeaturePluginIds = Set(savedActiveFeatures)

    self.activeVisualPluginId = UserDefaults.standard.string(forKey: "app.max.plugins.activeVisualPluginId")

    if let permissionsData = UserDefaults.standard.data(forKey: "app.max.plugins.acceptedPermissions"),
       let decoded = try? JSONDecoder().decode([String: [String]].self, from: permissionsData) {
      self.acceptedPermissions = decoded.mapValues { Set($0) }
    }

    logDiagnostic("plugin.registry.loaded | Installed: \(savedInstalled.count), VisualActive: \(activeVisualPluginId ?? "none")", level: "info")
  }

  func bootstrap() {
    // Instantiate all plugins declared in the BundledPluginCatalog
    let instances = BundledPluginCatalog.makeAll()
    self.registerBuiltInPlugins(instances)
  }

  func registerBuiltInPlugins(_ plugins: [any MaxPlugin]) {
    self.availablePlugins = plugins
    for plugin in plugins {
      let id = plugin.manifest.id
      if id == activeVisualPluginId {
        pluginStates[id] = .active
        // Active visual plugin registers contributions on registry bootstrap
        try? plugin.register(using: plugin.context)
      } else if installedPluginIds.contains(id) {
        if activeFeaturePluginIds.contains(id) {
          pluginStates[id] = .active
          // Active feature plugin registers contributions
          try? plugin.register(using: plugin.context)
        } else {
          pluginStates[id] = .installed
        }
      } else {
        pluginStates[id] = .available
      }
    }
    
    // If active visual plugin isn't installed or is invalid, recover
    if let visualId = activeVisualPluginId, !installedPluginIds.contains(visualId) {
      logDiagnostic("plugin.recover.invalid_active_visual | Active visual \(visualId) not installed. Recovering...", level: "warning")
      activeVisualPluginId = nil
    }
  }

  func bindProxies(navigation: any MaxPluginNavigationProxy, library: any MaxPluginLibraryProxy) {
    for plugin in availablePlugins {
      plugin.context.navigation = navigation
      plugin.context.library = library
    }
  }

  // MARK: - Lifecycle Methods
  func install(pluginId: String) async {
    guard let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) else { return }
    logDiagnostic("plugin.install.started | ID: \(pluginId)", level: "info")
    pluginStates[pluginId] = .installing
    
    // Simulate short transaction check (compatibility, permissions)
    try? await Task.sleep(for: .milliseconds(800))
    
    // Accept all permissions by default during bundle install simulation
    let allPermissions = Set(plugin.manifest.permissions.map { $0.rawValue })
    acceptedPermissions[pluginId] = allPermissions
    
    installedPluginIds.insert(pluginId)
    pluginStates[pluginId] = .installed
    logDiagnostic("plugin.install.completed | ID: \(pluginId)", level: "info")
  }

  func uninstall(pluginId: String) async {
    guard let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) else { return }
    logDiagnostic("plugin.uninstall.started | ID: \(pluginId)", level: "info")
    pluginStates[pluginId] = .removing
    
    try? await Task.sleep(for: .milliseconds(500))
    
    cleanupContributions(for: pluginId)
    plugin.context.storage.clearAll()

    if activeVisualPluginId == pluginId {
      activeVisualPluginId = nil
    }
    activeFeaturePluginIds.remove(pluginId)
    installedPluginIds.remove(pluginId)
    acceptedPermissions.removeValue(forKey: pluginId)
    
    pluginStates[pluginId] = .available
    logDiagnostic("plugin.uninstall.completed | ID: \(pluginId)", level: "info")
  }

  func activateVisualPlugin(_ pluginId: String) {
    guard installedPluginIds.contains(pluginId) else { return }
    guard let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) else { return }
    
    logDiagnostic("plugin.activation.started | ID: \(pluginId)", level: "info")
    
    // Set active visual plugin (there can only be one)
    let previousActive = activeVisualPluginId
    activeVisualPluginId = pluginId
    
    // Update states
    if let prev = previousActive {
      cleanupContributions(for: prev)
      pluginStates[prev] = .installed
    }

    pluginStates[pluginId] = .active
    try? plugin.register(using: plugin.context)
    
    logDiagnostic("plugin.activation.completed | ID: \(pluginId)", level: "info")
  }

  func deactivateVisualPlugin() {
    guard let current = activeVisualPluginId else { return }
    logDiagnostic("plugin.deactivation.started | ID: \(current)", level: "info")
    cleanupContributions(for: current)
    activeVisualPluginId = nil
    pluginStates[current] = .installed
    logDiagnostic("plugin.deactivation.completed | ID: \(current)", level: "info")
  }

  func toggleFeaturePlugin(_ pluginId: String) {
    guard installedPluginIds.contains(pluginId) else { return }
    guard let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) else { return }

    logDiagnostic("plugin.feature.toggle | ID: \(pluginId)", level: "info")
    if activeFeaturePluginIds.contains(pluginId) {
      activeFeaturePluginIds.remove(pluginId)
      cleanupContributions(for: pluginId)
      pluginStates[pluginId] = .installed
    } else {
      activeFeaturePluginIds.insert(pluginId)
      pluginStates[pluginId] = .active
      try? plugin.register(using: plugin.context)
    }
  }

  // MARK: - Contribution Management
  func registerRoute(
    pluginId: String,
    routeId: String,
    title: String,
    iconName: String,
    presentation: MaxPluginRoutePresentation = .sheet,
    requiredPermission: PluginPermission? = nil,
    deepLinkLabel: String? = nil,
    priority: Int = 0,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable (String) -> AnyView
  ) {
    guard verifyRegistration(pluginId: pluginId, requiredCapability: .customRoute) else { return }
    
    // Prevent duplicate routes or core route replacements
    guard routeContributions[routeId] == nil else {
      logDiagnostic("Registration rejected: Duplicate route ID '\(routeId)'", level: "warning")
      return
    }
    
    let contribution = PluginRouteContribution(
      routeId: routeId,
      owningPluginId: pluginId,
      title: title,
      iconName: iconName,
      presentation: presentation,
      requiredPermission: requiredPermission,
      deepLinkLabel: deepLinkLabel,
      priority: priority,
      availabilityCondition: availabilityCondition,
      builder: builder
    )
    routeContributions[routeId] = contribution
    logDiagnostic("Route '\(routeId)' registered by plugin '\(pluginId)'", level: "info")
  }

  func registerWidget(
    pluginId: String,
    widgetId: String,
    pointId: String,
    title: String,
    accessibilityLabel: String?,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable () -> AnyView
  ) {
    guard verifyRegistration(pluginId: pluginId, requiredCapability: .customWidget) else { return }
    
    let contribution = PluginWidgetContribution(
      widgetId: widgetId,
      owningPluginId: pluginId,
      pointId: pointId,
      title: title,
      accessibilityLabel: accessibilityLabel,
      priority: priority,
      requiredPermission: requiredPermission,
      availabilityCondition: availabilityCondition,
      builder: builder
    )
    
    var existing = widgetContributions[pointId] ?? []
    // Prevent duplicate widgets
    if !existing.contains(where: { $0.widgetId == widgetId }) {
      existing.append(contribution)
      widgetContributions[pointId] = existing
      logDiagnostic("Widget '\(widgetId)' registered by plugin '\(pluginId)' at point '\(pointId)'", level: "info")
    }
  }

  func registerAction(
    pluginId: String,
    actionId: String,
    title: String,
    iconName: String,
    placement: PluginActionPlacement,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    perform: @escaping @Sendable () async -> Void
  ) {
    // Note: Actions can be used for custom navigation / integrations
    guard verifyRegistration(pluginId: pluginId, requiredCapability: nil) else { return }
    
    let contribution = PluginActionContribution(
      actionId: actionId,
      owningPluginId: pluginId,
      title: title,
      iconName: iconName,
      placement: placement,
      priority: priority,
      requiredPermission: requiredPermission,
      availabilityCondition: availabilityCondition,
      perform: perform
    )
    
    let placementId = placement.rawValue
    var existing = actionContributions[placementId] ?? []
    if !existing.contains(where: { $0.actionId == actionId }) {
      existing.append(contribution)
      actionContributions[placementId] = existing
      logDiagnostic("Action '\(actionId)' registered by plugin '\(pluginId)' at placement '\(placementId)'", level: "info")
    }
  }

  private func verifyRegistration(pluginId: String, requiredCapability: PluginCapability?) -> Bool {
    guard let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) else { return false }
    
    // Check if plugin is active
    let isActive = (activeVisualPluginId == pluginId) || activeFeaturePluginIds.contains(pluginId)
    guard isActive else {
      logDiagnostic("Registration rejected: Plugin '\(pluginId)' is not active.", level: "warning")
      return false
    }

    // Check capability
    if let capability = requiredCapability {
      guard plugin.manifest.capabilities.contains(capability) else {
        logDiagnostic("Registration rejected: Plugin '\(pluginId)' lacks capability '\(capability.rawValue)'.", level: "warning")
        return false
      }
    }
    
    return true
  }

  private func cleanupContributions(for pluginId: String) {
    logDiagnostic("plugin.contributions.cleanup | ID: \(pluginId)", level: "info")
    
    if let plugin = availablePlugins.first(where: { $0.manifest.id == pluginId }) {
      plugin.context.deactivate()
    }
    
    // Cleanup route contributions
    routeContributions = routeContributions.filter { $0.value.owningPluginId != pluginId }
    
    // Cleanup widget contributions
    for (point, widgets) in widgetContributions {
      widgetContributions[point] = widgets.filter { $0.owningPluginId != pluginId }
    }
    
    // Cleanup action contributions
    for (placement, actions) in actionContributions {
      actionContributions[placement] = actions.filter { $0.owningPluginId != pluginId }
    }
    
    if let routeId = activeRouteId, !routeContributions.keys.contains(routeId) {
      activeRouteId = nil
    }
  }

  // MARK: - Active Plugin Helpers
  var activeVisualPlugin: (any MaxVisualPlugin)? {
    guard let id = activeVisualPluginId else { return nil }
    return availablePlugins.first(where: { $0.manifest.id == id }) as? any MaxVisualPlugin
  }

  var navigationContribution: NavigationContribution? {
    activeVisualPlugin?.navigationContribution()
  }

  var activeFeaturePlugins: [any MaxPlugin] {
    availablePlugins.filter { activeFeaturePluginIds.contains($0.manifest.id) }
  }

  func widgetContributions(for pointId: String) -> [PluginWidgetContribution] {
    let list = widgetContributions[pointId] ?? []
    return list.sorted {
      if $0.priority != $1.priority {
        return $0.priority > $1.priority
      }
      return $0.widgetId < $1.widgetId
    }
  }

  func actionContributions(for placement: PluginActionPlacement) -> [PluginActionContribution] {
    let list = actionContributions[placement.rawValue] ?? []
    return list.sorted {
      if $0.priority != $1.priority {
        return $0.priority > $1.priority
      }
      return $0.actionId < $1.actionId
    }
  }

  func hasPermission(_ pluginId: String, permission: PluginPermission) -> Bool {
    acceptedPermissions[pluginId]?.contains(permission.rawValue) ?? false
  }

  func logDiagnostic(_ message: String, level: String = "info") {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] [\(level.uppercased())] \(message)"
    diagnosticLogs.append(entry)
    if diagnosticLogs.count > 500 {
      diagnosticLogs.removeFirst()
    }
    print(entry)
  }

  func enterSafeMode() {
    logDiagnostic("plugin.safemode.entered", level: "warning")
    activeVisualPluginId = nil
    activeFeaturePluginIds.removeAll()
    routeContributions.removeAll()
    widgetContributions.removeAll()
    actionContributions.removeAll()
    activeRouteId = nil
    for key in pluginStates.keys {
      pluginStates[key] = .disabled
    }
  }
}


