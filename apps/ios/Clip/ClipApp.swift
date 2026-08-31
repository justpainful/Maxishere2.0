import SwiftUI

@main
struct ClipApp: App {
  @State private var activeURL: URL? = nil

  var body: some Scene {
    WindowGroup {
      ClipRootView(invocationURL: activeURL)
        .preferredColorScheme(.dark)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
          guard let incomingURL = userActivity.webpageURL else { return }
          activeURL = incomingURL
        }
        .onOpenURL { url in
          activeURL = url
        }
    }
  }
}
