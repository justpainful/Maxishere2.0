import SwiftUI

// MARK: - The Gathering Experience
// Design DNA: Void transition, Ember line travel, identity mark fade-in.
// Accessible and responsive; handles Reduce Motion/Transparency.

struct CouncilGatheringView: View {
  let onComplete: () -> Void

  @State private var phase: GatheringPhase = .begin
  @State private var emberProgress: CGFloat = 0.18
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled

  private enum GatheringPhase {
    case begin, voidEntry, emberEntry, warmReturn, identity, complete
  }

  var body: some View {
    ZStack {
      // Layer 0: Deep Obsidian Void
      Color(red: 0.020, green: 0.020, blue: 0.024)
        .ignoresSafeArea()

      // Layer 1: Traveling Ember Line
      if phase == .emberEntry || phase == .warmReturn || phase == .identity {
        emberLineOverlay
      }

      // Layer 2: Return of atmospheric warmth
      if phase == .warmReturn || phase == .identity {
        atmosphericReturn
      }

      // Layer 3: Identity Mark
      if phase == .identity {
        identityMark
      }

      // Skip Button
      VStack {
        HStack {
          Spacer()
          Button("common.skip") {
            // The presentation binding this drives is not animatable, and the
            // sequence task is cancelled by `.task` teardown on dismissal.
            completeGathering()
          }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color(red: 0.596, green: 0.576, blue: 0.596))
          .padding()
        }
        Spacer()
      }
    }
    .task { await beginSequence() }
    .accessibilityLabel(Text("theme.council.gathering.accessibility"))
  }

  private var emberLineOverlay: some View {
    GeometryReader { geo in
      let width = geo.size.width
      Rectangle()
        .fill(
          LinearGradient(
            colors: [
              Color.clear,
              Color(red: 0.91, green: 0.28, blue: 0.18).opacity(0.9),
              Color(red: 0.84, green: 0.55, blue: 0.40).opacity(0.7),
              Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(height: 1.5)
        .position(x: width / 2, y: geo.size.height * emberProgress)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var atmosphericReturn: some View {
    LinearGradient(
      colors: [
        Color(red: 0.56, green: 0.06, blue: 0.11).opacity(0.06),
        Color.clear,
        Color.black.opacity(0.30)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var identityMark: some View {
    VStack(spacing: 20) {
      Spacer()
      // Council Cut silhouette as an identity mark
      CouncilCutShape(cornerRadius: 20, cutDepth: 22)
        .stroke(
          LinearGradient(
            colors: [
              Color(red: 0.796, green: 0.784, blue: 0.780).opacity(0.6),
              Color(red: 0.56, green: 0.06, blue: 0.11).opacity(0.4),
              Color(red: 0.796, green: 0.784, blue: 0.780).opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
        .frame(width: 72, height: 72)

      Text(verbatim: "Black Council")
        .font(.system(.caption, design: .serif, weight: .medium))
        .foregroundStyle(Color(red: 0.596, green: 0.576, blue: 0.596))
        .tracking(3)
        .textCase(.uppercase)
      Spacer()
    }
    .transition(.opacity.combined(with: .scale(scale: 0.96)))
    .accessibilityHidden(true)
  }

  /// Bound to the view's lifetime by `.task`, so dismissing or skipping cancels
  /// it. The old unstructured `Task` kept running for up to ~3.2 s after Skip
  /// and fired `onComplete()` a second time, re-writing presentation state.
  private func beginSequence() async {
    if reduceMotion || !motionEnabled {
      // Bypass transitions for accessibility
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      completeGathering()
      return
    }

    // 1. Enter Void
    try? await Task.sleep(for: .milliseconds(200))
    guard !Task.isCancelled else { return }
    withAnimation(.easeIn(duration: 0.3)) { phase = .voidEntry }

    // 2. Ember Line appears
    try? await Task.sleep(for: .milliseconds(400))
    guard !Task.isCancelled else { return }
    withAnimation(.smooth(duration: 0.5)) { phase = .emberEntry }

    // 3. Warmth returns while the ember line travels to its resting height.
    //    The travel starts here, not on insertion: a freshly inserted view has
    //    no previous position to interpolate from, so it would not animate.
    try? await Task.sleep(for: .milliseconds(600))
    guard !Task.isCancelled else { return }
    withAnimation(.smooth(duration: 0.7)) {
      phase = .warmReturn
      emberProgress = 0.52
    }

    // 4. Show Identity Mark
    try? await Task.sleep(for: .milliseconds(500))
    guard !Task.isCancelled else { return }
    withAnimation(.smooth(duration: 0.4)) { phase = .identity }

    // 5. Complete and Dismiss
    try? await Task.sleep(for: .milliseconds(1500))
    guard !Task.isCancelled else { return }
    completeGathering()
  }

  private func completeGathering() {
    // Idempotent: Skip and the sequence can both reach here in the same frame.
    guard phase != .complete else { return }
    phase = .complete
    onComplete()
  }
}

// MARK: - Theme Preview View
// Renders inside Settings to showcase the Obsidian layers, Ember Line, and temperature-focused bubble cues.

struct CouncilThemePreviewView: View {
  @State private var showGathering = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("settings.theme.preview")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color(red: 0.596, green: 0.576, blue: 0.596))
        .padding(.bottom, 10)

      ZStack(alignment: .topLeading) {
        // Deep obsidian canvas
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(red: 0.020, green: 0.020, blue: 0.024))
          .frame(height: 200)

        // Directional warm light bleed
        if !reduceTransparency {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.56, green: 0.06, blue: 0.11).opacity(0.12),
                  Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(height: 200)
        }

        // Mini mock client UI
        VStack(spacing: 0) {
          // Tab bar mock
          HStack(spacing: 12) {
            ForEach(["archivebox", "person.2", "bubble.left", "person.crop.circle"], id: \.self) { sym in
              let isActive = sym == "archivebox"
              VStack(spacing: 3) {
                Image(systemName: sym)
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(
                    isActive
                      ? Color(red: 0.91, green: 0.28, blue: 0.18)
                      : Color(red: 0.42, green: 0.41, blue: 0.42)
                  )
                if isActive {
                  Rectangle()
                    .fill(Color(red: 0.91, green: 0.28, blue: 0.18))
                    .frame(width: 14, height: 1)
                } else {
                  Rectangle()
                    .fill(Color.clear)
                    .frame(width: 14, height: 1)
                }
              }
              .frame(maxWidth: .infinity)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color(red: 0.043, green: 0.039, blue: 0.051))

          // Mini hero card (Obsidian surface with cut shape)
          HStack(spacing: 8) {
            CouncilCutShape(cornerRadius: 8, cutDepth: 8)
              .fill(Color(red: 0.055, green: 0.047, blue: 0.063))
              .frame(width: 60, height: 40)
              .overlay {
                CouncilCutShape(cornerRadius: 8, cutDepth: 8)
                  .stroke(Color(red: 0.165, green: 0.141, blue: 0.161), lineWidth: 0.5)
              }
              .overlay(alignment: .bottomLeading) {
                Rectangle()
                  .fill(Color(red: 0.91, green: 0.28, blue: 0.18))
                  .frame(height: 1)
                  .padding(.horizontal, 6)
                  .padding(.bottom, 4)
              }

            VStack(alignment: .leading, spacing: 4) {
              Rectangle()
                .fill(Color(red: 0.596, green: 0.576, blue: 0.596).opacity(0.5))
                .frame(width: 80, height: 5)
                .clipShape(Capsule())
              Rectangle()
                .fill(Color(red: 0.420, green: 0.408, blue: 0.420).opacity(0.3))
                .frame(width: 50, height: 4)
                .clipShape(Capsule())
            }
            Spacer()
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)

          // File cell mocks
          VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
              HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                  .fill(Color(red: 0.071, green: 0.063, blue: 0.078))
                  .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                  Rectangle()
                    .fill(Color(red: 0.596, green: 0.576, blue: 0.596).opacity(0.4))
                    .frame(height: 4)
                    .clipShape(Capsule())
                  Rectangle()
                    .fill(Color(red: 0.420, green: 0.408, blue: 0.420).opacity(0.2))
                    .frame(width: 40, height: 3)
                    .clipShape(Capsule())
                }
                Spacer()
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color(red: 0.071, green: 0.063, blue: 0.078).opacity(0.6))
            }
          }

          // Message bubble mocks (Sent bubble uses obsidian selected red, received bubbles use stone)
          HStack {
            Text(verbatim: "···")
              .font(.system(size: 8))
              .foregroundStyle(Color(red: 0.796, green: 0.784, blue: 0.780))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color(red: 0.071, green: 0.063, blue: 0.078), in: Capsule())
            Spacer()
            Text(verbatim: "···")
              .font(.system(size: 8))
              .foregroundStyle(Color(red: 0.953, green: 0.941, blue: 0.933))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color(red: 0.165, green: 0.094, blue: 0.125), in: Capsule())
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 4)

          Spacer()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color(red: 0.165, green: 0.141, blue: 0.161), lineWidth: 1)
      }

      Button {
        showGathering = true
      } label: {
        Label("theme.council.replay_gathering", systemImage: "arrow.counterclockwise")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color(red: 0.84, green: 0.55, blue: 0.40))
      }
      .padding(.top, 10)
      .accessibilityIdentifier("ui_council_replay_gathering")
    }
    .fullScreenCover(isPresented: $showGathering) {
      CouncilGatheringView {
        showGathering = false
      }
    }
  }
}
