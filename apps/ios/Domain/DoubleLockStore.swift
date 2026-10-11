import Foundation
import LocalAuthentication
import Observation

enum DoubleLockTimeout: Int, Codable, CaseIterable, Identifiable, Sendable {
  case immediately = 0
  case oneMinute = 60
  case fiveMinutes = 300
  case fifteenMinutes = 900
  case oneHour = 3_600

  var id: Int { rawValue }
  var duration: TimeInterval { TimeInterval(rawValue) }
}

enum DoubleLockPhase: String, Sendable {
  case disabled
  case locked
  case unlocked
  case authenticating
}

enum DoubleLockBiometry: String, Sendable {
  case none
  case faceID
  case touchID
}

enum DoubleLockFailure: Hashable, Sendable {
  case invalidPIN
  case invalidPINFormat
  case biometricsCancelled
  case biometricsUnavailable
  case biometricsFailed
  case storage

  var message: String {
    switch self {
    case .invalidPIN:
      String(localized: "double_lock.error.invalid_pin")
    case .invalidPINFormat:
      String(localized: "double_lock.error.invalid_format")
    case .biometricsCancelled:
      String(localized: "double_lock.error.biometric_cancelled")
    case .biometricsUnavailable:
      String(localized: "double_lock.error.biometric_unavailable")
    case .biometricsFailed:
      String(localized: "double_lock.error.biometric_failed")
    case .storage:
      String(localized: "double_lock.error.storage")
    }
  }
}

@MainActor
@Observable
final class DoubleLockStore {
  private enum Key {
    static let enabled = "app.max.doubleLock.enabled"
    static let biometricsEnabled = "app.max.doubleLock.biometricsEnabled"
    static let timeout = "app.max.doubleLock.timeout"
  }

  @ObservationIgnored private let credentialStore: any DoubleLockCredentialStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let contextFactory: () -> LAContext
  @ObservationIgnored private var backgroundedAt: Date?

  private(set) var phase: DoubleLockPhase
  private(set) var failure: DoubleLockFailure?
  private(set) var biometry: DoubleLockBiometry = .none
  private(set) var isTestBypassActive: Bool

  private(set) var isEnabled: Bool {
    didSet { defaults.set(isEnabled, forKey: Key.enabled) }
  }

  private(set) var biometricsEnabled: Bool {
    didSet { defaults.set(biometricsEnabled, forKey: Key.biometricsEnabled) }
  }

  var lockTimeout: DoubleLockTimeout {
    didSet { defaults.set(lockTimeout.rawValue, forKey: Key.timeout) }
  }

  init(
    credentialStore: any DoubleLockCredentialStore = KeychainDoubleLockCredentialStore(
      service: "app.max.iphone"
    ),
    defaults: UserDefaults = .standard,
    contextFactory: @escaping () -> LAContext = { LAContext() },
    testBypassOverride: Bool? = nil
  ) {
    let enabled = defaults.bool(forKey: Key.enabled)
    let biometricsEnabled = defaults.bool(forKey: Key.biometricsEnabled)
    let savedTimeout = defaults.object(forKey: Key.timeout) as? NSNumber
    let lockTimeout = savedTimeout
      .flatMap { DoubleLockTimeout(rawValue: $0.intValue) } ?? .oneMinute
    let testBypassActive = Self.resolveTestBypass(override: testBypassOverride)

    self.credentialStore = credentialStore
    self.defaults = defaults
    self.contextFactory = contextFactory
    self.isEnabled = enabled
    self.biometricsEnabled = biometricsEnabled
    self.lockTimeout = lockTimeout
    self.isTestBypassActive = testBypassActive
    self.phase = enabled && !testBypassActive ? .locked : .disabled

    if self.isEnabled && self.isTestBypassActive {
      self.phase = .unlocked
    }

    do {
      if self.isEnabled, try credentialStore.loadMaterial() == nil {
        self.isEnabled = false
        self.biometricsEnabled = false
        defaults.set(false, forKey: Key.enabled)
        defaults.set(false, forKey: Key.biometricsEnabled)
        self.phase = .disabled
        self.failure = .storage
      }
    } catch {
      self.phase = self.isEnabled ? .locked : .disabled
      self.failure = .storage
    }

    refreshBiometricAvailability()
  }

  var isLocked: Bool {
    isEnabled && phase != .unlocked
  }

  var isAuthenticating: Bool {
    phase == .authenticating
  }

  var userVisibleError: String? {
    failure?.message
  }

  @discardableResult
  func configure(pin: String, enableBiometrics: Bool) async -> Bool {
    guard Self.isValidPIN(pin) else {
      failure = .invalidPINFormat
      return false
    }

    refreshBiometricAvailability()
    phase = .authenticating
    failure = nil
    do {
      let material = try await Task.detached(priority: .userInitiated) {
        try DoubleLockHasher.makeMaterial(pin: pin)
      }.value
      try credentialStore.saveMaterial(material)
      isEnabled = true
      biometricsEnabled = enableBiometrics && biometry != .none
      phase = .unlocked
      if enableBiometrics && biometry == .none {
        failure = .biometricsUnavailable
      }
      return true
    } catch {
      isEnabled = false
      biometricsEnabled = false
      phase = .disabled
      failure = .storage
      return false
    }
  }

