import Foundation
import LocalAuthentication
import Observation

/// Client-side per-conversation lock. Purely a privacy screen on this device:
/// the locked set lives in UserDefaults and the server never hears about it.
/// Opening a locked thread requires the device owner (Face ID / Touch ID /
/// passcode), once per launch; toggling the lock itself requires the same.
@MainActor
@Observable
final class ChatLockStore {
  private enum Key {
    static let lockedThreads = "app.max.chatLock.threadIDs"
  }

  @ObservationIgnored private let defaults: UserDefaults

  private(set) var lockedThreadIDs: Set<String> {
    didSet { defaults.set(Array(lockedThreadIDs), forKey: Key.lockedThreads) }
  }

  /// Threads already unlocked in this launch, so reading one conversation does
  /// not demand Face ID on every scroll back into it. In-memory on purpose.
  @ObservationIgnored private var unlockedThisSession: Set<String> = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.lockedThreadIDs = Set(defaults.stringArray(forKey: Key.lockedThreads) ?? [])
  }

  func isLocked(_ threadID: String) -> Bool {
    lockedThreadIDs.contains(threadID)
  }

  /// True when the thread is locked and has not been unlocked this session.
  func needsUnlock(_ threadID: String) -> Bool {
    isLocked(threadID) && !unlockedThisSession.contains(threadID)
  }

  /// Locks or unlocks the thread. Both directions demand device-owner
  /// authentication first — otherwise anyone holding the phone could simply
  /// flip the lock off.
  @discardableResult
  func setLocked(_ locked: Bool, threadID: String) async -> Bool {
    guard locked != isLocked(threadID) else { return true }
    let reason = locked ? "Lock this chat" : "Unlock this chat"
    guard await Self.authenticate(reason: reason) else {
      // Re-assigning the unchanged set still notifies observers, which snaps a
      // toggle the user flipped back to the truth after a failed Face ID.
      lockedThreadIDs = lockedThreadIDs
      return false
    }
    if locked {
      lockedThreadIDs.insert(threadID)
    } else {
      lockedThreadIDs.remove(threadID)
    }
    unlockedThisSession.remove(threadID)
    return true
  }

  /// Runs the device-owner check needed to open the thread. Returns true when
  /// the thread may be shown.
  @discardableResult
  func unlock(_ threadID: String) async -> Bool {
    guard needsUnlock(threadID) else { return true }
    guard await Self.authenticate(reason: "Unlock this chat") else { return false }
    unlockedThisSession.insert(threadID)
    return true
  }

  /// The single auth helper every chat-lock surface shares.
  /// `.deviceOwnerAuthentication` falls back from biometrics to the passcode on
  /// its own, so there is no PIN flow to build here.
  static func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    var evaluationError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
      // No passcode set: there is nothing to authenticate against, and refusing
      // forever would wall the user out of their own conversation.
      return true
    }
    let passed = (try? await context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: reason
    )) ?? false
    return passed
  }
}
