import Foundation
import SwiftUI

/// Thread-safe helper list for tracking items across threads safely.
private final class SafeList<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [T] = []

  func append(_ item: T) {
    lock.lock()
    items.append(item)
    lock.unlock()
  }

  func removeAll() {
    lock.lock()
    items.removeAll()
    lock.unlock()
  }

  var all: [T] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

protocol PluginScopedStorageAPI: Sendable {
  func set(_ value: Any?, forKey key: String)
  func string(forKey key: String) -> String?
  func bool(forKey key: String) -> Bool
  func integer(forKey key: String) -> Int
  func double(forKey key: String) -> Double
  func removeObject(forKey key: String)
  func clearAll()
}

protocol PluginNetworkAPI: Sendable {
  func request(_ url: URL) async throws -> Data
  func getDiagnosticHistory() -> [String]
}

protocol PluginHapticsAPI: Sendable {
  func triggerImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle)
  func triggerNotification(_ type: UINotificationFeedbackGenerator.FeedbackType)
}

protocol PluginLoggingAPI: Sendable {
  func log(_ message: String, level: String)
}

private func pluginNetworkHostAllowed(_ url: URL, allowedDomains: Set<String>) -> Bool {
  guard url.scheme?.lowercased() == "https",
        url.user == nil,
        url.password == nil,
        let host = url.host?.lowercased(),
        !host.isEmpty,
        host != "localhost",
        !host.hasSuffix(".localhost"),
        !host.hasSuffix(".local"),
        !host.hasSuffix(".internal"),
        !host.contains(":"),
        host.range(
          of: "^[0-9]{1,3}(?:\\.[0-9]{1,3}){3}$",
          options: .regularExpression
        ) == nil else {
    return false
  }
  return allowedDomains.contains(host) || allowedDomains.contains { domain in
    host.hasSuffix("." + domain)
  }
}

private func pluginNetworkDiagnosticOrigin(_ url: URL) -> String {
  var components = URLComponents()
  components.scheme = url.scheme?.lowercased()
  components.host = url.host?.lowercased()
  components.port = url.port
  return components.string ?? "invalid-url"
}

private final class PluginNetworkRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let allowedDomains: Set<String>

  init(allowedDomains: Set<String>) {
    self.allowedDomains = allowedDomains
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let url = request.url,
          pluginNetworkHostAllowed(url, allowedDomains: allowedDomains) else {
      completionHandler(nil)
      return
    }
    var sanitized = request
    sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
    sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
    completionHandler(sanitized)
  }
}

final class PluginRouteRegistry: Sendable {
  let pluginId: String

  init(pluginId: String) {
    self.pluginId = pluginId
  }

  @MainActor
  func register(
    id: String,
    title: String,
    iconName: String,
    presentation: MaxPluginRoutePresentation = .sheet,
    requiredPermission: PluginPermission? = nil,
    deepLinkLabel: String? = nil,
    priority: Int = 0,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable (String) -> AnyView
  ) {
    PluginStore.shared.registerRoute(
      pluginId: pluginId,
      routeId: id,
      title: title,
      iconName: iconName,
      presentation: presentation,
      requiredPermission: requiredPermission,
      deepLinkLabel: deepLinkLabel,
      priority: priority,
      availabilityCondition: availabilityCondition,
      builder: builder
    )
  }
}

final class PluginWidgetRegistry: Sendable {
  let pluginId: String

  init(pluginId: String) {
    self.pluginId = pluginId
  }

  @MainActor
  func register(
    id: String,
    pointId: String,
    title: String,
    accessibilityLabel: String? = nil,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    builder: @escaping @Sendable () -> AnyView
  ) {
    PluginStore.shared.registerWidget(
      pluginId: pluginId,
      widgetId: id,
      pointId: pointId,
      title: title,
      accessibilityLabel: accessibilityLabel,
      priority: priority,
      requiredPermission: requiredPermission,
      availabilityCondition: availabilityCondition,
      builder: builder
    )
  }
}

final class PluginActionRegistry: Sendable {
  let pluginId: String

  init(pluginId: String) {
    self.pluginId = pluginId
  }

  @MainActor
  func register(
    id: String,
    title: String,
    iconName: String,
    placement: PluginActionPlacement,
    priority: Int = 0,
    requiredPermission: PluginPermission? = nil,
    availabilityCondition: @escaping @Sendable () -> Bool = { true },
    perform: @escaping @Sendable () async -> Void
  ) {
    PluginStore.shared.registerAction(
      pluginId: pluginId,
      actionId: id,
      title: title,
      iconName: iconName,
      placement: placement,
      priority: priority,
      requiredPermission: requiredPermission,
      availabilityCondition: availabilityCondition,
      perform: perform
    )
  }
}

final class DefaultPluginScopedStorage: PluginScopedStorageAPI, @unchecked Sendable {
  private let defaults: UserDefaults
  private let pluginId: String
  private let prefix: String

  init(pluginId: String) {
    self.defaults = .standard
    self.pluginId = pluginId
    self.prefix = "app.max.plugin.\(pluginId)."
  }

  func set(_ value: Any?, forKey key: String) {
    defaults.set(value, forKey: prefix + key)
  }

  func string(forKey key: String) -> String? {
    defaults.string(forKey: prefix + key)
  }

  func bool(forKey key: String) -> Bool {
    defaults.bool(forKey: prefix + key)
  }

  func integer(forKey key: String) -> Int {
    defaults.integer(forKey: prefix + key)
  }

  func double(forKey key: String) -> Double {
    defaults.double(forKey: prefix + key)
  }

