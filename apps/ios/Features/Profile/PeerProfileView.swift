import Foundation
import SwiftUI

/// Another user's profile — who they are, and the slice of their uploads the
/// VIEWER is allowed to see. The media request runs through the same visibility
/// rules as the vault (`media?ownerId=`), so the server decides what appears
/// here, never the client. Presented as a sheet from anywhere a person's name
/// or avatar is on screen (chat details, member lists).
struct PeerProfileView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let userID: String

  @State private var profile: MaxV2Profile?
  @State private var stats: MaxV2PeerStats?
  @State private var items: [MaxMediaItem] = []
  @State private var failureReason: String?
  @State private var isLoading = true

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MaxSpace.md) {
          if let profile {
            header(profile)
            if let stats { factsSection(stats) }
            mediaSection
          } else if isLoading {
            ProgressView()
              .controlSize(.large)
              .frame(maxWidth: .infinity)
              .padding(.top, MaxSpace.xl * 2)
          } else if let failureReason {
            ContentUnavailableView {
              Label("Couldn't load profile", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
              Text(failureReason)
            } actions: {
              Button("Retry") { Task { await load() } }
            }
            .padding(.top, MaxSpace.xl)
          }
        }
        .padding(.bottom, MaxSpace.xl)
      }
      .navigationTitle("Profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .task { await load() }
      .maxScreenBackground()
    }
  }

  private func load() async {
    isLoading = true
    failureReason = nil
    do {
      let wire = try await model.apiClient.peerProfile(userID: userID)
      var query = MediaQuery()
      query.mode = "peer-profile"
      query.ownerId = userID
      query.limit = 60
      let page = try await model.apiClient.media(query: query)
      profile = wire
      items = page.items
      // Settled on its own: a profile is still a profile without its numbers,
      // and losing the whole page over a strip of figures would be a downgrade.
      stats = try? await model.apiClient.peerProfileStats(userID: userID)
    } catch {
      failureReason = ProductError.from(error, area: .profile).reason
    }
    isLoading = false
  }

  // MARK: - Facts

  /// What this viewer is allowed to know about this person. Counts arrive
  /// already scoped by the server to what they can see, so nothing here can
  /// reveal a private item by counting it — and there is deliberately no watch
  /// history, which is the one thing a shared vault still does not make shared.
  private func factsSection(_ stats: MaxV2PeerStats) -> some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      if let role = Self.roleLabel(stats.role) {
        Text(role)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(MaxColor.accent.opacity(0.16), in: Capsule())
          .foregroundStyle(MaxColor.accent)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: MaxSpace.sm)], spacing: MaxSpace.sm) {
        fact("calendar", "Joined", Self.dateOnly(stats.joinedAt))
        fact("square.and.arrow.up.on.square", "Uploads", stats.uploads.formatted())
        fact("internaldrive", "Contributed", ByteCountFormatter.string(fromByteCount: stats.uploadBytes, countStyle: .file))
        if stats.videos > 0 { fact("film", "Videos", stats.videos.formatted()) }
        if stats.photos > 0 { fact("photo", "Photos", stats.photos.formatted()) }
        if stats.ratedCount > 0 { fact("star.fill", "Rated", stats.ratedCount.formatted()) }
        if let average = stats.averageScore, stats.ratedCount > 0 {
          fact("chart.bar", "Average", String(format: "%.1f", average))
        }
        if stats.favoriteCount > 0 { fact("heart.fill", "Favorites", stats.favoriteCount.formatted()) }
        if stats.sharedChats > 0 { fact("bubble.left.and.bubble.right", "Shared chats", stats.sharedChats.formatted()) }
        if let last = stats.lastUploadAt { fact("clock", "Last upload", Self.dateOnly(last)) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, MaxSpace.md)
    .accessibilityIdentifier("ui_peer_facts")
  }

  private func fact(_ symbol: String, _ label: String, _ value: String) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: symbol)
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text(value).font(.subheadline.weight(.semibold))
        Text(label).font(.caption2).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  /// "member" is everybody, so it says nothing worth a badge.
  private static func roleLabel(_ role: String) -> String? {
    switch role {
    case "developer": return "Developer"
    case "admin": return "Admin"
    default: return nil
    }
  }

  /// A calendar date, no clock: "Joined 12 Mar 2026" is a fact about a person,
  /// "joined 4 months ago" is a countdown.
  private static func dateOnly(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return "" }
    return date.formatted(.dateTime.year().month(.abbreviated).day())
  }

  // MARK: - Header

  private func header(_ profile: MaxV2Profile) -> some View {
    VStack(spacing: MaxSpace.sm) {
      ZStack(alignment: .bottomLeading) {
        coverImage(profile.coverUrl)
        avatarImage(profile.avatarUrl, name: profile.displayName)
          .offset(x: MaxSpace.lg, y: 36)
      }
      .padding(.bottom, 36)

      VStack(spacing: 2) {
        Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
          .font(.title2.bold())
          .multilineTextAlignment(.center)
        if !profile.username.isEmpty {
          Text(verbatim: "@\(profile.username)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity)

      if !profile.bio.isEmpty {
        Text(profile.bio)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, MaxSpace.lg)
      }
    }
  }

  @ViewBuilder
  private func coverImage(_ url: URL?) -> some View {
    Group {
      if let url {
        MaxAsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          default:
            LinearGradient(
              colors: [MaxColor.accent.opacity(0.55), MaxColor.accent.opacity(0.2)],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          }
        }
      } else {
        LinearGradient(
          colors: [MaxColor.accent.opacity(0.55), MaxColor.accent.opacity(0.2)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
      }
    }
    .frame(height: 150)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .padding(.horizontal, MaxSpace.md)
  }

  @ViewBuilder
  private func avatarImage(_ url: URL?, name: String) -> some View {
    Group {
      if let url {
        MaxAsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          default:
            avatarFallback(name)
          }
        }
      } else {
        avatarFallback(name)
      }
    }
    .frame(width: 84, height: 84)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(.background, lineWidth: 3)
    )
  }

  private func avatarFallback(_ name: String) -> some View {
    ZStack {
      MaxColor.accent.opacity(0.3)
      Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
        .font(.largeTitle.bold())
        .foregroundStyle(MaxColor.accent)
    }
  }

  // MARK: - Media grid

  @ViewBuilder
  private var mediaSection: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      Text("Files you can view")
        .font(.headline)
        .padding(.horizontal, MaxSpace.md)

      if items.isEmpty {
        ContentUnavailableView {
          Label("Nothing visible yet", systemImage: "square.grid.2x2")
        } description: {
          Text("When they share files with you or a shared space, they appear here.")
        }
        .padding(.top, MaxSpace.md)
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
          ForEach(items) { item in
            mediaTile(item)
          }
        }
        .padding(.horizontal, MaxSpace.md)
      }
    }
  }

  private func mediaTile(_ item: MaxMediaItem) -> some View {
    Button {
      model.openPlayer(for: item, in: items)
    } label: {
      ZStack(alignment: .bottomTrailing) {
        Rectangle()
          .fill(.quaternary)
          .aspectRatio(1, contentMode: .fit)
          .overlay {
            if let poster = item.posterURL {
              MaxAsyncImage(url: poster) { phase in
                switch phase {
                case .success(let image):
                  image.resizable().scaledToFill()
                default:
                  Image(systemName: item.kind.lowercased() == "video" ? "film" : "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }
              }
            } else {
              Image(systemName: item.kind.lowercased() == "video" ? "film" : "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
            }
          }
          .clipped()
        if item.kind.lowercased() == "video" {
          Image(systemName: "play.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.55), in: Circle())
            .padding(5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.displayTitle)
  }
}
