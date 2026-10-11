import Foundation
import Security

protocol SessionTokenStore: Sendable {
  func loadToken() throws -> String?
  func loadRefreshToken() throws -> String?
  func saveCredentials(_ credentials: SessionCredentials) throws
  func clearToken() throws
}

struct SessionCredentials: Codable, Hashable, Sendable {
  let accessToken: String
  let refreshToken: String
}

struct KeychainSessionStore: SessionTokenStore {
  let service: String
  private let account = "max_v2_session"
  private let legacyAccount = "vault_session"

  func loadToken() throws -> String? {
    if let credentials = try loadCredentials() { return credentials.accessToken }
    return try loadString(account: legacyAccount)
  }

  func loadRefreshToken() throws -> String? {
    try loadCredentials()?.refreshToken
  }

  func saveCredentials(_ credentials: SessionCredentials) throws {
    guard !credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !credentials.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KeychainError(status: errSecParam)
    }
    let data = try JSONEncoder().encode(credentials)
    try replace(data: data, account: account)
    _ = SecItemDelete(query(account: legacyAccount) as CFDictionary)
  }

  func clearToken() throws {
    for account in [account, legacyAccount] {
      let status = SecItemDelete(query(account: account) as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound {
        throw KeychainError(status: status)
      }
    }
  }

  private func loadCredentials() throws -> SessionCredentials? {
    guard let data = try loadData(account: account) else { return nil }
    do {
      return try JSONDecoder().decode(SessionCredentials.self, from: data)
    } catch {
      throw KeychainError(status: errSecDecode)
    }
  }

  private func loadString(account: String) throws -> String? {
    guard let data = try loadData(account: account) else { return nil }
    guard let value = String(data: data, encoding: .utf8) else {
      throw KeychainError(status: errSecDecode)
    }
    return value
  }

  private func loadData(account: String) throws -> Data? {
    var query = query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = item as? Data else { throw KeychainError(status: errSecDecode) }
    return data
  }

  private func replace(data: Data, account: String) throws {
    _ = SecItemDelete(query(account: account) as CFDictionary)
    var item = query(account: account)
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  private func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

struct KeychainError: Error, LocalizedError {
  let status: OSStatus
  var errorDescription: String? { String(localized: "error.keychain") }
}

final class EphemeralSessionTokenStore: SessionTokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var credentials: SessionCredentials?

  func loadToken() throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return credentials?.accessToken
  }

  func loadRefreshToken() throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return credentials?.refreshToken
  }

  func saveCredentials(_ credentials: SessionCredentials) throws {
    lock.lock()
    defer { lock.unlock() }
    self.credentials = credentials
  }

  func clearToken() throws {
    lock.lock()
    defer { lock.unlock() }
    credentials = nil
  }
}
