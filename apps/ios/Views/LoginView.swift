import SwiftUI
import UIKit

struct LoginView: View {
  private enum FocusField: Hashable {
    case email
    case password
  }

  @Environment(MaxAppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.appTheme) private var appTheme

  @State private var showsPassword = false
  @State private var showsServerSettings = false
  @FocusState private var focusedField: FocusField?

  private var emailBinding: Binding<String> {
    Binding(
      get: { model.sessionStore.loginEmail },
      set: { model.sessionStore.loginEmail = $0 }
    )
  }

  private var passwordBinding: Binding<String> {
    Binding(
      get: { model.sessionStore.loginPassword },
      set: { model.sessionStore.loginPassword = $0 }
    )
  }

  private var loginError: ProductError {
    if !model.networkMonitor.isOnline {
      return ProductError(
        area: .account,
        code: .offline,
        title: String(localized: "error.product.offline.title"),
        reason: String(localized: "error.product.offline.reason"),
        recoverySuggestion: String(localized: "error.product.retry")
      )
    }

    return ProductError(
      area: .account,
      code: .sessionExpired,
      title: String(localized: "login.error.title"),
      reason: String(localized: "login.error.reason"),
      recoverySuggestion: String(localized: "login.error.recovery")
    )
  }

  private var canSubmit: Bool {
    !model.sessionStore.phase.isLoading
      && !model.sessionStore.loginEmail.trimmingCharacters(in: .whitespaces).isEmpty
      && !model.sessionStore.loginPassword.isEmpty
  }

  private var showsDeveloperSettings: Bool {
    true
  }

  var body: some View {
    let isCouncil = appTheme == .council
    NavigationStack {
      ScrollView {
        VStack(spacing: MaxSpace.xl) {
          LoginIdentityView()
            .padding(.top, MaxSpace.xl)

          VStack(spacing: MaxSpace.md) {
            Group {
              if isCouncil {
                VStack(spacing: MaxSpace.md) {
                  inputs
                }
              } else {
                GlassEffectContainer(spacing: MaxSpace.md) {
                  VStack(spacing: MaxSpace.md) {
                    inputs
                  }
                }
              }
            }

            if model.sessionStore.phase.errorMessage != nil {
              ProductErrorView(error: loginError, retry: signIn)
            }

            if isCouncil {
              Button(action: signIn) {
                HStack(spacing: MaxSpace.xs) {
                  if model.sessionStore.phase.isLoading {
                    ProgressView()
                      .controlSize(.small)
                  }
                  if model.sessionStore.phase.isLoading {
                    Text("login.loading")
                      .frame(maxWidth: .infinity)
                  } else {
                    Text("login.cta")
                      .frame(maxWidth: .infinity)
                  }
                }
              }
              .buttonStyle(CouncilButtonStyle(temperature: .ember))
              .controlSize(.large)
              .frame(minHeight: 52)
              .disabled(!canSubmit)
              .accessibilityIdentifier("ui_login_submit")
            } else {
              Button(action: signIn) {
                HStack(spacing: MaxSpace.xs) {
                  if model.sessionStore.phase.isLoading {
                    ProgressView()
                      .controlSize(.small)
                  }
                  if model.sessionStore.phase.isLoading {
                    Text("login.loading")
                      .frame(maxWidth: .infinity)
                  } else {
                    Text("login.cta")
                      .frame(maxWidth: .infinity)
                  }
                }
              }
              .buttonStyle(.glassProminent)
              .controlSize(.large)
              .frame(minHeight: 52)
              .disabled(!canSubmit)
              .accessibilityIdentifier("ui_login_submit")
            }

            if model.isDemoMode {
              if isCouncil {
                Button("login.demo.cta", action: signInToDemo)
                  .buttonStyle(CouncilButtonStyle(temperature: .neutral))
                  .controlSize(.large)
                  .disabled(model.sessionStore.phase.isLoading)
                  .accessibilityIdentifier("ui_login_demo")
              } else {
                Button("login.demo.cta", action: signInToDemo)
                  .buttonStyle(.glass)
                  .controlSize(.large)
                  .disabled(model.sessionStore.phase.isLoading)
                  .accessibilityIdentifier("ui_login_demo")
              }
            }
          }
          .frame(maxWidth: 480)
        }
        .padding(.horizontal, MaxSpace.lg)
        .padding(.bottom, MaxSpace.xxl)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .maxScreenBackground()
      .accessibilityIdentifier("ui_login_credentials_sheet")
      .toolbar {
        if showsDeveloperSettings {
          ToolbarItem(placement: .topBarTrailing) {
            Button("server.settings", systemImage: "network") {
              showsServerSettings = true
            }
            .accessibilityIdentifier("ui_login_server_settings")
          }
        }
      }
      .onAppear {
        if !model.isDemoMode {
          focusedField = .email
        }
      }
      .animation(reduceMotion ? nil : MaxMotion.standard, value: showsPassword)
      .sheet(isPresented: $showsServerSettings) {
        ServerSettingsView()
      }
    }
  }

  @ViewBuilder
  private var inputs: some View {
    LoginTextField(
      title: "login.email",
      text: emailBinding,
      contentType: .username,
      keyboardType: .emailAddress,
      submitLabel: .next
    )
    .focused($focusedField, equals: .email)
    .onSubmit { focusedField = .password }
    .accessibilityIdentifier("ui_login_email")

    LoginPasswordField(
      text: passwordBinding,
      showsPassword: $showsPassword,
      submit: signIn
    )
    .focused($focusedField, equals: .password)
  }

  private func signIn() {
    guard canSubmit else { return }
    focusedField = nil
    Task {
      await model.signIn(
        email: model.sessionStore.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines),
        password: model.sessionStore.loginPassword
      )
    }
  }

