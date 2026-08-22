import AppKit
import SwiftUI

@main
struct MaxMacApp: App {
  @State private var model = MaxDesktopModel()

  var body: some Scene {
    WindowGroup {
      MaxRootView()
        .environment(model)
        .environment(\.layoutDirection, model.language.layoutDirectionIsRTL ? .rightToLeft : .leftToRight)
        .preferredColorScheme(model.theme.preferredColorScheme)
        .background(WindowConfigurator())
    }
    .defaultSize(width: 1380, height: 900)
    .windowResizability(.contentMinSize)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(after: .newItem) {
        Button(model.copy("upload")) {
          model.isUploadPresented = true
        }
        .keyboardShortcut("u", modifiers: [.command])

        Button(model.copy("search")) {
          model.isCommandPalettePresented = true
        }
        .keyboardShortcut("k", modifiers: [.command])
      }

      CommandMenu("Navigate") {
        ForEach(SidebarDestination.allCases) { destination in
          Button(MaxCopy.text(destination.rawValue, language: model.language)) {
            model.selectedDestination = destination
          }
        }
      }
    }

    Settings {
      MaxSettingsView()
        .environment(model)
        .environment(\.layoutDirection, model.language.layoutDirectionIsRTL ? .rightToLeft : .leftToRight)
        .preferredColorScheme(model.theme.preferredColorScheme)
    }
    .defaultSize(width: 720, height: 560)
  }
}

struct MaxRootView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    Group {
      if model.isAuthenticated {
        AppShellView()
      } else {
        AuthenticationView()
      }
    }
    .frame(minWidth: 900, minHeight: 650)
    .accessibilityIdentifier(model.isAuthenticated ? "mac_authenticated_shell" : "mac_authentication")
  }
}

@MainActor
private struct WindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowConfigurationView {
    WindowConfigurationView()
  }

  func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
    nsView.applyRequestedConfiguration()
  }
}

@MainActor
private final class WindowConfigurationView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyRequestedConfiguration()
  }

  func applyRequestedConfiguration() {
    guard let window else { return }
    let environment = ProcessInfo.processInfo.environment
    guard let widthText = environment["MAX_MAC_WINDOW_WIDTH"],
          let heightText = environment["MAX_MAC_WINDOW_HEIGHT"],
          let width = Double(widthText),
          let height = Double(heightText) else { return }

    let size = NSSize(width: width, height: height)
    window.setContentSize(size)
    window.center()
  }
}

