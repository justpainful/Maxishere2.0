import SwiftUI

struct ClipRootView: View {
  let invocationURL: URL?

  @State private var shareToken: String = ""
  // Never hardcode an origin here: the clip shipped pinned to a quick tunnel
  // that had already been torn down. MaxConfiguration resolves the build-time
  // MAX_API_BASE_URL, falling back to the stable production origin.
  @State private var apiBaseURL: String = MaxConfiguration.fromBundle().baseURL.absoluteString
  @State private var resolvedContent: ResolvedShareContent? = nil
  @State private var isLoading = false
  @State private var errorMessage: String? = nil

  var body: some View {
    NavigationStack {
      VStack {
        if isLoading {
          ProgressView("Retrieving Secure Archive...")
            .tint(.blue)
            .foregroundColor(.gray)
        } else if let content = resolvedContent {
          ClipContentView(content: content)
        } else {
          // Manual Token Input for Local Testing & Fallback
          VStack(spacing: 24) {
            Image(systemName: "bolt.shield")
              .font(.system(size: 64))
              .foregroundColor(.blue)
              .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

            Text("clip.name")
              .font(.system(size: 28, weight: .black, design: .rounded))
              .foregroundColor(.white)

            Text("clip.share_token_prompt")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.gray)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 32)

            VStack(spacing: 12) {
              TextField("Enter Share Token (e.g., demo-video)", text: $shareToken)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(white: 0.12))
                .cornerRadius(16)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

              TextField("API Base URL", text: $apiBaseURL)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(white: 0.12))
                .cornerRadius(16)
                .foregroundColor(.gray)
                .font(.system(size: 14, weight: .medium))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 24)

            if let error = errorMessage {
              Text(error)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.red)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
            }

            Button(action: { resolveToken() }) {
              Text("clip.resolve_share_link")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(16)
            }
            .padding(.horizontal, 24)
          }
          .padding(.vertical, 40)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(red: 0.03, green: 0.07, blue: 0.12))
      .navigationTitle("clip.preview_title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .onAppear {
        handleInvocation()
      }
      .onChange(of: invocationURL) { _, _ in
        handleInvocation()
      }
    }
  }

  private func handleInvocation() {
    guard let url = invocationURL else { return }

    let pathComponents = url.pathComponents
    guard let index = pathComponents.firstIndex(of: "c"), index + 1 < pathComponents.count else {
      errorMessage = "Invalid share link structure"
      return
    }

    let token = pathComponents[index + 1]
    self.shareToken = token

    if let scheme = url.scheme, let host = url.host {
      var base = "\(scheme)://\(host)"
      if let port = url.port {
        base += ":\(port)"
      }
      self.apiBaseURL = base
    }

    resolveToken()
  }

  private func resolveToken() {
    guard !shareToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "Token cannot be empty"
      return
    }

    isLoading = true
    errorMessage = nil

    guard let url = URL(string: "\(apiBaseURL)/api/share/\(shareToken)") else {
      errorMessage = "Invalid API URL configuration"
      isLoading = false
      return
    }

    URLSession.shared.dataTask(with: url) { data, response, error in
      DispatchQueue.main.async {
        self.isLoading = false

        if let error = error {
          self.errorMessage = "Connection error: \(error.localizedDescription)"
          return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
          self.errorMessage = "Invalid server response"
          return
        }

        if httpResponse.statusCode == 404 {
          self.errorMessage = "This access portal has been permanently closed by the owner due to expiration limits or manual revocation."
          return
        }

        if httpResponse.statusCode == 410 {
          self.errorMessage = "This share link has been revoked or expired."
          return
        }

        guard httpResponse.statusCode == 200, let data = data else {
          self.errorMessage = "Server returned error (Status: \(httpResponse.statusCode))"
          return
        }

        do {
          let decoder = JSONDecoder()
          let result = try decoder.decode(ResolvedShareContent.self, from: data)
          self.resolvedContent = result
        } catch {
          self.errorMessage = "Failed to parse metadata: \(error.localizedDescription)"
        }
      }
    }.resume()
  }
}

struct ResolvedShareContent: Codable, Sendable {
  let type: String
  let share: ShareMetadata
  let file: ClipFileMetadata?
  let memory: ClipMemoryMetadata?
  let profile: ClipProfileMetadata?
  let collection: ClipCollectionMetadata?
}

struct ShareMetadata: Codable, Sendable {
  let id: String
  let token: String
  let expiresAt: String?
  let viewCount: Int?
  let watermarkText: String?
}

struct ClipFileMetadata: Codable, Sendable, Identifiable {
  let id: String
  let name: String
  let type: String
  let sizeBytes: Int
  let mediaUrl: String?
  let thumbnailUrl: String?
}

struct ClipMemoryMetadata: Codable, Sendable {
  let id: String
  let title: String
  let description: String?
  let mediaUrl: String?
  let thumbnailUrl: String?
  let createdAt: String?
  let owner: ClipOwnerMetadata?
}

struct ClipOwnerMetadata: Codable, Sendable {
  let displayName: String?
  let avatarUrl: String?
}

struct ClipProfileMetadata: Codable, Sendable {
  let userId: String
  let handle: String
  let displayName: String?
  let bio: String?
  let avatarUrl: String?
  let coverUrl: String?
  let followerCount: Int?
}

struct ClipCollectionMetadata: Codable, Sendable {
  let id: String
  let title: String
  let owner: ClipOwnerMetadata?
  let items: [ClipFileMetadata]
}
