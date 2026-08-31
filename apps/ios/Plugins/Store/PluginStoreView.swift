import SwiftUI

/// Identifiable wrapper for any MaxPlugin (existentials cannot conform to Identifiable).
struct IdentifiablePlugin: Identifiable {
  var id: String { plugin.manifest.id }
  let plugin: any MaxPlugin
}

struct PluginStoreView: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.dismiss) private var dismiss

  @State private var selectedTab: Int = 0 // 0: Explore, 1: Installed, 2: Updates
  @State private var selectedPlugin: IdentifiablePlugin?
  @State private var showDebugConsole = false

  init() {}

  var body: some View {
    MaxScreen {
      VStack(spacing: 0) {
        // Spacious Header
        HStack {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.backward")
              .font(.title3.weight(.bold))
              .foregroundStyle(palette.primaryText)
              .frame(width: 44, height: 44)
              .background(palette.primaryContentSurface, in: Circle())
          }
          .accessibilityIdentifier("ui_store_back")

          Spacer()
          
          Text("plugin.store.title")
            .font(.title2.weight(.bold))
            .foregroundStyle(palette.primaryText)
          
          Spacer()

          Button {
            showDebugConsole = true
          } label: {
            Image(systemName: "ladybug.fill")
              .font(.title3)
              .foregroundStyle(palette.secondaryText)
              .frame(width: 44, height: 44)
          }
          .accessibilityIdentifier("ui_store_debug")
        }
        .padding(.horizontal, MaxSpace.md)
        .padding(.top, MaxSpace.sm)

        // Custom Segmented Control
        HStack(spacing: 0) {
          ForEach([
            (0, "plugin.store.explore"),
            (1, "plugin.store.installed"),
            (2, "plugin.store.updates")
          ], id: \.0) { index, key in
            Button {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedTab = index
              }
            } label: {
              VStack(spacing: 6) {
                Text(LocalizedStringKey(key))
                  .font(.subheadline.weight(selectedTab == index ? .bold : .medium))
                  .foregroundStyle(selectedTab == index ? palette.accent : palette.secondaryText)
                
                // Active line
                Capsule()
                  .fill(selectedTab == index ? palette.accent : Color.clear)
                  .frame(height: 3)
                  .frame(width: 40)
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ui_store_tab_\(index)")
          }
        }
        .padding(.top, MaxSpace.md)
        .padding(.bottom, MaxSpace.xs)

        // Tab Content
        ScrollView {
          VStack(spacing: MaxSpace.lg) {
            if selectedTab == 0 {
              exploreTabContent
            } else if selectedTab == 1 {
              installedTabContent
            } else {
              updatesTabContent
            }
          }
          .padding(.vertical, MaxSpace.md)
        }
      }
    }
    .sheet(item: $selectedPlugin) { wrapper in
      PluginDetailsView(plugin: wrapper.plugin)
    }
    .sheet(isPresented: $showDebugConsole) {
      PluginDebugConsoleView()
    }
  }

  // MARK: - Explore Tab
  private var exploreTabContent: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      // Hero Card (Featured Plugin)
      if let heroPlugin = PluginStore.shared.availablePlugins.first(where: { $0.manifest.hero != nil }) {
        Button {
          selectedPlugin = IdentifiablePlugin(plugin: heroPlugin)
        } label: {
          VStack(alignment: .leading, spacing: MaxSpace.xs) {
            Text(verbatim: heroPlugin.manifest.hero?.title ?? "FEATURED")
              .font(.caption2.weight(.black))
              .tracking(2)
              .foregroundStyle(palette.accent)
            
            Text(verbatim: heroPlugin.manifest.name)
              .font(.system(size: 32, weight: .black))
              .foregroundStyle(palette.primaryText)
            
            Text(verbatim: heroPlugin.manifest.description)
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
              .multilineTextAlignment(.leading)
              .lineLimit(3)

            Spacer()

            HStack {
              Text(verbatim: heroPlugin.manifest.hero?.subtitle ?? "Transform Max")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText.opacity(0.8))
              Spacer()
              Text(verbatim: "View Details")
                .font(.footnote.weight(.bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, MaxSpace.sm)
                .padding(.vertical, MaxSpace.xxs)
                .background(palette.primaryContentSurface, in: Capsule())
                .overlay(Capsule().stroke(palette.accent, lineWidth: 1.5))
            }
          }
          .padding(MaxSpace.md)
          .frame(height: 240)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            ZStack {
              if let customBg = heroPlugin.previewBackground() {
                customBg
              } else {
                palette.elevatedContentSurface
              }
            }
          )
          .clipShape(RoundedRectangle(cornerRadius: MaxRadius.large))
          .overlay {
            RoundedRectangle(cornerRadius: MaxRadius.large)
              .stroke(palette.separator, lineWidth: 2)
          }
          .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MaxSpace.md)
      }

      // seasonal section
      Text("plugin.store.seasonal")
        .font(.title3.weight(.bold))
        .foregroundStyle(palette.primaryText)
        .padding(.horizontal, MaxSpace.md)
        .padding(.top, MaxSpace.xs)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MaxSpace.md) {
          ForEach(PluginStore.shared.availablePlugins.filter { $0.manifest.category == .seasonal }, id: \.manifest.id) { plugin in
            PluginCard(plugin: plugin) {
              selectedPlugin = IdentifiablePlugin(plugin: plugin)
            }
          }
        }
        .padding(.horizontal, MaxSpace.md)
      }

      // appearance section
      Text("plugin.store.advanced_appearances")
        .font(.title3.weight(.bold))
        .foregroundStyle(palette.primaryText)
        .padding(.horizontal, MaxSpace.md)
        .padding(.top, MaxSpace.xs)

      ForEach(PluginStore.shared.availablePlugins.filter { $0.manifest.category == .appearance }, id: \.manifest.id) { plugin in
        Button {
          selectedPlugin = IdentifiablePlugin(plugin: plugin)
        } label: {
          HStack(spacing: MaxSpace.md) {
            pluginIconView(for: plugin)
              .frame(width: 60, height: 60)
              .background(palette.elevatedContentSurface, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: MaxSpace.xxs) {
              Text(verbatim: plugin.manifest.name)
                .font(.headline)
                .foregroundStyle(palette.primaryText)
              Text(verbatim: plugin.manifest.description)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
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
        .padding(.horizontal, MaxSpace.md)
      }
    }
  }

  // MARK: - Installed Tab
  private var installedTabContent: some View {
    VStack(alignment: .leading, spacing: MaxSpace.md) {
      let installed = PluginStore.shared.availablePlugins.filter {
        PluginStore.shared.installedPluginIds.contains($0.manifest.id)
      }
      
      if installed.isEmpty {
        VStack(spacing: MaxSpace.sm) {
          Image(systemName: "puzzlepiece")
            .font(.system(size: 48))
            .foregroundStyle(palette.tertiaryText)
          Text("plugin.store.no_plugins")
            .font(.headline)
            .foregroundStyle(palette.secondaryText)
          Text("plugin.store.no_plugins_desc")
            .font(.caption)
            .foregroundStyle(palette.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
      } else {
        ForEach(installed, id: \.manifest.id) { plugin in
          let state = PluginStore.shared.pluginStates[plugin.manifest.id] ?? .installed
          
          VStack(alignment: .leading, spacing: MaxSpace.sm) {
            HStack(spacing: MaxSpace.md) {
              pluginIconView(for: plugin)
                .frame(width: 50, height: 50)
                .background(palette.elevatedContentSurface, in: RoundedRectangle(cornerRadius: 10))

              VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                Text(verbatim: plugin.manifest.name)
                  .font(.headline)
                  .foregroundStyle(palette.primaryText)
                
                // Status badge
                Text(verbatim: state.localizedDescription)
                  .font(.caption2.weight(.bold))
                  .padding(.horizontal, MaxSpace.xs)
                  .padding(.vertical, 2)
                  .background(state == .active ? palette.accent.opacity(0.15) : palette.tertiaryText.opacity(0.12), in: Capsule())
                  .foregroundStyle(state == .active ? palette.accent : palette.secondaryText)
              }
              Spacer()
              
              // Enable/Disable controls
              if plugin.manifest.capabilities.contains(.theme) {
                let isActive = PluginStore.shared.activeVisualPluginId == plugin.manifest.id
                Button {
                  if isActive {
                    PluginStore.shared.deactivateVisualPlugin()
                  } else {
                    PluginTakeoverCoordinator.shared.startTakeover(targetPluginId: plugin.manifest.id)
                  }
                } label: {
                  Text(isActive ? "plugin.state.active" : "plugin.action.apply_theme")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, MaxSpace.md)
                    .padding(.vertical, MaxSpace.xs)
                    .background(isActive ? palette.selectedControl : palette.accent, in: Capsule())
                    .foregroundStyle(isActive ? palette.accent : Color.white)
                }
              } else {
                let isActive = PluginStore.shared.activeFeaturePluginIds.contains(plugin.manifest.id)
                Button {
                  PluginStore.shared.toggleFeaturePlugin(plugin.manifest.id)
                } label: {
                  Text(isActive ? "plugin.state.active" : "plugin.action.enable_feature")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, MaxSpace.md)
                    .padding(.vertical, MaxSpace.xs)
                    .background(isActive ? palette.selectedControl : palette.accent, in: Capsule())
                    .foregroundStyle(isActive ? palette.accent : Color.white)
                }
              }
            }
            
            Divider()
              .background(palette.separator)
            
            HStack {
              Button {
                selectedPlugin = IdentifiablePlugin(plugin: plugin)
              } label: {
                Label(
                  title: { Text("plugin.store.settings") },
                  icon: { Image(systemName: "gearshape") }
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.secondaryText)
              }
              
              Spacer()
              
              Button {
                Task {
                  await PluginStore.shared.uninstall(pluginId: plugin.manifest.id)
                }
              } label: {
                Label(
                  title: { Text("plugin.store.remove") },
                  icon: { Image(systemName: "trash") }
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.destructive)
              }
            }
          }
          .padding(MaxSpace.md)
          .background(palette.primaryContentSurface)
          .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
          .overlay {
            RoundedRectangle(cornerRadius: MaxRadius.medium)
              .stroke(palette.separator, lineWidth: 1)
          }
          .padding(.horizontal, MaxSpace.md)
        }
      }
    }
  }

  // MARK: - Updates Tab
  private var updatesTabContent: some View {
    VStack(spacing: MaxSpace.sm) {
      Image(systemName: "arrow.clockwise.circle")
        .font(.system(size: 48))
        .foregroundStyle(palette.tertiaryText)
      Text("plugin.store.up_to_date")
        .font(.headline)
        .foregroundStyle(palette.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 40)
  }

  // Sigil/Icon Render Helper
  @ViewBuilder
  private func pluginIconView(for plugin: any MaxPlugin) -> some View {
    if let customIcon = plugin.iconView() {
      customIcon
    } else {
      let systemName = plugin.manifest.icon.light.name
      Image(systemName: systemName)
        .font(.title)
        .foregroundStyle(palette.accent)
    }
  }
}

