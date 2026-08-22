import SwiftUI

struct AuthenticationView: View {
  @Environment(MaxDesktopModel.self) private var model
  @State private var showsCredentials = false

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)

      HStack(spacing: 70) {
        VStack(alignment: .leading, spacing: 22) {
          HStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(palette.accent)
            Text("MAX")
              .font(.system(size: 29, weight: .black, design: .rounded))
              .tracking(7)
          }

          Text(model.copy("welcome"))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          Text(model.copy("featureParity"))
            .font(.title3)
            .foregroundStyle(palette.textSecondary)
            .lineSpacing(5)

          GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
              Button(model.copy("continue")) {
                showsCredentials = true
              }
              .buttonStyle(.glassProminent)
              .controlSize(.large)
              .accessibilityIdentifier("mac_auth_continue")

              Button(model.copy("demo")) {
                model.enterDemo()
              }
              .buttonStyle(.glass)
              .controlSize(.large)
              .accessibilityIdentifier("mac_auth_demo")
            }
          }

          Label(model.copy("localDemo"), systemImage: "checkmark.shield.fill")
            .font(.callout)
            .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: 530, alignment: .leading)

        AuthenticationArtwork(palette: palette)
          .frame(width: 390, height: 470)
      }
      .padding(70)
    }
    .sheet(isPresented: $showsCredentials) {
      CredentialsSheet(isPresented: $showsCredentials)
        .environment(model)
    }
  }
}

private struct AuthenticationArtwork: View {
  let palette: MaxPalette

  var body: some View {
    GlassEffectContainer(spacing: 28) {
      ZStack {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
          .fill(
            LinearGradient(
              colors: [palette.accent.opacity(0.92), palette.secondaryAccent.opacity(0.86)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 330, height: 410)
          .rotationEffect(.degrees(-5))
          .shadow(color: palette.accent.opacity(0.28), radius: 42, y: 24)

        VStack(spacing: 30) {
          Image(systemName: "play.rectangle.on.rectangle.fill")
            .font(.system(size: 84, weight: .semibold))
            .symbolRenderingMode(.hierarchical)

          VStack(spacing: 8) {
            Text("Aurora Passage")
              .font(.title.bold())
            Text("Private · Saved · Offline")
              .foregroundStyle(.white.opacity(0.74))
          }

          HStack(spacing: 12) {
            ForEach(["bookmark.fill", "star.fill", "arrow.down.circle.fill"], id: \.self) { symbol in
              Image(systemName: symbol)
                .frame(width: 46, height: 46)
                .glassEffect(.regular.interactive(), in: .circle)
            }
          }
        }
        .foregroundStyle(.white)
        .padding(28)
        .glassEffect(.clear, in: .rect(cornerRadius: 38))
      }
    }
    .accessibilityHidden(true)
  }
}

private struct CredentialsSheet: View {
  @Environment(MaxDesktopModel.self) private var model
  @Binding var isPresented: Bool
  @State private var email = "demo@max.local"
  @State private var password = "demo"

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)

      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text(model.copy("signIn"))
              .font(.largeTitle.bold())
            Text("Use your Max account or the local Demo credentials.")
              .foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Button {
            isPresented = false
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.glass)
          .accessibilityLabel(model.copy("cancel"))
        }

        VStack(alignment: .leading, spacing: 14) {
          TextField(model.copy("email"), text: $email)
            .textContentType(.emailAddress)
            .accessibilityIdentifier("mac_auth_email")
          SecureField(model.copy("password"), text: $password)
            .textContentType(.password)
            .accessibilityIdentifier("mac_auth_password")
        }
        .textFieldStyle(.roundedBorder)

        if let error = model.lastError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }

        HStack {
          Button(model.copy("demo")) {
            model.enterDemo()
            isPresented = false
          }
          .buttonStyle(.glass)

          Spacer()

          Button(model.copy("signIn")) {
            model.signIn(email: email, password: password)
            if model.isAuthenticated { isPresented = false }
          }
          .buttonStyle(.glassProminent)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("mac_auth_submit")
        }
      }
      .padding(36)
      .frame(width: 520)
      .glassEffect(.regular, in: .rect(cornerRadius: 28))
      .padding(32)
    }
    .frame(width: 620, height: 470)
    .accessibilityIdentifier("mac_credentials_sheet")
  }
}