  private func signInToDemo() {
    focusedField = nil
    Task { await model.signInToDemo() }
  }
}

private struct LoginIdentityView: View {
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    VStack(spacing: MaxSpace.md) {
      ZStack {
        MeshGradient(
          width: 2,
          height: 2,
          points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
          colors: [MaxColor.sky, MaxColor.periwinkle, MaxColor.coral, MaxColor.violet],
          background: palette.canvas,
          smoothsColors: true
        )
        Text(verbatim: "Max")
          .font(.system(size: 25, weight: .black, design: .rounded))
          .tracking(1.5)
          .foregroundStyle(.white)
      }
      .frame(width: 84, height: 84)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(.white.opacity(0.62), lineWidth: 1)
      }
      .accessibilityHidden(true)

      VStack(spacing: MaxSpace.xs) {
        Text("login.title")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)
          .multilineTextAlignment(.center)
        Text("login.subtitle")
          .font(.body)
          .foregroundStyle(MaxColor.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct LoginTextField: View {
  let title: LocalizedStringKey
  @Binding var text: String
  let contentType: UITextContentType?
  let keyboardType: UIKeyboardType
  let submitLabel: SubmitLabel

  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    TextField(title, text: $text)
      .textContentType(contentType)
      .keyboardType(keyboardType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(submitLabel)
      .padding(.horizontal, MaxSpace.md)
      .frame(minHeight: 54)
      .background {
        if isCouncil {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CouncilColor.stoneSurface)
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CouncilColor.quietBorder, lineWidth: 1)
            }
        }
      }
      .background {
        if !isCouncil {
          Color.clear
            .glassEffect(
              .regular.interactive(),
              in: .rect(cornerRadius: MaxRadius.medium)
            )
        }
      }
  }
}

private struct LoginPasswordField: View {
  @Binding var text: String
  @Binding var showsPassword: Bool
  let submit: () -> Void

  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    HStack(spacing: MaxSpace.xs) {
      Group {
        if showsPassword {
          TextField("login.password", text: $text)
        } else {
          SecureField("login.password", text: $text)
        }
      }
      .textContentType(.password)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(.go)
      .onSubmit(submit)

      Button {
        showsPassword.toggle()
      } label: {
        Image(systemName: showsPassword ? "eye.slash" : "eye")
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(showsPassword ? Text("login.password.hide") : Text("login.password.show"))
      .accessibilityIdentifier("ui_login_password_visibility")
    }
    .padding(.leading, MaxSpace.md)
    .padding(.trailing, MaxSpace.xs)
    .frame(minHeight: 54)
    .background {
      if isCouncil {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(CouncilColor.stoneSurface)
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(CouncilColor.quietBorder, lineWidth: 1)
          }
      }
    }
    .background {
      if !isCouncil {
        Color.clear
          .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: MaxRadius.medium)
          )
      }
    }
    .accessibilityIdentifier("ui_login_password")
  }
}
