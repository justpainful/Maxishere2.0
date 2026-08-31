import Foundation
import Observation
import Security

/// One signed-in identity kept in the account vault so switching needs no
/// password. The tokens are a snapshot of that account's session at the moment
/// it was last active; the active session's keychain entry stays authoritative
/// and the vault copy is refreshed on every successful bootstrap and on every
/// switch away.
struct StoredAccount: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var displayName: String
  var username: String?
  var accessToken: String
  var refreshToken: String
  var addedAt: Date
}

/// The keychain-backed vault behind fast account switching. A single keychain
/// entry (beside the active session's own) holds the JSON array of every
/// signed-in account, capped at six — the switcher UI reads this store, and
/// `MaxAppModel` writes it around sign-in, switch and sign-out.
@MainActor
@Observable
final class MultiAccountStore {
  static let maximumAccounts = 6

  @ObservationIgnored private let keychain: AccountVaultKeychain

  private(set) var accounts: [StoredAccount]

  init(service: String = "app.max.iphone") {
    let keychain = AccountVaultKeychain(service: service)
    self.keychain = keychain
    self.accounts = (try? keychain.load()) ?? []
  }

  func account(id: String) -> StoredAccount? {
    accounts.first { $0.id == id }
  }

  /// Inserts or refreshes one account. An existing row keeps its position and
  /// its original `addedAt`; a new row lands at the end, refused past the cap.
  func upsert(user: MaxUser, credentials: SessionCredentials) {
    let account = StoredAccount(
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      accessToken: credentials.accessToken,
      refreshToken: credentials.refreshToken,
      addedAt: accounts.first(where: { $0.id == user.id })?.addedAt ?? Date()
    )
    var next = accounts
    if let index = next.firstIndex(where: { $0.id == user.id }) {
      next[index] = account
    } else {
      guard next.count < Self.maximumAccounts else { return }
      next.append(account)
    }
    persist(next)
  }

  /// Drops one account from the vault (signing out removes its saved tokens).
  func remove(accountID: String) {
    let next = accounts.filter { $0.id != accountID }
    guard next.count != accounts.count else { return }
    persist(next)
  }

  private func persist(_ next: [StoredAccount]) {
    accounts = next
    try? keychain.save(next)
  }
}

/// Minimal keychain CRUD for the vault's single JSON entry. Deliberately a
/// sibling of `KeychainSessionStore` rather than a client of it: the session
/// store's helpers are private, and the two entries have different lifetimes.
struct AccountVaultKeychain: Sendable {
  let service: String
  private let account = "max_v2_account_vault"

  func load() throws -> [StoredAccount] {
    var query = query()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = item as? Data else { throw KeychainError(status: errSecDecode) }
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode([StoredAccount].self, from: data)
    } catch {
      throw KeychainError(status: errSecDecode)
    }
  }

  func save(_ accounts: [StoredAccount]) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(accounts)
    _ = SecItemDelete(query() as CFDictionary)
    var item = query()
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  private func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}
