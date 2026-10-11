import Foundation

@MainActor
final class PluginSafeMode {
  static let shared = PluginSafeMode()

  private let KeyLaunches = "app.max.safemode.launches"
  private let KeyConsecutiveCrashes = "app.max.safemode.consecutive_crashes"
  private let KeySafeModeActive = "app.max.safemode.active"

  private(set) var isSafeModeActive: Bool = false

  private init() {
    checkCrashLoop()
  }

  private func checkCrashLoop() {
    let defaults = UserDefaults.standard
    
    // Check if Safe Mode was explicitly requested (e.g. by holding down or last state)
    let safeActive = defaults.bool(forKey: KeySafeModeActive)
    
    let crashes = defaults.integer(forKey: KeyConsecutiveCrashes)
    
    if safeActive || crashes >= 2 {
      isSafeModeActive = true
      // Clear flag after boot to allow user to exit safe mode later
      defaults.set(false, forKey: KeySafeModeActive)
      defaults.set(0, forKey: KeyConsecutiveCrashes)
      print("[SafeMode] App booted in Safe Mode due to crash loop or manual trigger.")
    } else {
      // Mark starting boot
      defaults.set(crashes + 1, forKey: KeyConsecutiveCrashes)
    }
  }

  func markBootstrapSuccessful() {
    UserDefaults.standard.set(0, forKey: KeyConsecutiveCrashes)
    print("[SafeMode] Bootstrap successful. Reset consecutive crash counter.")
  }

  func forceSafeModeOnNextBoot() {
    UserDefaults.standard.set(true, forKey: KeySafeModeActive)
  }
}


