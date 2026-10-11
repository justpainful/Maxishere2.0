import Foundation

struct MaxConfiguration: Hashable, Sendable {
  let baseURL: URL
  let websocketURL: URL?

  init(baseURL: URL, websocketURL: URL? = nil) throws {
    guard Self.isValidHTTPURL(baseURL) else {
      throw MaxConfigurationError.invalidBaseURL
    }
    if let websocketURL, !Self.isValidWebSocketURL(websocketURL) {
      throw MaxConfigurationError.invalidWebSocketURL
    }

    self.baseURL = Self.normalizedOrigin(baseURL)
    self.websocketURL = websocketURL.map(Self.normalizedWebSocketURL)
      ?? Self.derivedWebSocketURL(from: self.baseURL)
  }

  static func fromBundle(
    defaults: UserDefaults = .standard,
    bundle: Bundle = .main
  ) -> MaxConfiguration {
    // A server address the user typed into Settings is authoritative and is
    // honoured verbatim. Only the build-time default is screened for a retired
    // quick tunnel, because a bundled tunnel outlives the tunnel itself.
    let savedBase = defaults.string(forKey: "vault_baseURL")
    let bundleBase = bundle.object(forInfoDictionaryKey: "MAX_API_BASE_URL") as? String
    let savedBaseURL = savedBase.flatMap { validHTTPURL(from: $0) }
    let bundleBaseURL: URL? = {
      guard let bundleBase, let url = validHTTPURL(from: bundleBase) else { return nil }
      return isRetiredDefaultTunnel(url) ? nil : url
    }()
    let baseURL = savedBaseURL ?? bundleBaseURL ?? productionBaseURL

    let savedWebSocket = defaults.string(forKey: "vault_wsURL")
    let bundleWebSocket = bundle.object(forInfoDictionaryKey: "MAX_WS_URL") as? String
    let savedWebSocketURL = savedWebSocket.flatMap { validWebSocketURL(from: $0) }
    let bundleWebSocketURL: URL? = {
      guard let bundleWebSocket, let url = validWebSocketURL(from: bundleWebSocket) else { return nil }
      return isRetiredDefaultTunnel(url) ? nil : url
    }()
    // When the user chose the origin themselves, a websocket URL bundled for a
    // different deployment must not leak through: leaving it nil makes `init`
    // derive the realtime origin from the origin the user actually authorized.
    let websocketURL = savedWebSocketURL ?? (savedBaseURL == nil ? bundleWebSocketURL : nil)

    do {
      return try MaxConfiguration(baseURL: baseURL, websocketURL: websocketURL)
    } catch {
      // The production origin is constructed from URLComponents below and is
      // always valid. Keep a non-throwing app bootstrap without force unwraps.
      return MaxConfiguration.uncheckedProductionConfiguration()
    }
  }