  @discardableResult
  func unlock(pin: String) async -> Bool {
    guard isEnabled else {
      phase = .disabled
      return true
    }
    if isTestBypassActive {
      completeUnlock()
      return true
    }
    guard !isAuthenticating else { return false }
    guard Self.isValidPIN(pin) else {
      failLocked(with: .invalidPINFormat)
      return false
    }

    phase = .authenticating
    failure = nil
    do {
      guard let material = try credentialStore.loadMaterial() else {
        failLocked(with: .storage)
        return false
      }
      let matches = await Task.detached(priority: .userInitiated) {
        DoubleLockHasher.verify(pin: pin, material: material)
      }.value
      guard matches else {
        failLocked(with: .invalidPIN)
        return false
      }
      completeUnlock()
      return true
    } catch {
      failLocked(with: .storage)
      return false
    }
  }

  @discardableResult
  func unlockWithBiometrics(
    reason: String = "Unlock Max"
  ) async -> Bool {
    guard isEnabled else {
      phase = .disabled
      return true
    }
    if isTestBypassActive {
      completeUnlock()
      return true
    }
    guard biometricsEnabled else {
      failLocked(with: .biometricsUnavailable)
      return false
    }
    guard !isAuthenticating else { return false }

    let context = contextFactory()
    context.localizedCancelTitle = "Use PIN"
    var evaluationError: NSError?
    guard context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &evaluationError
    ) else {
      failLocked(with: .biometricsUnavailable)
      return false
    }
    if context.biometryType == .faceID,
       !Self.hasFaceIDUsageDescription {
      failLocked(with: .biometricsUnavailable)
      return false
    }

    phase = .authenticating
    failure = nil
    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      )
      guard success else {
        failLocked(with: .biometricsFailed)
        return false
      }
      completeUnlock()
      return true
    } catch {
      failLocked(with: Self.biometricFailure(for: error))
      return false
    }
  }

  @discardableResult
  func disable(pin: String) async -> Bool {
    if isEnabled && !isTestBypassActive {
      guard await unlock(pin: pin) else { return false }
    }

    do {
      try credentialStore.clearMaterial()
      isEnabled = false
      biometricsEnabled = false
      backgroundedAt = nil
      phase = .disabled
      failure = nil
      return true
    } catch {
      failure = .storage
      return false
    }
  }

  @discardableResult
  func changePIN(currentPIN: String, newPIN: String) async -> Bool {
    guard Self.isValidPIN(newPIN) else {
      failure = .invalidPINFormat
      return false
    }
    guard await unlock(pin: currentPIN) else { return false }

    do {
      let material = try await Task.detached(priority: .userInitiated) {
        try DoubleLockHasher.makeMaterial(pin: newPIN)
      }.value
      try credentialStore.saveMaterial(material)
      completeUnlock()
      return true
    } catch {
      failure = .storage
      return false
    }
  }

  func setBiometricsEnabled(_ enabled: Bool) {
    refreshBiometricAvailability()
    guard !enabled || biometry != .none else {
      biometricsEnabled = false
      failure = .biometricsUnavailable
      return
    }
    biometricsEnabled = enabled
    failure = nil
  }

  func refreshBiometricAvailability() {
    let context = contextFactory()
    var error: NSError?
    guard context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &error
    ) else {
      biometry = .none
      return
    }
    switch context.biometryType {
    case .faceID:
      biometry = Self.hasFaceIDUsageDescription ? .faceID : .none
    case .touchID:
      biometry = .touchID
    case .opticID:
      biometry = .none
    case .none:
      biometry = .none
    @unknown default:
      biometry = .none
    }
  }

  func lock() {
    guard isEnabled, !isTestBypassActive else { return }
    phase = .locked
    failure = nil
  }

  func clearFailure() {
    failure = nil
    if isEnabled && phase != .unlocked {
      phase = .locked
    }
  }

  func sceneWillResignActive(at date: Date = Date()) {
    guard isEnabled else { return }
    backgroundedAt = backgroundedAt ?? date
    if lockTimeout == .immediately {
      lock()
    }
  }

  func sceneDidEnterBackground(at date: Date = Date()) {
    guard isEnabled else { return }
    backgroundedAt = backgroundedAt ?? date
    if lockTimeout == .immediately {
      lock()
    }
  }

  func sceneDidBecomeActive(at date: Date = Date()) {
    guard isEnabled, !isTestBypassActive else {
      backgroundedAt = nil
      return
    }
    defer { backgroundedAt = nil }
    guard let backgroundedAt else { return }
    if date.timeIntervalSince(backgroundedAt) >= lockTimeout.duration {
      lock()
    }
  }

  private func completeUnlock() {
    phase = .unlocked
    failure = nil
    backgroundedAt = nil
  }

  private func failLocked(with failure: DoubleLockFailure) {
    phase = .locked
    self.failure = failure
  }

  private static func isValidPIN(_ pin: String) -> Bool {
    (4...12).contains(pin.count) && pin.allSatisfy(\.isNumber)
  }

  private static func biometricFailure(for error: Error) -> DoubleLockFailure {
    let nsError = error as NSError
    guard nsError.domain == LAError.errorDomain,
          let code = LAError.Code(rawValue: nsError.code) else {
      return .biometricsFailed
    }

    switch code {
    case .userCancel, .appCancel, .systemCancel, .userFallback:
      return .biometricsCancelled
    case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
      return .biometricsUnavailable
    default:
      return .biometricsFailed
    }
  }

  private static var hasFaceIDUsageDescription: Bool {
    let value = Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String
    return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  private static func resolveTestBypass(override: Bool?) -> Bool {
    #if DEBUG
    if let override { return override }
    let process = ProcessInfo.processInfo
    return process.arguments.contains("-MaxUITestMode")
      && process.environment["MAX_UI_TEST_DOUBLE_LOCK_BYPASS"] == "1"
    #else
    return false
    #endif
  }
}
