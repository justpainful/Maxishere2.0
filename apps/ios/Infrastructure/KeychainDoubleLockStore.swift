import CryptoKit
import Foundation
import Security

struct DoubleLockVerificationMaterial: Codable, Hashable, Sendable {
  let salt: Data
  let digest: Data
  let rounds: Int
}

protocol DoubleLockCredentialStore: Sendable {
  func loadMaterial() throws -> DoubleLockVerificationMaterial?
  func saveMaterial(_ material: DoubleLockVerificationMaterial) throws
  func clearMaterial() throws
}

struct KeychainDoubleLockCredentialStore: DoubleLockCredentialStore {
  let service: String
  private let account = "double_lock_verification_v1"

  func loadMaterial() throws -> DoubleLockVerificationMaterial? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = item as? Data else { throw DoubleLockCredentialError.invalidMaterial }

    do {
      return try JSONDecoder().decode(DoubleLockVerificationMaterial.self, from: data)
    } catch {
      throw DoubleLockCredentialError.invalidMaterial
    }
  }

  func saveMaterial(_ material: DoubleLockVerificationMaterial) throws {
    let data = try JSONEncoder().encode(material)
    var attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainError(status: updateStatus)
    }

    attributes.merge(baseQuery) { current, _ in current }
    let addStatus = SecItemAdd(attributes as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
  }

  func clearMaterial() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError(status: status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

enum DoubleLockCredentialError: Error, LocalizedError, Sendable {
  case invalidMaterial
  case randomGenerationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidMaterial:
      String(localized: "error.double_lock.invalid_material")
    case .randomGenerationFailed:
      String(localized: "error.double_lock.secure_data_creation_failed")
    }
  }
}

enum DoubleLockHasher {
  private static let currentRounds = 50_000
  private static let saltByteCount = 32

  static func makeMaterial(pin: String) throws -> DoubleLockVerificationMaterial {
    var saltBytes = [UInt8](repeating: 0, count: saltByteCount)
    let status = saltBytes.withUnsafeMutableBytes {
      (buffer: UnsafeMutableRawBufferPointer) -> OSStatus in
      guard let baseAddress = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
    }
    guard status == errSecSuccess else {
      throw DoubleLockCredentialError.randomGenerationFailed(status)
    }

    let salt = Data(saltBytes)
    return DoubleLockVerificationMaterial(
      salt: salt,
      digest: digest(pin: pin, salt: salt, rounds: currentRounds),
      rounds: currentRounds
    )
  }

  static func verify(pin: String, material: DoubleLockVerificationMaterial) -> Bool {
    guard material.salt.count >= 16,
          material.digest.count == SHA256.Digest.byteCount,
          (1...250_000).contains(material.rounds) else {
      return false
    }

    let candidate = digest(pin: pin, salt: material.salt, rounds: material.rounds)
    return constantTimeEqual(candidate, material.digest)
  }

  private static func digest(pin: String, salt: Data, rounds: Int) -> Data {
    var input = Data()
    input.reserveCapacity(salt.count + pin.utf8.count)
    input.append(salt)
    input.append(contentsOf: pin.utf8)
    var value = Data(SHA256.hash(data: input))

    if rounds > 1 {
      for _ in 1..<rounds {
        var next = Data()
        next.reserveCapacity(salt.count + value.count)
        next.append(salt)
        next.append(value)
        value = Data(SHA256.hash(data: next))
      }
    }
    return value
  }

  private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) {
      difference |= left ^ right
    }
    return difference == 0
  }
}
