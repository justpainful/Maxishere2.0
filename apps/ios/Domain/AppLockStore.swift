import Foundation
import Observation

/// The whole-app Face ID gate. When the "Lock the app with Face ID" preference
/// is on, launch and every return from the background must pass the device
/// owner check before any content shows. Reuses `ChatLockStore`'s
/// device-owner authentication (biometrics with passcode fallback), so there
/// is no PIN flow of its own — and, like the chat lock, it is purely a privacy
/// screen on this device.
@MainActor
@Observable
final class AppLockStore {
  private(set) var isUnlocked = false
  private(set) var isAuthenticating = false

  /// Backgrounding re-arms the gate; the next foreground shows it again.
  func lockForBackground() {
    isUnlocked = false
  }

  /// Enabling the lock in Settings must not slam the gate on the person who
  /// just flipped the switch — they are demonstrably present.
  func grantForSetup() {
    isUnlocked = true
  }

  /// Runs the device-owner check. A failed or cancelled prompt leaves the gate
  /// up with its Unlock button ready for another attempt.
  func unlock() async {
    guard !isUnlocked, !isAuthenticating else { return }
    isAuthenticating = true
    let passed = await ChatLockStore.authenticate(reason: "Unlock Max")
    isAuthenticating = false
    isUnlocked = passed
  }
}
