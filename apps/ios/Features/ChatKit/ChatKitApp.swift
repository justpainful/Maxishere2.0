import SwiftUI

/// Container that wires the rebuilt chat together: the inbox pushes a
/// conversation onto its own navigation stack. Not yet swapped in for the
/// legacy Chats tab — that happens once ChatKit reaches feature parity
/// (attachments, reactions, new-conversation, group management) so the switch
/// is an upgrade, never a regression.
struct ChatKitApp: View {
  @Environment(MaxAppModel.self) private var model
  @State private var path: [ChatThread] = []

  /// Optional close handler used when presented as a preview over the legacy tab.
  var onClose: (() -> Void)?

  var body: some View {
    NavigationStack(path: $path) {
      ChatKitInboxView(onOpen: { path.append($0) }, onClose: onClose)
        .navigationDestination(for: ChatThread.self) { thread in
          ChatKitThreadView(thread: thread)
        }
    }
    .tint(MaxColor.accent)
    .maxTabContent()
    .accessibilityIdentifier("ui_chatkit_app")
  }
}
