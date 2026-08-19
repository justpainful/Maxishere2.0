import SwiftUI

final class ExternalDataLabPlugin: MaxPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Lab", email: "datalab@max.app", website: nil)
    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.external-data-lab",
      name: "External Data Lab",
      version: "0.5.0-experimental",
      description: "Demonstrates permission-gated network queries and structured caching controls.",
      longDescription: "Secure sandboxed networking. This experimental plugin declares allowed domain boundaries ('api.mockdata.org') and uses the controlled PluginNetworkAPI to fetch metadata safely.",
      author: author,
      category: .experimental,
      tags: ["experimental", "network", "sandbox"],
      icon: PluginIcon(
        light: AssetReference(type: "system", name: "network"),
        dark: AssetReference(type: "system", name: "network"),
        monochrome: nil,
        animated: nil
      ),
      hero: nil,
      previews: [],
      capabilities: [.customRoute, .customWidget, .settingsPage],
      permissions: [.accessNetwork],
      network: PluginNetworkManifest(allowedDomains: ["api.mockdata.org"], sendsUserData: false),
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.external-data-lab", allowedDomains: ["api.mockdata.org"])
  }

  func register(using context: MaxPluginContext) throws {
    // Register custom route page
    context.routes.register(
      id: "datalab",
      title: "External Data Lab",
      iconName: "network"
    ) { _ in
      AnyView(ExternalDataLabView(context: context))
    }

    // Register Home Widget
    context.widgets.register(
      id: "datalab:widget",
      pointId: "home:afterHero",
      title: "Data Lab Stream",
      accessibilityLabel: "External Data Lab Widget"
    ) {
      AnyView(ExternalDataLabWidget(context: context))
    }
  }

  func settingsView() -> AnyView? {
    AnyView(
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: "Network Settings")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
        Text(verbatim: "Allowed host: api.mockdata.org")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      .padding()
      .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    )
  }
}

// MARK: - External Data Lab View UI
struct ExternalDataLabView: View {
  let context: MaxPluginContext
  @Environment(\.maxThemePalette) private var palette

  @State private var dataString = ""
  @State private var loading = false
  @State private var errorMessage = ""
  @State private var networkLogs: [String] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          Text(verbatim: "Sandbox Query Simulator")
            .font(.headline)
            .foregroundStyle(palette.primaryText)
          
          Text(verbatim: "Tapping 'Fetch Declared' makes a request to the whitelisted domain 'api.mockdata.org'. Tapping 'Fetch Undeclared' tries 'api.eviltracker.com' and is blocked by the sandbox.")
            .font(.caption)
            .foregroundStyle(palette.secondaryText)

          HStack(spacing: MaxSpace.sm) {
            Button {
              fetchData(urlStr: "https://api.mockdata.org/v1/feed")
            } label: {
              Text(verbatim: "Fetch Declared")
                .font(.caption.weight(.bold))
                .padding(.horizontal, MaxSpace.md)
                .padding(.vertical, MaxSpace.xs)
                .background(palette.accent, in: Capsule())
                .foregroundStyle(Color.white)
            }

            Button {
              fetchData(urlStr: "https://api.eviltracker.com/leak")
            } label: {
              Text(verbatim: "Fetch Undeclared")
                .font(.caption.weight(.bold))
                .padding(.horizontal, MaxSpace.md)
                .padding(.vertical, MaxSpace.xs)
                .background(Color.red, in: Capsule())
                .foregroundStyle(Color.white)
            }
          }

          if loading {
            HStack {
              ProgressView()
              Text(verbatim: "Connecting to host...")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            }
            .padding(.top, MaxSpace.xs)
          }

          if !errorMessage.isEmpty {
            Text(verbatim: "Error: \(errorMessage)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.red)
              .padding(.top, MaxSpace.xs)
          }

          if !dataString.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text(verbatim: "Response Data:")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryText)
              Text(verbatim: dataString)
                .font(.system(size: 12, design: .monospaced))
                .padding(MaxSpace.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedContentSurface, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, MaxSpace.xs)
          }
        }
        .padding(MaxSpace.md)
        .background(palette.primaryContentSurface)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
        .overlay {
          RoundedRectangle(cornerRadius: MaxRadius.medium)
            .stroke(palette.separator, lineWidth: 1)
        }

        // Logs
        VStack(alignment: .leading, spacing: MaxSpace.xs) {
          Text(verbatim: "Data Lab Network Logs")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(palette.primaryText)
          
          ForEach(networkLogs, id: \.self) { log in
            Text(verbatim: log)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(log.contains("BLOCKED") ? Color.red : Color.green)
          }
        }
        .padding(MaxSpace.md)
        .background(palette.primaryContentSurface)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
        .overlay {
          RoundedRectangle(cornerRadius: MaxRadius.medium)
            .stroke(palette.separator, lineWidth: 1)
        }
      }
      .padding(MaxSpace.md)
    }
    .background(palette.canvas)
    .onAppear {
      networkLogs = context.network.getDiagnosticHistory()
    }
  }

  private func fetchData(urlStr: String) {
    loading = true
    errorMessage = ""
    dataString = ""
    
    Task {
      do {
        guard let url = URL(string: urlStr) else {
          throw URLError(.badURL)
        }
        let data = try await context.network.request(url)
        dataString = String(data: data, encoding: .utf8) ?? ""
      } catch {
        errorMessage = error.localizedDescription
      }
      loading = false
      networkLogs = context.network.getDiagnosticHistory()
    }
  }
}

// MARK: - External Data Lab Widget UI
struct ExternalDataLabWidget: View {
  let context: MaxPluginContext
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Button {
      context.navigation?.openRoute(routeId: "datalab")
    } label: {
      HStack(spacing: MaxSpace.md) {
        Image(systemName: "icloud.and.arrow.down.fill")
          .font(.title2)
          .foregroundStyle(palette.accent)
          .frame(width: 44, height: 44)
          .background(palette.selectedControl, in: Circle())
        
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "Sandboxed Stream")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primaryText)
          Text(verbatim: "Explore whitelisted domain endpoints")
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
        }
        Spacer()
        Image(systemName: "chevron.forward")
          .foregroundStyle(palette.tertiaryText)
      }
      .padding(MaxSpace.md)
      .background(palette.primaryContentSurface)
      .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MaxRadius.medium)
          .stroke(palette.separator, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}


