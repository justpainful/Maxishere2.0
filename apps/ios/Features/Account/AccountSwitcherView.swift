import SwiftUI

/// The quick account switcher, summoned by long-pressing the profile header
/// avatar (the Settings account section offers the same rows). Tap a saved
/// account to switch to it; "Add Account" stashes the current session and
/// lands on the login screen.
struct AccountSwitcherSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.dismiss) private var dismiss

  @State private var isSwitching = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.accountStore.accounts) { account in
            accountRow(account)
          }

          Button("Add Account", systemImage: "person.badge.plus") {
            dismiss()
            Task { await model.beginAddAccount() }
          }
          .disabled(isSwitching)
          .accessibilityIdentifier("ui_switcher_add_account")
        } footer: {
          Text("Switching keeps every account signed in on this device.")
        }
      }
      .navigationTitle("Accounts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("common.close") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_account_switcher")
  }

  private func accountRow(_ account: StoredAccount) -> some View {
    let isCurrent = account.id == model.sessionStore.user?.id
    return Button {
      guard !isCurrent, !isSwitching else { return }
      isSwitching = true
      Task {
        await model.switchAccount(to: account)
        isSwitching = false
        dismiss()
      }
    } label: {
      HStack(spacing: MaxSpace.sm) {
        ProfileAvatarArtwork(name: account.displayName, url: nil, size: 40)
        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: account.displayName)
            .font(.body.weight(isCurrent ? .semibold : .regular))
            .foregroundStyle(MaxColor.textPrimary)
          if let username = account.username, !username.isEmpty {
            Text(verbatim: "@\(username)")
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .environment(\.layoutDirection, .leftToRight)
          }
        }
        Spacer(minLength: 0)
        if isCurrent {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(palette.accent)
        } else if isSwitching {
          ProgressView()
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isSwitching)
    .accessibilityIdentifier("ui_switcher_account_\(account.id)")
  }
}
