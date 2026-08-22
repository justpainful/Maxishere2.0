import SwiftUI

private enum SharedMode: String, CaseIterable, Identifiable {
  case files
  case spaces
  var id: String { rawValue }
}

struct SharedView: View {
  @Environment(MaxDesktopModel.self) private var model
  @State private var mode: SharedMode = .files
  @State private var query = ""
  @State private var presentedWorkspace: Workspace?

  private var sharedMedia: [MediaItem] {
    model.media.filter { item in
      !item.isTrashed && item.workspaceID != nil
        && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
    }
  }

  var body: some View {
    let palette = model.palette

    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        GlassCard(tint: palette.secondaryAccent) {
          HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
              Text(model.copy("shared"))
                .font(.system(size: 38, weight: .bold, design: .rounded))
              Text("Files and spaces you share with people you trust.")
                .font(.title3)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            SharedMetric(value: "\(sharedMedia.count)", label: model.copy("files"), symbol: "doc.on.doc.fill", tint: palette.accent)
            SharedMetric(value: "\(model.workspaces.count)", label: model.copy("spaces"), symbol: "person.3.fill", tint: palette.secondaryAccent)
          }
          .padding(24)
        }

        Picker("Shared", selection: $mode) {
          ForEach(SharedMode.allCases) { option in
            Text(model.copy(option.rawValue)).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        .accessibilityIdentifier("mac_shared_mode")

        if mode == .files {
          filesGrid
        } else {
          spacesGrid
        }
      }
      .padding(28)
    }
    .searchable(text: $query, placement: .toolbar, prompt: model.copy("search"))
    .navigationTitle(model.copy("shared"))
    .accessibilityIdentifier("mac_shared_screen")
    .sheet(item: $presentedWorkspace) { workspace in
      WorkspaceDetailView(workspace: workspace)
        .environment(model)
    }
  }

  private var filesGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
      ForEach(sharedMedia) { item in
        SharedFileCard(item: item)
          .environment(model)
      }
    }
    .accessibilityIdentifier("mac_shared_files")
  }

  private var spacesGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18)], spacing: 18) {
      ForEach(model.workspaces.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { workspace in
        Button {
          presentedWorkspace = workspace
        } label: {
          GlassCard(tint: Color(hue: workspace.hue, saturation: 0.75, brightness: 0.92)) {
            VStack(alignment: .leading, spacing: 18) {
              HStack {
                Image(systemName: "person.3.fill")
                  .font(.system(size: 28))
                  .foregroundStyle(Color(hue: workspace.hue, saturation: 0.7, brightness: 0.95))
                Spacer()
                Text("\(workspace.itemIDs.count) items")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(model.palette.textSecondary)
              }
              Text(workspace.name)
                .font(.title2.bold())
              Text(workspace.summary)
                .foregroundStyle(model.palette.textSecondary)
                .lineLimit(2)
              HStack {
                HStack(spacing: -8) {
                  ForEach(Array(workspace.memberNames.enumerated()), id: \.offset) { index, member in
                    Circle()
                      .fill(Color(hue: (workspace.hue + Double(index) * 0.17).truncatingRemainder(dividingBy: 1), saturation: 0.60, brightness: 0.88))
                      .frame(width: 31, height: 31)
                      .overlay(Text(member.prefix(1)).font(.caption.bold()).foregroundStyle(.white))
                      .overlay(Circle().stroke(model.palette.solidSurface, lineWidth: 2))
                  }
                }
                Spacer()
                Image(systemName: "chevron.right")
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac_workspace_\(workspace.id)")
      }
    }
    .accessibilityIdentifier("mac_shared_spaces")
  }
}

private struct SharedMetric: View {
  let value: String
  let label: String
  let symbol: String
  let tint: Color

  var body: some View {
    VStack(spacing: 5) {
      Label(value, systemImage: symbol).font(.title2.bold()).foregroundStyle(tint)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(minWidth: 90)
  }
}

private struct SharedFileCard: View {
  @Environment(MaxDesktopModel.self) private var model
  let item: MediaItem

  var body: some View {
    Button { model.open(item) } label: {
      VStack(alignment: .leading, spacing: 0) {
        MediaArtwork(item: item)
          .frame(height: 130)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(item.title).font(.headline).lineLimit(1)
            Spacer()
            Image(systemName: "person.2.fill").foregroundStyle(model.palette.accent)
          }
          Text(item.subtitle).font(.caption).foregroundStyle(model.palette.textSecondary)
          HStack {
            Text("Can view").font(.caption2.weight(.semibold))
            Spacer()
            Button { } label: { Image(systemName: "paperplane.fill") }
              .buttonStyle(.borderless)
              .accessibilityLabel("Send to chat")
          }
        }
        .padding(14)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 19))
    .accessibilityIdentifier("mac_shared_file_\(item.id)")
  }
}

private struct WorkspaceDetailView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let workspace: Workspace

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text(workspace.name).font(.largeTitle.bold())
            Text(workspace.summary).foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Button { dismiss() } label: { Image(systemName: "xmark") }
            .buttonStyle(.glass)
            .accessibilityLabel(model.copy("done"))
        }
        .padding(26)

        Divider().opacity(0.35)

        HStack(alignment: .top, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Members").font(.title3.bold())
            ForEach(workspace.memberNames, id: \.self) { member in
              Label(member, systemImage: "person.crop.circle.fill")
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
            Button("Manage Members") { }
              .buttonStyle(.glass)
          }
          .frame(width: 240)

          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
              ForEach(model.media.filter { workspace.itemIDs.contains($0.id) }) { item in
                MediaTile(item: item).environment(model)
              }
            }
          }
        }
        .padding(26)
      }
    }
    .frame(width: 960, height: 680)
    .accessibilityIdentifier("mac_workspace_detail")
  }
}

