import SwiftUI

struct AppShellView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    @Bindable var model = model
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)

      NavigationSplitView {
        sidebar
          .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 310)
      } detail: {
        destinationView
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationSplitViewStyle(.balanced)
    }
    .tint(palette.accent)
    .foregroundStyle(palette.textPrimary)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            Button {
              model.isCommandPalettePresented = true
            } label: {
              Label(model.copy("search"), systemImage: "magnifyingglass")
            }
            .buttonStyle(.glass)
            .keyboardShortcut("k", modifiers: [.command])
            .accessibilityIdentifier("mac_toolbar_search")

            Button {
              model.isUploadPresented = true
            } label: {
              Label(model.copy("upload"), systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("mac_toolbar_upload")

            Button {
              model.isTransfersPresented = true
            } label: {
              Image(systemName: "arrow.up.arrow.down.circle")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(model.copy("transfers"))
            .accessibilityIdentifier("mac_toolbar_transfers")
          }
        }
      }
    }
    .sheet(isPresented: $model.isUploadPresented) {
      UploadSheetView()
        .environment(model)
    }
    .sheet(isPresented: $model.isTransfersPresented) {
      TransfersView()
        .environment(model)
    }
    .sheet(isPresented: $model.isMediaPresented) {
      MediaDetailView()
        .environment(model)
    }
    .sheet(isPresented: $model.isProfileEditorPresented) {
      ProfileEditorView()
        .environment(model)
    }
    .sheet(isPresented: $model.isCommandPalettePresented) {
      CommandPaletteView()
        .environment(model)
    }
  }

  private var sidebar: some View {
    @Bindable var model = model
    let palette = model.palette

    return VStack(spacing: 0) {
      SidebarIdentityCard(profile: model.profile, palette: palette)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)

      List(selection: $model.selectedDestination) {
        Section("Max") {
          sidebarRow(.vault)
          sidebarRow(.library)
          sidebarRow(.shared)
          sidebarRow(.chats, badge: model.threads.reduce(0) { $0 + $1.unreadCount })
          sidebarRow(.profile)
        }

        Section("Discover") {
          sidebarRow(.memories)
          sidebarRow(.plugins)
        }
      }
      .scrollContentBackground(.hidden)
      .listStyle(.sidebar)

      HStack(spacing: 10) {
        SettingsLink {
          Label(model.copy("settings"), systemImage: "gearshape.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac_sidebar_settings")

        Circle()
          .fill(Color.green)
          .frame(width: 8, height: 8)
          .help("Connected · Demo")
      }
      .font(.callout.weight(.medium))
      .foregroundStyle(palette.textSecondary)
      .padding(14)
    }
    .background(.clear)
  }

  private func sidebarRow(_ destination: SidebarDestination, badge: Int = 0) -> some View {
    HStack {
      Label(model.copy(destination.rawValue), systemImage: destination.symbol)
      Spacer()
      if badge > 0 {
        Text("\(badge)")
          .font(.caption2.bold())
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(model.palette.accent, in: Capsule())
          .foregroundStyle(.white)
      }
    }
    .tag(destination)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mac_sidebar_\(destination.rawValue)")
  }

  @ViewBuilder
  private var destinationView: some View {
    switch model.selectedDestination {
    case .vault:
      VaultView()
    case .library:
      LibraryView()
    case .shared:
      SharedView()
    case .chats:
      ChatsView()
    case .profile:
      ProfileView()
    case .memories:
      MemoriesView()
    case .plugins:
      PluginStoreView()
    }
  }
}

private struct SidebarIdentityCard: View {
  let profile: MaxProfile
  let palette: MaxPalette

  var body: some View {
    HStack(spacing: 11) {
      ZStack {
        Circle()
          .fill(LinearGradient(colors: [palette.accent, palette.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
        Text(profile.displayName.prefix(1))
          .font(.headline.bold())
          .foregroundStyle(.white)
      }
      .frame(width: 38, height: 38)

      VStack(alignment: .leading, spacing: 2) {
        Text(profile.displayName)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Text("@\(profile.username)")
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(11)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 17))
  }
}