// MARK: - Large Discovery Card View
struct PluginCard: View {
  let plugin: any MaxPlugin
  let action: () -> Void

  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: MaxSpace.xs) {
        // Visual theme preview
        ZStack {
          cardPreviewBackground
            .frame(height: 120)
          
          VStack {
            Spacer()
            HStack {
              pluginSigil
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.2), in: Circle())
              Spacer()
            }
            .padding(MaxSpace.sm)
          }
        }
        
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: plugin.manifest.name)
            .font(.headline)
            .foregroundStyle(palette.primaryText)
          
          Text(verbatim: plugin.manifest.description)
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, MaxSpace.sm)
        .padding(.bottom, MaxSpace.sm)
      }
      .frame(width: 200)
      .background(palette.primaryContentSurface)
      .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MaxRadius.medium)
          .stroke(palette.separator, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var cardPreviewBackground: some View {
    if let customBg = plugin.previewBackground() {
      customBg
    } else {
      palette.elevatedContentSurface
    }
  }

  @ViewBuilder
  private var pluginSigil: some View {
    if let customIcon = plugin.iconView() {
      customIcon
    } else {
      Image(systemName: "puzzlepiece.fill")
        .foregroundStyle(palette.accent)
    }
  }
}

// MARK: - Detailed Plugin Page Sheet
struct PluginDetailsView: View {
  let plugin: any MaxPlugin

