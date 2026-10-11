import SwiftUI

/// The whole-app Face ID gate: shown at launch and on every return from the
/// background while the "Lock the app with Face ID" preference is on. It asks
/// for the device owner as soon as it appears; a cancelled prompt leaves the
/// Unlock button ready for another attempt.
struct AppLockGateView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    ZStack {
      palette.canvas.ignoresSafeArea()

      VStack(spacing: MaxSpace.xl) {
        Spacer()

        Image(systemName: "faceid")
          .font(.system(size: 52, weight: .semibold))
          .foregroundStyle(palette.accent)
          .accessibilityHidden(true)

        VStack(spacing: MaxSpace.xs) {
          Text("Max is locked")
            .font(.largeTitle.bold())
            .foregroundStyle(MaxColor.textPrimary)
          Text("Unlock with Face ID to continue.")
            .font(.body)
            .foregroundStyle(MaxColor.textSecondary)
            .multilineTextAlignment(.center)
        }

        Button {
          Task { await model.appLockStore.unlock() }
        } label: {
          Label("Unlock", systemImage: "lock.open")
            .font(.body.weight(.semibold))
            .frame(maxWidth: 220)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.appLockStore.isAuthenticating)
        .accessibilityIdentifier("ui_app_lock_unlock")

        Spacer()
        Spacer()
      }
      .padding(MaxSpace.lg)
    }
    .task { await model.appLockStore.unlock() }
    .accessibilityIdentifier("ui_app_lock_gate")
  }
}
