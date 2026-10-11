import SwiftUI

struct DoubleLockGateView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.appTheme) private var appTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pin = ""
  @State private var isSealed = false

  var body: some View {
    let isCouncil = appTheme == .council
    ZStack {
      if isCouncil {
        CouncilColor.voidBackground.ignoresSafeArea()
      } else {
        palette.canvas.ignoresSafeArea()
      }

      VStack(spacing: MaxSpace.xl) {
        Spacer()

        if isCouncil {
          ZStack {
            CouncilCutShape(cornerRadius: 24, cutDepth: 26)
              .fill(CouncilColor.obsidianSurface)
              .frame(width: 100, height: 100)
              .overlay {
                CouncilCutShape(cornerRadius: 24, cutDepth: 26)
                  .stroke(CouncilColor.quietBorder, lineWidth: 1)
              }
              .scaleEffect(isSealed ? 1.0 : 0.85)

            Image(systemName: "lock.shield.fill")
              .font(.system(size: 44, weight: .semibold))
              .foregroundStyle(CouncilColor.coldSilver)
              .opacity(isSealed ? 1.0 : 0.0)
              .scaleEffect(isSealed ? 1.0 : 0.7)

            if !isSealed && !reduceMotion {
              Rectangle()
                .fill(
                  LinearGradient(
                    colors: [.clear, CouncilColor.coldSilver, CouncilColor.ember, .clear],
                    startPoint: .top, endPoint: .bottom
                  )
                )
                .frame(width: 120, height: 2)
                .offset(y: -50)
                .transition(.move(edge: .top))
            }
          }
          .padding(.bottom, MaxSpace.md)
        } else {
          Image(systemName: "lock.shield.fill")
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(palette.accent)
            .accessibilityHidden(true)
        }

        VStack(spacing: MaxSpace.xs) {
          Text("double_lock.locked.title")
            .font(isCouncil ? CouncilTypography.title : .largeTitle.bold())
            .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.primaryText) : AnyShapeStyle(MaxColor.textPrimary))
          Text("double_lock.locked.subtitle")
            .font(isCouncil ? CouncilTypography.body : .body)
            .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.secondaryText) : AnyShapeStyle(MaxColor.textSecondary))
            .multilineTextAlignment(.center)
        }

        SecureField("double_lock.pin", text: $pin)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .multilineTextAlignment(.center)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 280)
          .accessibilityIdentifier("double-lock.pin")

        if let failure = model.doubleLockStore.failure {
          Text(failure.localizedKey)
            .font(.caption)
            .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.critical) : AnyShapeStyle(MaxColor.danger))
            .multilineTextAlignment(.center)
        }

        VStack(spacing: MaxSpace.sm) {
          if isCouncil {
            Button("double_lock.unlock") {
              Task {
                if await model.doubleLockStore.unlock(pin: pin) { pin = "" }
              }
            }
            .buttonStyle(CouncilButtonStyle(temperature: .ember))
            .controlSize(.large)
            .disabled(pin.isEmpty || model.doubleLockStore.isAuthenticating)
            .accessibilityIdentifier("double-lock.unlock")

            if model.doubleLockStore.biometricsEnabled {
              Button("double_lock.unlock_biometrics", systemImage: biometricSymbol) {
                Task {
                  _ = await model.doubleLockStore.unlockWithBiometrics(
                    reason: String(localized: "double_lock.biometric_reason")
                  )
                }
              }
              .buttonStyle(CouncilButtonStyle(temperature: .neutral))
              .disabled(model.doubleLockStore.isAuthenticating)
            }
          } else {
            Button("double_lock.unlock") {
              Task {
                if await model.doubleLockStore.unlock(pin: pin) { pin = "" }
              }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(pin.isEmpty || model.doubleLockStore.isAuthenticating)
            .accessibilityIdentifier("double-lock.unlock")

            if model.doubleLockStore.biometricsEnabled {
              Button("double_lock.unlock_biometrics", systemImage: biometricSymbol) {
                Task {
                  _ = await model.doubleLockStore.unlockWithBiometrics(
                    reason: String(localized: "double_lock.biometric_reason")
                  )
                }
              }
              .buttonStyle(.glass)
              .disabled(model.doubleLockStore.isAuthenticating)
            }
          }
        }
        .frame(maxWidth: 320)

        if model.doubleLockStore.isAuthenticating { ProgressView() }
        Spacer()
      }
      .padding(MaxSpace.lg)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("double-lock.gate")
    .onAppear {
      if isCouncil {
        if reduceMotion {
          isSealed = true
        } else {
          withAnimation(CouncilMotion.royal) {
            isSealed = true
          }
        }
      }
    }
  }

  private var biometricSymbol: String {
    switch model.doubleLockStore.biometry {
    case .faceID: "faceid"
    case .touchID: "touchid"
    case .none: "lock"
    }
  }
}