  @Environment(\.maxThemePalette) private var palette
  @Environment(\.dismiss) private var dismiss

  @State private var progress: Double = 0.0
  @State private var isInstalling = false

  var body: some View {
    VStack(spacing: 0) {
      // Header details card
      ZStack(alignment: .bottomLeading) {
        headerPreviewBackground
          .frame(height: 180)
        
        HStack(spacing: MaxSpace.md) {
          pluginSigilLarge
            .frame(width: 72, height: 72)
            .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
              RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
          
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: plugin.manifest.name)
              .font(.title2.weight(.black))
              .foregroundStyle(.white)
            
            Text(verbatim: "Version \(plugin.manifest.version) | By \(plugin.manifest.author.name)")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.8))
          }
        }
        .padding(MaxSpace.md)
      }
      
      ScrollView {
        VStack(alignment: .leading, spacing: MaxSpace.md) {
          
          // Action button (Install/Apply)
          actionSection
            .padding(.top, MaxSpace.xs)
          
          // Description
          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text("plugin.store.description")
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            Text(verbatim: plugin.manifest.longDescription ?? plugin.manifest.description)
              .font(.body)
              .foregroundStyle(palette.secondaryText)
              .lineSpacing(4)
          }

          Divider()
            .background(palette.separator)

          // Changes list
          VStack(alignment: .leading, spacing: MaxSpace.xs) {
            Text("plugin.store.what_it_changes")
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            
            ForEach(plugin.manifest.capabilities, id: \.rawValue) { capability in
              HStack(spacing: MaxSpace.xs) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(palette.success)
                Text(verbatim: capability.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                  .font(.subheadline)
                  .foregroundStyle(palette.secondaryText)
              }
            }
          }

          Divider()
            .background(palette.separator)

          // Security & Permissions
          VStack(alignment: .leading, spacing: MaxSpace.xs) {
            Text("plugin.store.permissions_security")
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            
            ForEach(plugin.manifest.permissions, id: \.rawValue) { permission in
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: permission.localizedTitle.uppercased())
                  .font(.caption.weight(.bold))
                  .foregroundStyle(palette.accent)
                Text(verbatim: permission.userDescription)
                  .font(.caption2)
                  .foregroundStyle(palette.tertiaryText)
              }
              .padding(.leading, MaxSpace.xs)
            }
            
            if plugin.manifest.permissions.isEmpty {
              Text("plugin.store.no_permissions")
                .font(.caption)
                .foregroundStyle(palette.tertiaryText)
            }
          }

          // Custom configuration settings view if installed
          if PluginStore.shared.installedPluginIds.contains(plugin.manifest.id) {
            Divider()
              .background(palette.separator)
            
            plugin.settingsView()
          }
        }
        .padding(MaxSpace.md)
      }
    }
    .background(palette.canvas)
    .ignoresSafeArea(edges: .top)
  }

  @ViewBuilder
  private var actionSection: some View {
    let id = plugin.manifest.id
    let isInstalled = PluginStore.shared.installedPluginIds.contains(id)
    
    if isInstalling {
      HStack {
        ProgressView(value: progress, total: 1.0)
          .tint(palette.accent)
        Text(verbatim: "\(Int(progress * 100))%")
          .font(.caption.weight(.bold))
      }
      .padding()
    } else if !isInstalled {
      Button {
        isInstalling = true
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
          progress += 0.15
          if progress >= 1.0 {
            timer.invalidate()
            Task {
              await PluginStore.shared.install(pluginId: id)
              isInstalling = false
              progress = 0.0
            }
          }
        }
      } label: {
        Text("plugin.action.install")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding()
          .background(palette.accent, in: Capsule())
      }
    } else {
      if plugin.manifest.capabilities.contains(.theme) {
        let isActive = PluginStore.shared.activeVisualPluginId == id
        Button {
          dismiss()
          if isActive {
            PluginStore.shared.deactivateVisualPlugin()
          } else {
            PluginTakeoverCoordinator.shared.startTakeover(targetPluginId: id)
          }
        } label: {
          Text(isActive ? "plugin.action.deactivate_style" : "plugin.action.apply_theme")
            .font(.headline)
            .foregroundStyle(isActive ? palette.accent : .white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? palette.selectedControl : palette.accent, in: Capsule())
        }
      } else {
        let isActive = PluginStore.shared.activeFeaturePluginIds.contains(id)
        Button {
          PluginStore.shared.toggleFeaturePlugin(id)
        } label: {
          Text(isActive ? "plugin.action.disable_feature" : "plugin.action.enable_feature")
            .font(.headline)
            .foregroundStyle(isActive ? palette.accent : .white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? palette.selectedControl : palette.accent, in: Capsule())
        }
      }
    }
  }

  @ViewBuilder
  private var headerPreviewBackground: some View {
    if let customBg = plugin.previewBackground() {
      customBg
    } else {
      palette.elevatedContentSurface
    }
  }

  @ViewBuilder
  private var pluginSigilLarge: some View {
    if let customIcon = plugin.iconView() {
      customIcon
    } else {
      Image(systemName: "puzzlepiece.fill")
        .font(.largeTitle)
        .foregroundStyle(palette.accent)
    }
  }
}

// MARK: - Safe Developer Diagnostics Console
struct PluginDebugConsoleView: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("plugin.store.dev_diagnostics")
          .font(.headline)
          .foregroundStyle(.white)
        Spacer()
        Button(action: {
          dismiss()
        }) {
          Text("plugin.store.close")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.accent)
        }
      }
      .padding()
      .background(Color(white: 0.1))
      
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(PluginStore.shared.diagnosticLogs, id: \.self) { log in
            Text(verbatim: log)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(log.contains("WARN") ? .orange : (log.contains("ERR") ? .red : .green))
              .padding(.horizontal, 8)
          }
        }
        .padding(.vertical)
      }
      .background(Color.black)
    }
  }
}


