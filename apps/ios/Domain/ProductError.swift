import Foundation

enum ProductArea: String, Codable, Hashable, Sendable {
  case account
  case vault
  case library
  case ratings
  case player
  case transfers
  case chats
  case shared
  case profile
  case memories
  case watch
}

enum ProductErrorCode: String, Codable, Hashable, Sendable {
  case offline
  case serverUnavailable = "server_unavailable"
  case sessionExpired = "session_expired"
  case accessDenied = "access_denied"
  case notFound = "not_found"
  case expiredMediaURL = "expired_media_url"
  case invalidResponse = "invalid_response"
  case downloadFailed = "download_failed"
  case insufficientStorage = "insufficient_storage"
  case ratingSaveFailed = "rating_save_failed"
  case uploadFailed = "upload_failed"
  case profileUpdateFailed = "profile_update_failed"
  case unknown
}

/// A security-safe, user-facing error that keeps support context structured and expandable.
struct ProductError: Error, Identifiable, Hashable, Sendable {
  let id: UUID
  let area: ProductArea
  let code: ProductErrorCode
  let title: String
  let reason: String
  let recoverySuggestion: String?
  let httpStatus: Int?
  let requestID: String?
  let occurredAt: Date

  init(
    id: UUID = UUID(),
    area: ProductArea,
    code: ProductErrorCode,
    title: String,
    reason: String,
    recoverySuggestion: String? = nil,
    httpStatus: Int? = nil,
    requestID: String? = nil,
    occurredAt: Date = Date()
  ) {
    self.id = id
    self.area = area
    self.code = code
    self.title = title
    self.reason = reason
    self.recoverySuggestion = recoverySuggestion
    self.httpStatus = httpStatus
    self.requestID = requestID
    self.occurredAt = occurredAt
  }

  var supportDetails: String {
    var lines = [
      "Area: \(area.rawValue)",
      "Code: \(code.rawValue)",
      "Time: \(occurredAt.ISO8601Format())",
      "Environment: \(Self.safeEnvironmentName)",
    ]
    if let httpStatus { lines.append("HTTP: \(httpStatus)") }
    if let requestID, Self.isSafeIdentifier(requestID) {
      lines.append("Request: \(requestID)")
    }
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String {
      lines.append("App: \(version)")
    }
    return lines.joined(separator: "\n")
  }

  static func from(
    _ error: Error,
    area: ProductArea,
    fallback: ProductErrorCode = .unknown
  ) -> ProductError {
    if let productError = error as? ProductError { return productError }
    if let apiError = error as? MaxAPIError {
      switch apiError {
      case .invalidURL, .invalidResponse:
        return ProductError(
          area: area,
          code: .invalidResponse,
          title: String(localized: "error.product.invalid_response.title"),
          reason: String(localized: "error.product.invalid_response.reason"),
          recoverySuggestion: String(localized: "error.product.retry")
        )
      case .invalidProfileImage:
        return ProductError(
          area: .profile,
          code: .profileUpdateFailed,
          title: String(localized: "error.product.profile_image.title"),
          reason: String(localized: "error.product.profile_image.reason"),
          recoverySuggestion: String(localized: "error.product.profile_image.recovery")
        )
      case .unauthorized(let status, _):
        return ProductError(
          area: area,
          code: status == 403 ? .accessDenied : .sessionExpired,
          title: status == 403
            ? String(localized: "error.product.access_denied.title")
            : String(localized: "error.product.session_expired.title"),
          reason: status == 403
            ? String(localized: "error.product.access_denied.reason")
            : String(localized: "error.product.session_expired.reason"),
          recoverySuggestion: status == 403
            ? String(localized: "error.product.back")
            : String(localized: "error.product.sign_in"),
          httpStatus: status
        )
      case .server(let status, _):
        let code: ProductErrorCode
        switch status {
        case 404: code = .notFound
        case 410: code = .expiredMediaURL
        default: code = .serverUnavailable
        }
        return ProductError(
          area: area,
          code: code,
          title: code.title,
          reason: code.reason,
          recoverySuggestion: String(localized: "error.product.retry"),
          httpStatus: status
        )
      }
    }
    if let urlError = error as? URLError {
      let code: ProductErrorCode = urlError.code == .notConnectedToInternet
        ? .offline
        : .serverUnavailable
      return ProductError(
        area: area,
        code: code,
        title: code == .offline
          ? String(localized: "error.product.offline.title")
          : String(localized: "error.product.server.title"),
        reason: code == .offline
          ? String(localized: "error.product.offline.reason")
          : String(localized: "error.product.server.reason"),
        recoverySuggestion: String(localized: "error.product.retry")
      )
    }
    return ProductError(
      area: area,
      code: fallback,
      title: String(localized: "error.product.action.title"),
      reason: String(localized: "error.product.action.reason"),
      recoverySuggestion: String(localized: "error.product.retry")
    )
  }

  private static func isSafeIdentifier(_ value: String) -> Bool {
    guard value.count <= 96 else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0)
    }
  }

  private static var safeEnvironmentName: String {
    let process = ProcessInfo.processInfo
    if process.environment["MAX_DEMO_MODE"] == "1"
        || process.arguments.contains("-MAX_DEMO_MODE") {
      return "Demo"
    }
    #if DEBUG
    return "Debug"
    #else
    return "Release"
    #endif
  }
}

private extension ProductErrorCode {
  var title: String {
    switch self {
    case .notFound:
      String(localized: "error.product.not_found.title")
    case .expiredMediaURL:
      String(localized: "error.product.expired_media_url.title")
    default:
      String(localized: "error.product.server.title")
    }
  }

  var reason: String {
    switch self {
    case .notFound:
      String(localized: "error.product.not_found.reason")
    case .expiredMediaURL:
      String(localized: "error.product.expired_media_url.reason")
    default:
      String(localized: "error.product.server.reason")
    }
  }
}

extension ProductError: LocalizedError {
  var errorDescription: String? { reason }
}
