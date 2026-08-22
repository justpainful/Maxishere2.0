import SwiftUI

struct MaxSettingsView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)
      TabView {
        generalSettings
          .tabItem { Label(model.copy("general"), systemImage: "gearshape") }
        privacySettings
          .tabItem { Label(model.copy("privacy"), systemImage: "hand.raised.fill") }
        securitySettings
          .tabItem { Label(model.copy("security"), systemImage: "lock.shield.fill") }
        serverSettings
          .tabItem { Label(model.copy("server"), systemImage: "server.rack") }
      }
      .scenePadding()
    }
    .frame(minWidth: 640, minHeight: 500)
    .accessibilityIdentifier("mac_settings_screen")
  }

  private var generalSettings: some View {
    @Bindable var model = model
    let palette = model.palette

    return Form {
      Section(model.copy("appearance")) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
          ForEach(AppTheme.allCases) { theme in
            Button {
              model.theme = theme
              model.persistPreferences()
            } label: {
              VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                  .fill(
                    LinearGradient(
                      colors: [
                        MaxPalette.palette(for: theme, colorScheme: theme.preferredColorScheme ?? .dark).accent,
                        MaxPalette.palette(for: theme, colorScheme: theme.preferredColorScheme ?? .dark).backgroundBottom,
                      ],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing
                    )
                  )
                  .frame(height: 52)
                  .overlay(alignment: .topTrailing) {
                    if model.theme == theme {
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .padding(7)
                    }
                  }
                Text(theme.localizedName).font(.callout.weight(.semibold))
              }
              .padding(10)
              .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mac_theme_\(theme.rawValue)")
          }
        }
      }

      Section(model.copy("language")) {
        Picker(model.copy("language"), selection: $model.language) {
          Text("English").tag(AppLanguage.english)
          Text("العربية").tag(AppLanguage.arabic)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mac_settings_language")
        .onChange(of: model.language) { _, _ in model.persistPreferences() }
        Text(model.language == .arabic ? "يُطبق اتجاه الكتابة من اليمين إلى اليسار على التطبيق بالكامل." : "Language and reading direction apply across the entire app.")
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
      }

      Section(model.copy("downloads")) {
        Toggle("Download on Wi-Fi only", isOn: $model.wifiOnlyDownloads)
        Button("Open Transfer Manager") { model.isTransfersPresented = true }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  private var privacySettings: some View {
    Form {
      Section("Local data") {
        Label("Tokens are stored in the macOS Keychain.", systemImage: "key.fill")
        Label("Offline copies remain inside the app container.", systemImage: "internaldrive.fill")
        Label("Demo mode never contacts the network.", systemImage: "network.slash")
      }
      Section("Media") {
        Toggle("Remove metadata when exporting", isOn: .constant(true))
        Toggle("Hide private previews in notifications", isOn: .constant(true))
      }
      Section {
        Button("Clear thumbnail cache") { }
        Button("Clear all local data", role: .destructive) { }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  private var securitySettings: some View {
    @Bindable var model = model
    return Form {
      Section(model.copy("security")) {
        Toggle("Require Double Lock", isOn: $model.doubleLockEnabled)
        Picker("Lock after", selection: .constant("5 minutes")) {
          Text("Immediately").tag("Immediately")
          Text("1 minute").tag("1 minute")
          Text("5 minutes").tag("5 minutes")
          Text("15 minutes").tag("15 minutes")
        }
        Button("Change Double Lock Passcode…") { }
      }
      Section("System") {
        Label("Touch ID may unlock Double Lock when available.", systemImage: "touchid")
        Label("The app locks when this Mac sleeps.", systemImage: "moon.zzz.fill")
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  private var serverSettings: some View {
    @Bindable var model = model
    return Form {
      Section(model.copy("server")) {
        TextField("Server URL", text: $model.serverURL)
          .textContentType(.URL)
        HStack {
          Button("Check Connection") {
            Task {
              guard let url = URL(string: model.serverURL) else {
                model.lastError = "Enter a valid URL."
                return
              }
              await model.apiClient.updateBaseURL(url)
              do {
                let healthy = try await model.apiClient.healthCheck()
                model.lastError = healthy ? nil : "The server is unavailable."
              } catch {
                model.lastError = error.localizedDescription
              }
            }
          }
          .buttonStyle(.glassProminent)
          if let error = model.lastError {
            Text(error).foregroundStyle(.red).font(.caption)
          } else {
            Label("Demo configuration", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
          }
        }
      }
      Section(model.copy("advanced")) {
        Toggle("Enable diagnostics", isOn: $model.diagnosticsEnabled)
        LabeledContent("Client", value: "Max macOS 2.2.0")
        LabeledContent("Platform", value: "macOS 26 Tahoe")
        LabeledContent("Rendering", value: "Native SwiftUI Liquid Glass")
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}

