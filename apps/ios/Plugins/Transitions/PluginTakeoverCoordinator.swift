import SwiftUI
import UIKit

enum TakeoverPhase: String, CaseIterable, Sendable, Hashable {
  case prepare
  case origin
  case propagate
  case transformNavigation = "transform-navigation"
  case transformSurfaces = "transform-surfaces"
  case transformBackground = "transform-background"
  case revealDetails = "reveal-details"
  case settle
  case complete
}

@Observable
@MainActor
final class PluginTakeoverCoordinator {
  public static let shared = PluginTakeoverCoordinator()

  public private(set) var isTransitioning = false
  public private(set) var currentPhase: TakeoverPhase = .prepare
  public private(set) var progress: CGFloat = 0.0 // 0.0 to 1.0
  public private(set) var targetPluginId: String?
  
  private var task: Task<Void, Never>?

  private init() {}

  func startTakeover(targetPluginId: String, duration: Double = 2.4) {
    // Reduce Motion has to be honoured at the source: the overlay only swapped
    // its *content*, so the 2.4 s state machine and its six haptic impacts ran
    // regardless. Low Power Mode gets the same instant path.
    guard !UIAccessibility.isReduceMotionEnabled,
          !UserDefaults.standard.bool(forKey: "app.max.preferences.reduceBackgroundMotion"),
          !ProcessInfo.processInfo.isLowPowerModeEnabled else {
      PluginStore.shared.activateVisualPlugin(targetPluginId)
      return
    }

    self.targetPluginId = targetPluginId
    withAnimation(.easeInOut(duration: 0.2)) {
      self.isTransitioning = true
    }
    self.currentPhase = .prepare
    self.progress = 0.0

    let haptics = PluginStore.shared.activeVisualPlugin?.context.haptics ?? DefaultPluginHaptics()

    task?.cancel()
    task = Task {
      haptics.triggerNotification(.success)
      
      let phases: [TakeoverPhase] = [
        .prepare,
        .origin,
        .propagate,
        .transformNavigation,
        .transformSurfaces,
        .transformBackground,
        .revealDetails,
        .settle,
        .complete
      ]

      let stepDuration = duration / Double(phases.count - 1)

      for (index, phase) in phases.enumerated() {
        guard !Task.isCancelled else {
          rollback()
          return
        }

        withAnimation(.easeInOut(duration: stepDuration)) {
          self.currentPhase = phase
          self.progress = CGFloat(index) / CGFloat(phases.count - 1)
        }

        // Haptic feedback feedback patterns
        switch phase {
        case .origin:
          haptics.triggerImpact(.medium)
        case .propagate:
          haptics.triggerImpact(.light)
        case .transformNavigation:
          haptics.triggerImpact(.medium)
        case .transformSurfaces:
          haptics.triggerImpact(.rigid)
        case .settle:
          haptics.triggerImpact(.soft)
        case .complete:
          haptics.triggerNotification(.success)
        default:
          break
        }

        // Wait for step to finish. The last phase has nothing to wait for, and
        // sleeping after it stretched the declared 2.4 s to 2.7 s.
        if index < phases.count - 1 {
          try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
        }
      }

      // Finish takeover. Without this guard, a `skip()` landing on the final
      // iteration let the loop fall through and activate the plugin twice.
      guard !Task.isCancelled else { return }
      PluginStore.shared.activateVisualPlugin(targetPluginId)
      withAnimation(.easeInOut(duration: 0.2)) {
        self.isTransitioning = false
      }
      self.targetPluginId = nil
    }
  }

  func skip() {
    logDiagnostic("plugin.transition.skipped", level: "info")
    task?.cancel()
    task = nil
    if let target = targetPluginId {
      PluginStore.shared.activateVisualPlugin(target)
    }
    withAnimation(.easeInOut(duration: 0.2)) {
      self.isTransitioning = false
    }
    self.targetPluginId = nil
  }

  func rollback() {
    logDiagnostic("plugin.transition.rolledBack", level: "warning")
    withAnimation(.easeInOut(duration: 0.2)) {
      self.isTransitioning = false
    }
    self.targetPluginId = nil
    self.progress = 0.0
  }

  func handleAppLifecycleInterrupt() {
    if isTransitioning {
      logDiagnostic("plugin.transition.interrupted | App sent to background", level: "warning")
      skip() // Fast-forward to target state to prevent half-applied themes
    }
  }

  private func logDiagnostic(_ message: String, level: String) {
    PluginStore.shared.logDiagnostic(message, level: level)
  }
}

// SwiftUI overlay for the takeover transition
struct TakeoverOverlayView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  let coordinator = PluginTakeoverCoordinator.shared

  var body: some View {
    if coordinator.isTransitioning {
      ZStack {
        // Backdrop
        Color.black.opacity(Double(coordinator.progress) * 0.45)
          .ignoresSafeArea()

        if reduceMotion {
          // Simple progress view for accessibility overrides
          VStack(spacing: MaxSpace.md) {
            ProgressView()
              .tint(.white)
            Text("plugin.state.activating")
              .font(.headline)
              .foregroundStyle(.white)
          }
          .accessibilityElement(children: .combine)
        } else {
          // Play visual effect from target plugin
          if let targetId = coordinator.targetPluginId,
             let plugin = PluginStore.shared.availablePlugins.first(where: { $0.manifest.id == targetId }) as? any MaxVisualPlugin {
            plugin.takeoverTransitionView(phase: coordinator.progress)
          }
        }

        // UI Controls: Skip Button
        VStack {
          Spacer()
          Button(action: {
            coordinator.skip()
          }) {
            Text("common.skip")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, MaxSpace.md)
              .padding(.vertical, MaxSpace.xs)
              .frame(minWidth: 44, minHeight: 44)
              .background(Color.white.opacity(0.12), in: Capsule())
              .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1))
          }
          .accessibilityIdentifier("ui_plugin_takeover_skip")
          .padding(.bottom, MaxSpace.xxl + MaxSpace.md)
        }
      }
      .transition(.opacity)
      .zIndex(99999) // Force overlay on top of everything
    }
  }
}


