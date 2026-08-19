import SwiftUI
import AVKit

struct ClipContentView: View {
  let content: ResolvedShareContent
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 24) {
          switch content.type {
          case "video":
            if let file = content.file, let urlString = file.mediaUrl, let url = URL(string: urlString) {
              VideoDetailView(file: file, url: url)
            } else {
              ErrorStateView(message: "Video URL is missing")
            }
          case "image":
            if let file = content.file, let urlString = file.mediaUrl, let url = URL(string: urlString) {
              ImageDetailView(file: file, url: url)
            } else {
              ErrorStateView(message: "Image URL is missing")
            }
          case "memory":
            if let memory = content.memory {
              MemoryDetailView(memory: memory)
            } else {
              ErrorStateView(message: "Memory metadata is missing")
            }
          case "profile":
            if let profile = content.profile {
              ProfileDetailView(profile: profile)
            } else {
              ErrorStateView(message: "Profile metadata is missing")
            }
          case "collection":
            if let collection = content.collection {
              CollectionDetailView(collection: collection)
            } else {
              ErrorStateView(message: "Collection metadata is missing")
            }
          default:
            ErrorStateView(message: "Unsupported shared content type: \(content.type)")
          }
        }
        .padding(.bottom, 120)
      }

      Spacer()
    }
    .overlay(alignment: .bottom) {
      VStack(spacing: 0) {
        Divider()
          .background(Color(white: 0.15))

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("clip.viewed_via")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.gray)
            Text("clip.full_app_prompt")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.white)
          }

          Spacer()

          if let appURL = URL(string: "max://c/\(content.share.token)") {
            Link(destination: appURL) {
              Text("clip.open_max")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(12)
            }
          }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(red: 0.05, green: 0.09, blue: 0.16).opacity(0.95))
        .background(Material.ultraThinMaterial)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.03, green: 0.07, blue: 0.12))
  }
}

struct VideoDetailView: View {
  let file: ClipFileMetadata
  let url: URL

  var body: some View {
    VStack(spacing: 16) {
      VideoPlayer(player: AVPlayer(url: url))
        .aspectRatio(16/9, contentMode: .fit)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .shadow(radius: 10)

      VStack(alignment: .leading, spacing: 8) {
        Text(file.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)

        Text("Shared Video • \((Double(file.sizeBytes) / 1024 / 1024).formatted(.number.precision(.fractionLength(2)))) MB")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
    }
  }
}

struct ImageDetailView: View {
  let file: ClipFileMetadata
  let url: URL

  var body: some View {
    VStack(spacing: 16) {
      AsyncImage(url: url) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fit)
          .cornerRadius(16)
          .padding(.horizontal, 16)
          .shadow(radius: 10)
      } placeholder: {
        ProgressView()
          .tint(.blue)
          .frame(height: 200)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(file.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)

        Text("Shared Image • \((Double(file.sizeBytes) / 1024 / 1024).formatted(.number.precision(.fractionLength(2)))) MB")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
    }
  }
}

struct MemoryDetailView: View {
  let memory: ClipMemoryMetadata

  var body: some View {
    VStack(spacing: 20) {
      if let thumbString = memory.thumbnailUrl ?? memory.mediaUrl, let url = URL(string: thumbString) {
        AsyncImage(url: url) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 320)
            .clipped()
            .cornerRadius(24)
            .padding(.horizontal, 16)
            .shadow(radius: 10)
        } placeholder: {
          ProgressView()
            .tint(.blue)
            .frame(height: 320)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        if let owner = memory.owner {
          HStack(spacing: 8) {
            Circle()
              .fill(Color.blue)
              .frame(width: 24, height: 24)
              .overlay {
                Text(String(owner.displayName?.first ?? "M"))
                  .font(.system(size: 11, weight: .bold))
                  .foregroundColor(.white)
              }

            Text(owner.displayName ?? "Max Member")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.gray)
          }
        }

        Text(memory.title)
          .font(.system(size: 24, weight: .black, design: .rounded))
          .foregroundColor(.white)

        if let desc = memory.description {
          Text(desc)
            .font(.system(size: 15))
            .foregroundColor(Color(white: 0.7))
            .lineSpacing(4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
    }
  }
}

struct ProfileDetailView: View {
  let profile: ClipProfileMetadata

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .bottomLeading) {
        Rectangle()
          .fill(LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(height: 180)

        Circle()
          .fill(Color(white: 0.12))
          .frame(width: 88, height: 88)
          .overlay {
            Text(String(profile.displayName?.first ?? "@"))
              .font(.system(size: 36, weight: .black))
              .foregroundColor(.white)
          }
          .offset(x: 24, y: 44)
      }
      .padding(.bottom, 48)

      VStack(alignment: .leading, spacing: 12) {
        Text(profile.displayName ?? "@\(profile.handle)")
          .font(.system(size: 26, weight: .black))
          .foregroundColor(.white)

        Text("@\(profile.handle)")
          .font(.system(size: 14, weight: .bold, design: .monospaced))
          .foregroundColor(.blue)

        if let bio = profile.bio, !bio.isEmpty {
          Text(bio)
            .font(.system(size: 15))
            .foregroundColor(Color(white: 0.8))
            .lineSpacing(4)
            .padding(.top, 4)
        }

        HStack(spacing: 20) {
          HStack(spacing: 4) {
            Text("\(profile.followerCount ?? 0)")
              .font(.system(size: 14, weight: .bold))
              .foregroundColor(.white)
            Text("clip.followers")
              .font(.system(size: 14))
              .foregroundColor(.gray)
          }
        }
        .padding(.top, 8)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
    }
  }
}

struct CollectionDetailView: View {
  let collection: ClipCollectionMetadata

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(collection.title)
        .font(.system(size: 24, weight: .black))
        .foregroundColor(.white)
        .padding(.horizontal, 24)

      if let owner = collection.owner {
        Text("Created by \(owner.displayName ?? "Member")")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.gray)
          .padding(.horizontal, 24)
      }

      VStack(spacing: 12) {
        ForEach(collection.items) { item in
          HStack(spacing: 16) {
            Rectangle()
              .fill(Color(white: 0.15))
              .frame(width: 60, height: 45)
              .cornerRadius(8)
              .overlay {
                Image(systemName: "video")
                  .foregroundColor(.gray)
              }

            VStack(alignment: .leading, spacing: 4) {
              Text(item.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
              Text("Video • \((Double(item.sizeBytes) / 1024 / 1024).formatted(.number.precision(.fractionLength(2)))) MB")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            }

            Spacer()
          }
          .padding()
          .background(Color(white: 0.08))
          .cornerRadius(16)
          .padding(.horizontal, 16)
        }
      }
    }
  }
}

struct ErrorStateView: View {
  let message: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.amber)
      Text(message)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
    .padding(.vertical, 60)
  }
}

extension Color {
  static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
}