struct DoubleLockSettingsView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var activeAction: DoubleLockAction?

  var body: some View {
    Form {
      if model.doubleLockStore.isEnabled {
        Section("double_lock.status") {
          Label("double_lock.enabled", systemImage: "checkmark.shield.fill")
            .foregroundStyle(MaxColor.mint)
          Picker("double_lock.timeout", selection: timeoutBinding) {
            ForEach(DoubleLockTimeout.allCases) { timeout in
              Text(timeout.titleKey)
                .tag(timeout)
            }
          }
          Toggle("double_lock.biometrics", isOn: biometricsBinding)
            .disabled(model.doubleLockStore.biometry == .none)
        }

        Section {
          Button("double_lock.lock_now", systemImage: "lock.fill") {
            model.doubleLockStore.lock()
          }
          Button("double_lock.change_pin") { activeAction = .changePIN }
          Button("double_lock.disable", role: .destructive) { activeAction = .disable }
        }
      } else {
        Section {
          DoubleLockSetupView()
        } header: {
          Text("double_lock.setup")
        } footer: {
          Text("double_lock.setup.footer")
        }
      }

      if let failure = model.doubleLockStore.failure {
        Section {
          Text(failure.localizedKey)
            .foregroundStyle(MaxColor.danger)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .maxScreenBackground()
    .navigationTitle("double_lock.title")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $activeAction) { action in
      DoubleLockCredentialActionView(action: action)
    }
    .accessibilityIdentifier("ui_double_lock_settings")
  }

  private var timeoutBinding: Binding<DoubleLockTimeout> {
    Binding(
      get: { model.doubleLockStore.lockTimeout },
      set: { model.doubleLockStore.lockTimeout = $0 }
    )
  }

  private var biometricsBinding: Binding<Bool> {
    Binding(
      get: { model.doubleLockStore.biometricsEnabled },
      set: { model.doubleLockStore.setBiometricsEnabled($0) }
    )
  }
}

private extension DoubleLockTimeout {
  var titleKey: LocalizedStringKey {
    switch self {
    case .immediately: "double_lock.timeout.0"
    case .oneMinute: "double_lock.timeout.60"
    case .fiveMinutes: "double_lock.timeout.300"
    case .fifteenMinutes: "double_lock.timeout.900"
    case .oneHour: "double_lock.timeout.3600"
    }
  }
}

private struct DoubleLockSetupView: View {
  @Environment(MaxAppModel.self) private var model
  @State private var pin = ""
  @State private var confirmation = ""
  @State private var useBiometrics = true
  @State private var mismatch = false

  // Emitted as sibling rows so the enclosing Section lays them out with native
  // separators and insets, matching the Change PIN sheet in this same file.
  @ViewBuilder
  var body: some View {
    SecureField("double_lock.new_pin", text: $pin)
      .keyboardType(.numberPad)
      .textContentType(.newPassword)
    SecureField("double_lock.confirm_pin", text: $confirmation)
      .keyboardType(.numberPad)
      .textContentType(.newPassword)
    if model.doubleLockStore.biometry != .none {
      Toggle("double_lock.biometrics", isOn: $useBiometrics)
    }
    if mismatch {
      Text("double_lock.pin_mismatch")
        .font(.caption)
        .foregroundStyle(MaxColor.danger)
    }
    Button("double_lock.enable") {
      guard pin == confirmation else {
        mismatch = true
        return
      }
      mismatch = false
      Task {
        if await model.doubleLockStore.configure(
          pin: pin,
          enableBiometrics: useBiometrics
        ) {
          pin = ""
          confirmation = ""
        }
      }
    }
    .buttonStyle(.borderless)
    .disabled(pin.isEmpty || confirmation.isEmpty || model.doubleLockStore.isAuthenticating)
  }
}

private enum DoubleLockAction: String, Identifiable {
  case changePIN
  case disable
  var id: String { rawValue }
}

private struct DoubleLockCredentialActionView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let action: DoubleLockAction

  @State private var currentPIN = ""
  @State private var newPIN = ""
  @State private var confirmation = ""
  @State private var mismatch = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("double_lock.current_pin", text: $currentPIN)
            .keyboardType(.numberPad)
          if action == .changePIN {
            SecureField("double_lock.new_pin", text: $newPIN)
              .keyboardType(.numberPad)
            SecureField("double_lock.confirm_pin", text: $confirmation)
              .keyboardType(.numberPad)
          }
        }

        if mismatch {
          Section {
            Text("double_lock.pin_mismatch")
              .foregroundStyle(MaxColor.danger)
          }
        }

        if let failure = model.doubleLockStore.failure {
          Section {
            Text(failure.localizedKey)
              .foregroundStyle(MaxColor.danger)
          }
        }
      }
      .navigationTitle(action == .changePIN ? "double_lock.change_pin" : "double_lock.disable")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action == .changePIN ? "common.save" : "double_lock.disable") {
            performAction()
          }
          .disabled(currentPIN.isEmpty || model.doubleLockStore.isAuthenticating)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func performAction() {
    Task {
      let succeeded: Bool
      switch action {
      case .changePIN:
        guard newPIN == confirmation else {
          mismatch = true
          return
        }
        mismatch = false
        succeeded = await model.doubleLockStore.changePIN(
          currentPIN: currentPIN,
          newPIN: newPIN
        )
      case .disable:
        succeeded = await model.doubleLockStore.disable(pin: currentPIN)
      }
      if succeeded { dismiss() }
    }
  }
}

private extension DoubleLockFailure {
  var localizedKey: LocalizedStringKey {
    switch self {
    case .invalidPIN: "double_lock.error.invalid_pin"
    case .invalidPINFormat: "double_lock.error.invalid_format"
    case .biometricsCancelled: "double_lock.error.biometric_cancelled"
    case .biometricsUnavailable: "double_lock.error.biometric_unavailable"
    case .biometricsFailed: "double_lock.error.biometric_failed"
    case .storage: "double_lock.error.storage"
    }
  }
}