  func removeObject(forKey key: String) {
    defaults.removeObject(forKey: prefix + key)
  }

  func clearAll() {
    let allKeys = defaults.dictionaryRepresentation().keys
    for key in allKeys {
      if key.hasPrefix(prefix) {
        defaults.removeObject(forKey: key)
      }
    }
  }
}

final class DefaultPluginNetwork: PluginNetworkAPI, @unchecked Sendable {
  private let pluginId: String
  private let allowedDomains: Set<String>
  private let logger: any PluginLoggingAPI
  private let requestHistory = SafeList<String>()
  private let activeTasks = SafeList<Task<Data, Error>>()

  init(pluginId: String, allowedDomains: [String], logger: any PluginLoggingAPI) {
    self.pluginId = pluginId
    self.allowedDomains = Set(allowedDomains)
    self.logger = logger
  }

  func cancelAll() {
    let tasks = activeTasks.all
    for task in tasks {
      task.cancel()
    }
    activeTasks.removeAll()
  }

  func request(_ url: URL) async throws -> Data {
    guard let host = url.host?.lowercased() else {
      logger.log("Network request blocked: Invalid URL host", level: "error")
      throw URLError(.badURL)
    }

    guard pluginNetworkHostAllowed(url, allowedDomains: allowedDomains) else {
      let errorMsg = "Network request blocked: Domain '\(host)' not declared in manifest."
      logger.log(errorMsg, level: "error")
      requestHistory.append("BLOCKED: \(pluginNetworkDiagnosticOrigin(url))")
      throw URLError(.networkConnectionLost)
    }

    let redirectAllowedDomains = allowedDomains
    let fetchTask = Task<Data, Error> {
      #if os(iOS) || os(macOS)
      var request = URLRequest(url: url)
      request.timeoutInterval = 10.0 // timeout after 10s
      request.setValue(nil, forHTTPHeaderField: "Authorization")
      request.setValue(nil, forHTTPHeaderField: "Cookie")
      
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 10.0
      let redirectGuard = PluginNetworkRedirectGuard(allowedDomains: redirectAllowedDomains)
      let session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)

      let (bytes, _) = try await session.bytes(for: request)
      var data = Data()
      data.reserveCapacity(64 * 1024)
      for try await byte in bytes {
        guard data.count < 2 * 1024 * 1024 else {
          session.invalidateAndCancel()
          throw URLError(.dataLengthExceedsMaximum)
        }
        data.append(byte)
      }
      session.finishTasksAndInvalidate()
      return data
      #else
      // Windows simulation mock state
      try await Task.sleep(nanoseconds: 500_000_000)
      let mockJSON = "{\"status\":\"success\",\"host\":\"\(host)\",\"data\":{\"items\":[{\"id\":\"1\",\"title\":\"Mock Data Lab Item\"}]}}"
      return mockJSON.data(using: .utf8) ?? Data()
      #endif
    }

    activeTasks.append(fetchTask)
    
    do {
      let data = try await fetchTask.value
      requestHistory.append("ALLOWED: \(pluginNetworkDiagnosticOrigin(url))")
      return data
    } catch {
      let diagnostic = error as NSError
      requestHistory.append(
        "FAILED: \(pluginNetworkDiagnosticOrigin(url)) | Error: \(diagnostic.domain):\(diagnostic.code)"
      )
      throw error
    }
  }

  func getDiagnosticHistory() -> [String] {
    return requestHistory.all
  }
}

final class DefaultPluginHaptics: PluginHapticsAPI, @unchecked Sendable {
  init() {}

  func triggerImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    DispatchQueue.main.async {
      let generator = UIImpactFeedbackGenerator(style: style)
      generator.prepare()
      generator.impactOccurred()
    }
  }

  func triggerNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    DispatchQueue.main.async {
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(type)
    }
  }
}

final class DefaultPluginLogging: PluginLoggingAPI, @unchecked Sendable {
  private let pluginId: String

  init(pluginId: String) {
    self.pluginId = pluginId
  }

  func log(_ message: String, level: String) {
    #if DEBUG
    let entry = "[\(level.uppercased())] [Plugin: \(pluginId)] \(message)"
    print(entry)
    #endif
  }
}

final class MaxPluginContext: @unchecked Sendable {
  let pluginId: String
  let storage: any PluginScopedStorageAPI
  let haptics: any PluginHapticsAPI
  let logging: any PluginLoggingAPI
  let network: any PluginNetworkAPI
  
  // Scoped registration wrappers
  let routes: PluginRouteRegistry
  let widgets: PluginWidgetRegistry
  let actions: PluginActionRegistry

  // Environment bindings injected dynamically at runtime
  var navigation: (any MaxPluginNavigationProxy)?
  var library: (any MaxPluginLibraryProxy)?

  init(pluginId: String, allowedDomains: [String] = []) {
    self.pluginId = pluginId
    let logApi = DefaultPluginLogging(pluginId: pluginId)
    self.logging = logApi
    self.storage = DefaultPluginScopedStorage(pluginId: pluginId)
    self.haptics = DefaultPluginHaptics()
    self.routes = PluginRouteRegistry(pluginId: pluginId)
    self.widgets = PluginWidgetRegistry(pluginId: pluginId)
    self.actions = PluginActionRegistry(pluginId: pluginId)
    self.network = DefaultPluginNetwork(pluginId: pluginId, allowedDomains: allowedDomains, logger: logApi)
  }

  func deactivate() {
    if let defaultNet = network as? DefaultPluginNetwork {
      defaultNet.cancelAll()
    }
  }
}