  static func validHTTPURL(from value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed), isValidHTTPURL(url) else {
      return nil
    }
    return normalizedOrigin(url)
  }

  static func validWebSocketURL(from value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed),
          isValidWebSocketURL(url) else {
      return nil
    }
    return normalizedWebSocketURL(url)
  }

  static func isValidRemoteMediaURL(_ url: URL) -> Bool {
    isValidHTTPURL(url)
  }

  /// Whether `host` belongs to the Max deployment the app is talking to.
  ///
  /// Presigned media URLs are rewritten onto — and authenticated against — the
  /// configured origin only when this returns true. The configured origin always
  /// matches, so the allowlist follows the server the user selected instead of
  /// going stale. Extra origins (a CDN, a reverse proxy, a tunnel) are added at
  /// build time through the comma separated `MAX_BACKEND_HOSTS` bundle key; an
  /// entry beginning with `.` matches any subdomain of that suffix.
  static func isBackendHost(_ host: String?, baseURL: URL) -> Bool {
    guard let host = host?.lowercased(), !host.isEmpty else { return false }
    if let baseHost = baseURL.host?.lowercased(), host == baseHost { return true }
    if isLoopbackHost(host) { return true }
    return backendHostPatterns.contains { pattern in
      pattern.hasPrefix(".") ? host.hasSuffix(pattern) : host == pattern
    }
  }

  private static let backendHostPatterns: [String] = {
    let configured = (Bundle.main.object(forInfoDictionaryKey: "MAX_BACKEND_HOSTS") as? String)?
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty } ?? []
    return defaultBackendHostPatterns + configured
  }()

  private static let defaultBackendHostPatterns: [String] = [
    "archivedata.shop",
    ".archivedata.shop",
    ".lhr.life",
    ".trycloudflare.com",
  ]

  /// Fallback origin for a build that ships without `MAX_API_BASE_URL`.
  /// It must be a stable domain: a quick tunnel here dies with its process and
  /// strands every installed copy of the app.
  private static var productionBaseURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "archivedata.shop"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  private static func isRetiredDefaultTunnel(_ url: URL) -> Bool {
    // trycloudflare assigns temporary hostnames. Persisting one causes a
    // released app to keep calling a vanished API after the tunnel closes.
    // A production build must receive a stable HTTPS origin from its plist or
    // a user-provided server setting instead.
    url.host?.lowercased().hasSuffix(".trycloudflare.com") == true
  }

  private static func uncheckedProductionConfiguration() -> MaxConfiguration {
    let baseURL = productionBaseURL
    return MaxConfiguration(
      validatedBaseURL: baseURL,
      validatedWebSocketURL: derivedWebSocketURL(from: baseURL)
    )
  }

  private init(validatedBaseURL: URL, validatedWebSocketURL: URL?) {
    self.baseURL = validatedBaseURL
    self.websocketURL = validatedWebSocketURL
  }

  private static func isValidHTTPURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          let host = url.host,
          !host.isEmpty,
          url.user == nil,
          url.password == nil,
          url.fragment == nil else {
      return false
    }
    return scheme == "https" || (scheme == "http" && isLoopbackHost(host))
  }

  private static func isValidWebSocketURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          let host = url.host,
          !host.isEmpty,
          url.user == nil,
          url.password == nil,
          url.query == nil,
          url.fragment == nil else {
      return false
    }
    return scheme == "wss" || (scheme == "ws" && isLoopbackHost(host))
  }

  private static func isLoopbackHost(_ host: String) -> Bool {
    let normalized = host.lowercased()
    return normalized == "localhost" || normalized == "::1" || normalized.hasPrefix("127.")
  }

  private static func normalizedOrigin(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url ?? url
  }

  private static func normalizedWebSocketURL(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url ?? url
  }

  private static func derivedWebSocketURL(from baseURL: URL) -> URL? {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    switch components.scheme?.lowercased() {
    case "https": components.scheme = "wss"
    case "http": components.scheme = "ws"
    default: return nil
    }
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url
  }
}

enum MaxConfigurationError: Error, LocalizedError, Sendable {
  case invalidBaseURL
  case invalidWebSocketURL

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL:
      String(localized: "error.config.invalid_base_url")
    case .invalidWebSocketURL:
      String(localized: "error.config.invalid_websocket_url")
    }
  }
}
// Triggering full build for IPA extraction

extension URL {
  func resolved(against baseURL: URL) -> URL {
    var targetURL = self
    // Single source of truth for "this URL belongs to our backend"; see
    // MaxConfiguration.isBackendHost. Keeping the list here in sync by hand is
    // what let the app go on rewriting onto a dead tunnel.
    // Only paths the API actually routes are rewritten. A presigned URL that
    // points straight at object storage has a path like /<bucket>/<key>, which
    // the API serves under /storage/... and nowhere else — rewriting its origin
    // produced a URL that 404s on every request.
    if MaxConfiguration.isBackendHost(self.host, baseURL: baseURL),
       self.path.hasPrefix("/storage/") || self.path.hasPrefix("/api/") || self.path.hasPrefix("/media/") || self.path.hasPrefix("/uploads/") {
       if var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) {
           comps.scheme = baseURL.scheme
           comps.host = baseURL.host
           // Adopt the base URL's port only when it states one. Assigning it
           // unconditionally deleted the port of a direct object-storage URL —
           // http://127.0.0.1:59000/... became https://host/... — and the
           // request then went somewhere that does not serve the object.
           if let port = baseURL.port {
               comps.port = port
           }
           if let rewritten = comps.url {
               targetURL = rewritten
           }
       }
    }
    guard targetURL.scheme == nil || targetURL.host == nil else { return targetURL }
    return URL(string: targetURL.absoluteString, relativeTo: baseURL)?.absoluteURL ?? targetURL
  }
}
