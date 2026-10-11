import SwiftUI

/// Presentation styles for plugin routes.
enum MaxPluginRoutePresentation: String, Codable, Sendable, Hashable {
  case navigation
  case sheet
  case fullScreenCover
}

/// Placement rules for quick action shortcuts.
enum PluginActionPlacement: String, Codable, Sendable, Hashable {
  case quickActions = "quick-actions"
  case toolbar = "toolbar"
  case contextMenu = "context-menu"
}

/// Represents a custom route contribution registered by a plugin.
struct PluginRouteContribution: Identifiable, Sendable {
  var id: String { routeId }
  let routeId: String
  let owningPluginId: String
  let title: String
  let iconName: String
  let presentation: MaxPluginRoutePresentation
  let requiredPermission: PluginPermission?
  let deepLinkLabel: String?
  let priority: Int
  let availabilityCondition: @Sendable () -> Bool
  let builder: @Sendable (String) -> AnyView
  
  init(
    routeId: String,
    owningPluginId: String,
    title: String,
    iconName: String,
    presentation: MaxPluginRoutePresentation = .sheet,
    requiredPermission: PluginPermission? = nil,
    deepLinkLabel: String? = nil,
    priority: Int = 0,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable (String) -> AnyView
  ) {
    self.routeId = routeId
    self.owningPluginId = owningPluginId
    self.title = title
    self.iconName = iconName
    self.presentation = presentation
    self.requiredPermission = requiredPermission
    self.deepLinkLabel = deepLinkLabel
    self.priority = priority
    self.availabilityCondition = availabilityCondition
    self.builder = builder
  }
}

/// Represents a custom widget contribution rendered at target extension points.
struct PluginWidgetContribution: Identifiable, Sendable {
  var id: String { widgetId }
  let widgetId: String
  let owningPluginId: String
  let pointId: String
  let title: String
  let accessibilityLabel: String?
  let priority: Int
  let requiredPermission: PluginPermission?
  let availabilityCondition: @Sendable () -> Bool
  let builder: @Sendable () -> AnyView
  
  init(
    widgetId: String,
    owningPluginId: String,
    pointId: String,
    title: String,
    accessibilityLabel: String?,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable () -> AnyView
  ) {
    self.widgetId = widgetId
    self.owningPluginId = owningPluginId
    self.pointId = pointId
    self.title = title
    self.accessibilityLabel = accessibilityLabel
    self.priority = priority
    self.requiredPermission = requiredPermission
    self.availabilityCondition = availabilityCondition
    self.builder = builder
  }
}

/// Represents a triggerable action contribution.
struct PluginActionContribution: Identifiable, Sendable {
  var id: String { actionId }
  let actionId: String
  let owningPluginId: String
  let title: String
  let iconName: String
  let placement: PluginActionPlacement
  let priority: Int
  let requiredPermission: PluginPermission?
  let availabilityCondition: @Sendable () -> Bool
  let perform: @Sendable () async -> Void
  
  init(
    actionId: String,
    owningPluginId: String,
    title: String,
    iconName: String,
    placement: PluginActionPlacement,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    perform: @escaping @Sendable () async -> Void
  ) {
    self.actionId = actionId
    self.owningPluginId = owningPluginId
    self.title = title
    self.iconName = iconName
    self.placement = placement
    self.priority = priority
    self.requiredPermission = requiredPermission
    self.availabilityCondition = availabilityCondition
    self.perform = perform
  }
}


