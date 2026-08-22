import SwiftUI

struct MemoriesView: View {
  @Environment(MaxDesktopModel.self) private var model
  @State private var selection = "Featured"

  var body: some View {
    let palette = model.palette

    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        GlassCard(tint: .orange) {
          HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
              Label(model.copy("memories"), systemImage: "sparkles")
                .font(.system(size: 38, weight: .bold, design: .rounded))
              Text("Private, on-device moments resurfaced with care.")
                .font(.title3)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "photo.stack.fill")
              .font(.system(size: 62))
              .foregroundStyle(.orange)
          }
          .padding(26)
        }

        Picker("Memories", selection: $selection) {
          Text("Featured").tag("Featured")
          Text("Timeline").tag("Timeline")
          Text("Places").tag("Places")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
          ForEach(model.memories) { memory in
            GlassCard(tint: Color(hue: memory.hue, saturation: 0.7, brightness: 0.92)) {
              VStack(alignment: .leading, spacing: 16) {
                ZStack {
                  LinearGradient(
                    colors: [Color(hue: memory.hue, saturation: 0.72, brightness: 0.94), Color(hue: memory.hue, saturation: 0.82, brightness: 0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  )
                  Image(systemName: memory.symbol)
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(memory.title).font(.title3.bold())
                HStack {
                  Label(memory.location, systemImage: "location.fill")
                  Spacer()
                  Text(memory.date, format: .dateTime.year().month(.abbreviated))
                }
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
              }
              .padding(14)
            }
          }
        }
      }
      .padding(28)
    }
    .navigationTitle(model.copy("memories"))
    .accessibilityIdentifier("mac_memories_screen")
  }
}

struct PluginStoreView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    let palette = model.palette

    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          VStack(alignment: .leading, spacing: 7) {
            Text(model.copy("plugins"))
              .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("Extend Max with scoped, reviewable capabilities.")
              .font(.title3)
              .foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Label("Safe Mode Ready", systemImage: "checkmark.shield.fill")
            .foregroundStyle(.green)
            .padding(10)
            .glassEffect(.regular, in: .capsule)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
          ForEach(model.plugins) { plugin in
            GlassCard(tint: Color(hue: plugin.hue, saturation: 0.74, brightness: 0.94)) {
              VStack(alignment: .leading, spacing: 16) {
                HStack {
                  Image(systemName: plugin.symbol)
                    .font(.system(size: 29))
                    .foregroundStyle(Color(hue: plugin.hue, saturation: 0.72, brightness: 0.95))
                  Spacer()
                  Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { _ in model.togglePlugin(plugin.id) }
                  ))
                  .labelsHidden()
                }
                Text(plugin.name).font(.title3.bold())
                Text(plugin.summary)
                  .foregroundStyle(palette.textSecondary)
                  .lineLimit(2)
                HStack {
                  Label(plugin.isEnabled ? "Enabled" : "Not installed", systemImage: plugin.isEnabled ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                  Spacer()
                  Button("Details") { }.buttonStyle(.glass)
                }
              }
              .padding(19)
            }
            .accessibilityIdentifier("mac_plugin_\(plugin.id)")
          }
        }
      }
      .padding(28)
    }
    .navigationTitle(model.copy("plugins"))
    .accessibilityIdentifier("mac_plugins_screen")
  }
}

struct UploadSheetView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var destination = "Personal Vault"
  @State private var privacy = "Private"

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(model.copy("upload")).font(.largeTitle.bold())
            Text("Add files to Max without leaving this window.").foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
        }

        Button { } label: {
          VStack(spacing: 14) {
            Image(systemName: "arrow.up.doc.fill").font(.system(size: 42)).foregroundStyle(palette.accent)
            Text("Drop files here or choose from Finder").font(.title3.bold())
            Text("Images, videos, and documents up to 10 GB").foregroundStyle(palette.textSecondary)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 190)
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac_upload_dropzone")

        Form {
          Picker("Destination", selection: $destination) {
            Text("Personal Vault").tag("Personal Vault")
            ForEach(model.workspaces) { Text($0.name).tag($0.name) }
          }
          Picker("Access", selection: $privacy) {
            Text("Private").tag("Private")
            Text("Workspace members").tag("Workspace members")
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)

        HStack {
          Text("Demo upload creates a local transfer record.").font(.caption).foregroundStyle(palette.textSecondary)
          Spacer()
          Button(model.copy("cancel")) { dismiss() }.buttonStyle(.glass)
          Button("Upload Demo File") { model.beginDemoUpload() }.buttonStyle(.glassProminent)
            .accessibilityIdentifier("mac_upload_start")
        }
      }
      .padding(28)
    }
    .frame(width: 760, height: 650)
    .accessibilityIdentifier("mac_upload_sheet")
  }
}

struct TransfersView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let palette = model.palette

    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(model.copy("transfers")).font(.largeTitle.bold())
        Spacer()
        Button("Complete Demo") { model.completeTransfers() }.buttonStyle(.glass)
        Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
      }
      if model.transfers.isEmpty {
        EmptyStateView(symbol: "arrow.up.arrow.down.circle", title: "No active transfers", message: "Uploads and downloads appear here.")
      } else {
        ForEach(model.transfers) { transfer in
          GlassCard(tint: transfer.state == .complete ? .green : palette.accent) {
            HStack(spacing: 14) {
              Image(systemName: transfer.state == .complete ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(transfer.state == .complete ? .green : palette.accent)
              VStack(alignment: .leading, spacing: 7) {
                Text(transfer.title).font(.headline)
                ProgressView(value: transfer.progress)
                Text(transfer.state.rawValue.capitalized).font(.caption).foregroundStyle(palette.textSecondary)
              }
            }
            .padding(16)
          }
        }
        Spacer()
      }
    }
    .padding(26)
    .frame(width: 620, height: 460)
    .accessibilityIdentifier("mac_transfers_sheet")
  }
}

struct CommandPaletteView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    VStack(spacing: 14) {
      HStack {
        Image(systemName: "magnifyingglass")
        TextField("Search Max or run a command", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .accessibilityIdentifier("mac_command_query")
        Text("⌘K").font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      .padding(15)
      .glassEffect(.regular, in: .rect(cornerRadius: 16))

      VStack(spacing: 8) {
        ForEach(SidebarDestination.allCases.filter { query.isEmpty || model.copy($0.rawValue).localizedCaseInsensitiveContains(query) }) { destination in
          Button {
            model.selectedDestination = destination
            dismiss()
          } label: {
            HStack {
              Label(model.copy(destination.rawValue), systemImage: destination.symbol)
              Spacer()
              Text("Open").font(.caption).foregroundStyle(.secondary)
            }
            .padding(11)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        Divider()
        Button {
          model.isUploadPresented = true
          dismiss()
        } label: {
          HStack { Label(model.copy("upload"), systemImage: "plus"); Spacer(); Text("⌘U").font(.caption.monospaced()) }
            .padding(11)
        }
        .buttonStyle(.plain)
      }
      .padding(8)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      Spacer()
    }
    .padding(22)
    .frame(width: 620, height: 540)
    .accessibilityIdentifier("mac_command_palette")
  }
}

