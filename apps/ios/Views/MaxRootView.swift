import SwiftUI

struct MaxRootView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.appTheme) private var appTheme
  @State private var isGatheringPresented = false

  var body: some View {
    ZStack {
      // Only the logged-out branch lacks an opaque background of its own. The
      // authenticated shell paints its atmosphere per tab and the lock gate
      // paints its own canvas, so wrapping everything in MaxScreen just rendered
      // a second, permanently hidden living background.
      Group {
        if model.presentsAuthenticatedShell {
          if model.doubleLockStore.isLocked {
            DoubleLockGateView()
          } else {
            authenticatedShell
          }
        } else {
          MaxScreen { EntryExperienceView() }
        }
      }

      TakeoverOverlayView()
    }
    .sheet(item: Binding(
      get: { PluginStore.shared.activeRouteId.map { IdentifiableRoute(id: $0) } },
      set: { PluginStore.shared.activeRouteId = $0?.id }
    )) { route in
      NavigationStack {
        if let contribution = PluginStore.shared.routeContributions[route.id] {
          contribution.builder("")
            .navigationTitle(Text(verbatim: contribution.title))
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                  PluginStore.shared.activeRouteId = nil
                }) {
                  Text("plugin.store.close")
                }
              }
            }
        } else {
          VStack(spacing: MaxSpace.md) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundStyle(.orange)
            Text("plugin.route.unavailable")
              .font(.headline)
            Text("plugin.route.unavailable.desc")
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .multilineTextAlignment(.center)
          }
          .padding()
          .navigationTitle(Text("plugin.route.unavailable"))
          .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
              Button(action: {
                PluginStore.shared.activeRouteId = nil
              }) {
                Text("plugin.store.close")
              }
            }
          }
        }
      }
    }
    .sheet(item: sheetBinding) { sheet in
      switch sheet {
      case .rating(let item):
        RatingSheetView(item: item)
      case .accessRequests:
        AccessRequestsSheet()
      case .upload(let destination):
        UploadSheet(destination: destination)
      case .transfers:
        TransferManagerView()
      case .whatsNew:
        WhatsNewView()
      case .serverSettings:
        ServerSettingsView()
      }
    }
    .fullScreenCover(item: playerBinding) { item in
      MaxPlayerView()
        .id(item.id)
    }
    .fullScreenCover(isPresented: memoriesBinding) {
      MemoriesRootView()
    }
    .fullScreenCover(item: releaseAnnouncementBinding) { announcement in
      ReleaseExperienceView(
        announcement: announcement,
        personalDisplayName: model.releaseStore.personalDisplayName,
        onDismiss: { handleReleaseCTA(announcement) }
      )
      .interactiveDismissDisabled()
    }
    .fullScreenCover(isPresented: $isGatheringPresented) {
      CouncilGatheringView {
        model.preferencesStore.hasShownCouncilGathering = true
        isGatheringPresented = false
      }
    }
    .onChange(of: appTheme) { _, newTheme in
      if newTheme == .council && !model.preferencesStore.hasShownCouncilGathering {
        isGatheringPresented = true
      }
    }
    .onAppear {
      if appTheme == .council && !model.preferencesStore.hasShownCouncilGathering {
        isGatheringPresented = true
      }
    }
  }

  private var sheetBinding: Binding<MaxSheet?> {
    Binding(
      get: { model.activeSheet },
      set: { model.activeSheet = $0 }
    )
  }

  private var playerBinding: Binding<MaxMediaItem?> {
    Binding(
      get: { model.doubleLockStore.isLocked ? nil : model.activePlayer },
      set: { model.activePlayer = $0 }
    )
  }

  private var memoriesBinding: Binding<Bool> {
    Binding(
      get: { model.isMemoriesEnabled && !model.doubleLockStore.isLocked && model.isMemoriesPresented },
      set: { model.isMemoriesPresented = model.isMemoriesEnabled && $0 }
    )
  }

  private var releaseAnnouncementBinding: Binding<ReleaseAnnouncement?> {
    Binding(
      get: {
        // Suppress announcement during UI tests to prevent flaky timing failures
        if ProcessInfo.processInfo.environment["MAX_UI_TESTING"] == "1" { return nil }
        guard !model.doubleLockStore.isLocked, model.activePlayer == nil else { return nil }
        guard let announcement = model.releaseStore.activeAnnouncement else { return nil }
        guard announcement.destination != .memories || model.isMemoriesEnabled else { return nil }
        return announcement
      },
      set: { announcement in
        if announcement == nil {
          guard !model.doubleLockStore.isLocked, model.activePlayer == nil else { return }
          model.releaseStore.dismissActiveAnnouncement(markSeen: true)
        } else {
          model.releaseStore.activeAnnouncement = announcement
        }
      }
    )
  }

  private var tabBinding: Binding<AppTab> {
    Binding(
      get: { model.selectedTab },
      set: { model.selectedTab = $0 }
    )
  }

  private func handleReleaseCTA(_ announcement: ReleaseAnnouncement) {
    model.releaseStore.dismissActiveAnnouncement(markSeen: true)
    guard announcement.presentationStyle == .featureUpdate else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      model.openReleaseDestination(announcement.destination)
    }
  }

  private var authenticatedShell: some View {
    Group {
      if appTheme == .clouds {
        rootTabs
          .toolbar(.hidden, for: .tabBar)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            CloudTabBar(selection: tabBinding)
              .padding(.horizontal, MaxSpace.md)
              .padding(.top, MaxSpace.xs)
          }
      } else {
        rootTabs
          .tabBarMinimizeBehavior(.onScrollDown)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if PluginSafeMode.shared.isSafeModeActive {
        HStack {
          Spacer()
          Label(
            title: { Text(verbatim: "Safe Mode Active - Plugins Disabled") },
            icon: { Image(systemName: "exclamationmark.shield.fill") }
          )
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          Spacer()
        }
        .padding(.vertical, 8)
        .background(Color.red)
      } else if !model.networkMonitor.isOnline {
        offlineBanner
      }
    }
    .overlay(alignment: .bottom) {
      if let transfer = model.transferStore.activeRecords.first {
        CompactTransferView(record: transfer)
          .padding(.horizontal, MaxSpace.md)
          .padding(.bottom, appTheme == .clouds ? 84 : 66)
      }
    }
    .accessibilityIdentifier("ui_authenticated_shell")
  }

  private var rootTabs: some View {
    TabView(selection: tabBinding) {
      Tab(value: AppTab.vault) {
        NavigationStack { VaultView() }
      } label: {
        Label("tab.vault", systemImage: "archivebox")
          .accessibilityIdentifier("ui_tab_vault")
      }

      Tab(value: AppTab.library) {
        NavigationStack { LibraryView() }
      } label: {
        Label("tab.library", systemImage: "rectangle.grid.2x2")
          .accessibilityIdentifier("ui_tab_library")
      }

      Tab(value: AppTab.shared) {
        NavigationStack { SharedView() }
      } label: {
        Label("tab.shared", systemImage: "person.2")
          .accessibilityIdentifier("ui_tab_shared")
      }

      Tab(value: AppTab.chats) {
        // ChatKit is the rebuilt chat surface (new-conversation, media, reactions,
        // reply/edit/delete, forward, search, details+members, delete, text/photo/
        // voice send, chats+mentions scopes) on the proven ChatStore realtime +
        // idempotent-send engine and fix's chat repairs. It owns its own
        // NavigationStack. Legacy ChatsView remains in the tree (reachable for
        // reference) until access-requests + member management land here.
        ChatKitApp()
      } label: {
        Label("tab.chats", systemImage: "bubble.left.and.bubble.right")
          .accessibilityIdentifier("ui_tab_chats")
      }

      Tab(value: AppTab.profile) {
        NavigationStack { ProfileView() }
      } label: {
        Label("tab.profile", systemImage: "person.crop.circle")
          .accessibilityIdentifier("ui_tab_profile")
      }
    }
  }

  private var offlineBanner: some View {
    Button {
      model.openTransfers()
    } label: {
      MaxFloatingSurface(horizontalPadding: MaxSpace.md, verticalPadding: MaxSpace.xs) {
        Label("offline.banner", systemImage: "wifi.slash")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MaxColor.warning)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MaxSpace.md)
    .padding(.top, MaxSpace.xs)
  }

}
private struct CloudTabBar: View {
  @Binding var selection: AppTab
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if reduceTransparency {
      tabItems
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, MaxSpace.xs)
        .background(palette.primaryContentSurface.opacity(0.96), in: CloudBarShape())
    } else if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: MaxSpace.xs) {
        tabItems
          .padding(.horizontal, MaxSpace.sm)
          .padding(.vertical, MaxSpace.xs)
          .glassEffect(
            .regular.tint(Color.white.opacity(0.16)).interactive(),
            in: CloudBarShape()
          )
      }
    } else {
      tabItems
        .padding(.horizontal, MaxSpace.sm)
        .padding(.vertical, MaxSpace.xs)
        .background(palette.primaryContentSurface, in: CloudBarShape())
    }
  }

  private var tabItems: some View {
    HStack(spacing: MaxSpace.xxs) {
      ForEach(AppTab.allCases) { tab in
        Button {
          selection = tab
        } label: {
          VStack(spacing: 3) {
            Image(systemName: cloudSymbol(for: tab))
              .font(.system(size: 19, weight: .semibold))
            Text(tab.titleKey)
              .font(.caption2.weight(.semibold))
              .lineLimit(1)
          }
          .foregroundStyle(selection == tab ? palette.accent : palette.secondaryText)
          .frame(maxWidth: .infinity)
          .frame(minHeight: 48)
          .background {
            if selection == tab {
              Capsule(style: .continuous)
                .fill(palette.selectedControl)
                .overlay {
                  Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
                }
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("ui_cloud_tab_\(tab.rawValue)")
      }
    }
  }

  private func cloudSymbol(for tab: AppTab) -> String {
    switch tab {
    case .vault: "shippingbox.fill"
    case .library: "square.grid.2x2.fill"
    case .shared: "person.2.fill"
    case .chats: "bubble.left.and.bubble.right.fill"
    case .profile: "person.crop.circle.fill"
    }
  }
}
private struct CloudBarShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let bodyHeight = rect.height * 0.70
    let bodyY = rect.maxY - bodyHeight
    
    // Start at bottom left curve
    path.move(to: CGPoint(x: rect.minX + bodyHeight / 2, y: rect.maxY))
    
    // Bottom edge
    path.addLine(to: CGPoint(x: rect.maxX - bodyHeight / 2, y: rect.maxY))
    
    // Right cap
    path.addArc(
      center: CGPoint(x: rect.maxX - bodyHeight / 2, y: bodyY + bodyHeight / 2),
      radius: bodyHeight / 2,
      startAngle: .degrees(90),
      endAngle: .degrees(-45),
      clockwise: true
    )
    
    // Right puff arc
    path.addArc(
      center: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.35),
      radius: rect.height * 0.25,
      startAngle: .degrees(-45),
      endAngle: .degrees(-105),
      clockwise: true
    )
    
    // Center puff arc
    path.addArc(
      center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.30),
      radius: rect.height * 0.35,
      startAngle: .degrees(75),
      endAngle: .degrees(225),
      clockwise: true
    )
    
    // Left puff arc
    path.addArc(
      center: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.35),
      radius: rect.height * 0.25,
      startAngle: .degrees(135),
      endAngle: .degrees(225),
      clockwise: true
    )
    
    // Left cap
    path.addArc(
      center: CGPoint(x: rect.minX + bodyHeight / 2, y: bodyY + bodyHeight / 2),
      radius: bodyHeight / 2,
      startAngle: .degrees(225),
      endAngle: .degrees(90),
      clockwise: true
    )
    
    path.closeSubpath()
    return path
  }
}
