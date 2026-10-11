import AVKit
import Foundation
import SwiftUI

/// The stories rail pinned above Saved Messages in the chat inbox: one ring per
/// poster, mine first, an accent ring while unseen stories remain. Mirrors the
/// desktop's StoriesRail.
struct ChatKitStoriesRail: View {
  let rails: [MaxStoryRail]
  /// Called with the index of the tapped rail; the host presents the viewer.
  let onOpen: (Int) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: MaxSpace.sm) {
        ForEach(Array(rails.enumerated()), id: \.element.id) { index, rail in
          Button { onOpen(index) } label: {
            VStack(spacing: 4) {
              ChatKitAvatar(url: rail.avatarUrl, title: rail.displayName)
                .frame(width: 52, height: 52)
                .padding(3)
                .overlay {
                  Circle().strokeBorder(
                    rail.unseen > 0
                      ? AnyShapeStyle(MaxColor.accent)
                      : AnyShapeStyle(.quaternary),
                    lineWidth: 2
                  )
                }
              Text(verbatim: rail.mine ? "My Story" : rail.displayName)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 64)
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_chatkit_story_ring_\(rail.userId)")
        }
      }
      .padding(.horizontal, MaxSpace.md)
      .padding(.vertical, MaxSpace.xs)
    }
    .accessibilityIdentifier("ui_chatkit_stories_rail")
  }
}

/// Full-screen story viewer: images auto-advance after five seconds, videos
/// advance when playback ends. Tap advances, the left chevron goes back, the
/// trash removes my own story. Mirrors the desktop's StoryViewer.
struct ChatKitStoryViewer: View {
  @Environment(MaxAppModel.self) private var model
  let rails: [MaxStoryRail]
  let startRailIndex: Int
  let onClose: () -> Void

  @State private var railIndex: Int
  @State private var storyIndex = 0
  @State private var videoPlayer: AVPlayer?

  init(rails: [MaxStoryRail], startRailIndex: Int, onClose: @escaping () -> Void) {
    self.rails = rails
    self.startRailIndex = startRailIndex
    self.onClose = onClose
    _railIndex = State(initialValue: startRailIndex)
  }

  private var rail: MaxStoryRail? {
    rails.indices.contains(railIndex) ? rails[railIndex] : nil
  }

  private var story: MaxStory? {
    guard let rail, rail.stories.indices.contains(storyIndex) else { return nil }
    return rail.stories[storyIndex]
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let story {
        storyContent(story)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
          .onTapGesture { advance() }
      }

      VStack(spacing: MaxSpace.sm) {
        progressSegments
        header
        Spacer()
        if let caption = story?.caption, !caption.isEmpty {
          Text(verbatim: caption)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, MaxSpace.md)
            .padding(.bottom, MaxSpace.lg)
        }
      }
      .padding(.top, MaxSpace.sm)

      HStack {
        Button { retreat() } label: {
          Image(systemName: "chevron.left")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(MaxSpace.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Previous story"))
        Spacer()
      }
    }
    .task(id: story?.id) { await presentCurrentStory() }
    .onDisappear { tearDownVideo() }
    .accessibilityIdentifier("ui_chatkit_story_viewer")
  }

  // MARK: - Pieces

  @ViewBuilder
  private func storyContent(_ story: MaxStory) -> some View {
    if story.kind == "video" {
      if let videoPlayer {
        // Bare playback: hit testing is off so the tap-to-advance gesture and
        // the viewer's own chrome stay in charge instead of AVKit's controls.
        VideoPlayer(player: videoPlayer)
          .allowsHitTesting(false)
      } else {
        storyPoster(story)
      }
    } else if let url = story.url ?? story.posterUrl {
      MaxAsyncImage(url: url) { phase in
        if case .success(let image) = phase {
          image.resizable().scaledToFit()
        } else {
          ProgressView().tint(.white)
        }
      }
    } else {
      storyPoster(story)
    }
  }

  /// Poster placeholder shown while a video prepares or when a URL is missing.
  private func storyPoster(_ story: MaxStory) -> some View {
    ZStack {
      if let posterUrl = story.posterUrl {
        MaxAsyncImage(url: posterUrl) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFit()
          } else {
            Color.black
          }
        }
      }
      ProgressView().tint(.white)
    }
  }

  private var progressSegments: some View {
    HStack(spacing: 4) {
      if let rail {
        ForEach(Array(rail.stories.enumerated()), id: \.element.id) { index, _ in
          Capsule()
            .fill(index <= storyIndex ? Color.white : Color.white.opacity(0.3))
            .frame(height: 3)
        }
      }
    }
    .padding(.horizontal, MaxSpace.md)
  }

  private var header: some View {
    HStack(spacing: MaxSpace.sm) {
      Text(verbatim: rail?.mine == true ? "My Story" : (rail?.displayName ?? ""))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Spacer(minLength: MaxSpace.sm)
      if rail?.mine == true, let story {
        Button { deleteCurrent(story) } label: {
          Image(systemName: "trash")
            .font(.body)
            .foregroundStyle(.white)
            .padding(MaxSpace.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Delete story"))
        .accessibilityIdentifier("ui_chatkit_story_delete")
      }
      Button { onClose() } label: {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .padding(MaxSpace.xs)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Close"))
      .accessibilityIdentifier("ui_chatkit_story_close")
    }
    .padding(.horizontal, MaxSpace.md)
  }

  // MARK: - Playback & navigation

  /// Marks the story on screen viewed and arms its advance: a five-second hold
  /// for images, end-of-playback for videos. Runs as `.task(id: story.id)`, so
  /// moving to another story cancels the pending advance automatically.
  private func presentCurrentStory() async {
    tearDownVideo()
    guard let story else { return }
    let storyID = story.id
    Task { _ = try? await model.apiClient.viewStory(id: storyID) }

    if story.kind == "video", let url = story.url {
      let player = AVPlayer(url: url)
      videoPlayer = player
      player.play()
      // Poll for the end from this structured task instead of a notification
      // observer: no unstructured state, and cancellation is free.
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        guard let item = player.currentItem else { continue }
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0,
           player.currentTime().seconds >= duration - 0.05 {
          break
        }
      }
      guard !Task.isCancelled else { return }
      advance()
    } else {
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      advance()
    }
  }

  private func advance() {
    guard let rail else { return }
    if storyIndex + 1 < rail.stories.count {
      storyIndex += 1
    } else if railIndex + 1 < rails.count {
      railIndex += 1
      storyIndex = 0
    } else {
      onClose()
    }
  }

  private func retreat() {
    if storyIndex > 0 {
      storyIndex -= 1
    } else if railIndex > 0 {
      let previous = rails[railIndex - 1]
      railIndex -= 1
      storyIndex = max(0, previous.stories.count - 1)
    }
  }

  private func deleteCurrent(_ story: MaxStory) {
    Task { _ = try? await model.apiClient.deleteStory(id: story.id) }
    onClose()
  }

  private func tearDownVideo() {
    videoPlayer?.pause()
    videoPlayer = nil
  }
}
