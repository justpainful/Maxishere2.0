import SwiftUI

struct ProfileView: View {
  @Environment(MaxDesktopModel.self) private var model

  var body: some View {
    let palette = model.palette

    ScrollView {
      VStack(spacing: 22) {
        profileHero(palette: palette)
        statsGrid(palette: palette)

        HStack(alignment: .top, spacing: 20) {
          favorites(palette: palette)
            .frame(maxWidth: .infinity)
          accountPanel(palette: palette)
            .frame(width: 310)
        }
      }
      .padding(28)
    }
    .navigationTitle(model.copy("profile"))
    .accessibilityIdentifier("mac_profile_screen")
  }

  private func profileHero(palette: MaxPalette) -> some View {
    GlassCard(tint: palette.accent) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(
          colors: [palette.accent.opacity(0.82), palette.secondaryAccent.opacity(0.72), .clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .frame(height: 240)

        HStack(alignment: .bottom, spacing: 22) {
          ZStack {
            Circle()
              .fill(LinearGradient(colors: [palette.accent, palette.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(model.profile.displayName.prefix(1))
              .font(.system(size: 48, weight: .bold))
              .foregroundStyle(.white)
          }
          .frame(width: 112, height: 112)
          .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 4))
          .shadow(radius: 18, y: 10)

          VStack(alignment: .leading, spacing: 6) {
            Text(model.profile.displayName)
              .font(.system(size: 33, weight: .bold, design: .rounded))
            Text("@\(model.profile.username)")
              .font(.title3)
              .foregroundStyle(palette.textSecondary)
            Text(model.profile.bio)
              .foregroundStyle(palette.textSecondary)
              .lineLimit(2)
          }
          Spacer()
          Button {
            model.isProfileEditorPresented = true
          } label: {
            Label(model.copy("editProfile"), systemImage: "pencil")
          }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("mac_profile_edit")
        }
        .padding(26)
      }
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
  }

  private func statsGrid(palette: MaxPalette) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
      ProfileMetric(value: "\(model.profile.totalItems)", label: "Items", symbol: "square.stack.3d.up.fill", tint: palette.accent)
      ProfileMetric(value: "\(model.profile.watchHours)h", label: "Watch time", symbol: "play.circle.fill", tint: palette.secondaryAccent)
      ProfileMetric(value: "\(model.media.filter(\.isSaved).count)", label: model.copy("saved"), symbol: "bookmark.fill", tint: .pink)
      ProfileMetric(value: "\(model.profile.sharedSpaces)", label: model.copy("spaces"), symbol: "person.3.fill", tint: .cyan)
      ProfileMetric(value: String(format: "%.1f GB", model.profile.storageUsedGB), label: "Storage", symbol: "internaldrive.fill", tint: .green)
    }
  }

  private func favorites(palette: MaxPalette) -> some View {
    GlassCard(tint: .pink) {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Label("Favorites", systemImage: "heart.fill").font(.title2.bold()).foregroundStyle(.pink)
          Spacer()
          Button("View all") { model.selectedDestination = .library; model.selectedLibrarySection = .saved }
            .buttonStyle(.glass)
        }
        ForEach(model.media.filter { $0.isSaved && !$0.isTrashed }.prefix(4)) { item in
          Button { model.open(item) } label: {
            HStack(spacing: 12) {
              MediaArtwork(item: item, compact: true)
                .frame(width: 78, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
              VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.subtitle).font(.caption).foregroundStyle(palette.textSecondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(20)
    }
  }

  private func accountPanel(palette: MaxPalette) -> some View {
    GlassCard(tint: palette.secondaryAccent) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Account").font(.title2.bold())
        Label(model.profile.email, systemImage: "envelope.fill")
          .foregroundStyle(palette.textSecondary)
        Divider()
        SettingsLink {
          Label(model.copy("settings"), systemImage: "gearshape.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("mac_profile_settings")
        Button {
          model.selectedDestination = .plugins
        } label: {
          Label(model.copy("plugins"), systemImage: "puzzlepiece.extension.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        Button(role: .destructive) {
          model.signOut()
        } label: {
          Label(model.copy("signOut"), systemImage: "rectangle.portrait.and.arrow.right")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("mac_profile_signout")
      }
      .padding(20)
    }
  }
}

private struct ProfileMetric: View {
  let value: String
  let label: String
  let symbol: String
  let tint: Color

  var body: some View {
    GlassCard(tint: tint) {
      VStack(alignment: .leading, spacing: 9) {
        Image(systemName: symbol).font(.title2).foregroundStyle(tint)
        Text(value).font(.title.bold())
        Text(label).font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
    }
  }
}

struct ProfileEditorView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var draft = MaxFixtures.profile

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)
      VStack(spacing: 0) {
        HStack {
          Text(model.copy("editProfile")).font(.largeTitle.bold())
          Spacer()
          Button(model.copy("cancel")) { dismiss() }.buttonStyle(.glass)
          Button(model.copy("save")) { model.saveProfile(draft) }.buttonStyle(.glassProminent)
            .accessibilityIdentifier("mac_profile_save")
        }
        .padding(24)
        Divider().opacity(0.35)
        Form {
          Section("Identity") {
            TextField("Display name", text: $draft.displayName)
              .accessibilityIdentifier("mac_profile_name")
            TextField("Username", text: $draft.username)
              .accessibilityIdentifier("mac_profile_username")
            TextField("Email", text: $draft.email)
          }
          Section("About") {
            TextEditor(text: $draft.bio)
              .frame(minHeight: 100)
              .accessibilityIdentifier("mac_profile_bio")
          }
          Section("Artwork") {
            HStack {
              Button("Choose Avatar…") { }.buttonStyle(.glass)
              Button("Choose Header…") { }.buttonStyle(.glass)
              Text("Demo artwork stays on this Mac.").foregroundStyle(palette.textSecondary)
            }
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
      }
    }
    .frame(width: 720, height: 620)
    .onAppear { draft = model.profile }
    .accessibilityIdentifier("mac_profile_editor")
  }
}

