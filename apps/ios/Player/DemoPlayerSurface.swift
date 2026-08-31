import SwiftUI

/// Bundled-code Demo media. It never resolves the synthetic demo.invalid URLs,
/// while still driving the same seek, pause, resume, finish, and persistence paths.
struct DemoPlayerSurface: View {
  let item: MaxMediaItem
  let position: Double
  let isPlaying: Bool

  var body: some View {
    GeometryReader { proxy in
      let phase = position / 12
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.08, green: 0.17, blue: 0.31),
            Color(red: 0.20, green: 0.48, blue: 0.63),
            Color(red: 0.04, green: 0.12, blue: 0.16),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        Circle()
          .fill(MaxColor.coral.opacity(0.68))
          .frame(width: proxy.size.width * 0.72)
          .blur(radius: 52)
          .offset(
            x: CGFloat(sin(phase)) * proxy.size.width * 0.20,
            y: proxy.size.height * 0.22
          )

        Circle()
          .fill(MaxColor.periwinkle.opacity(0.72))
          .frame(width: proxy.size.width * 0.58)
          .blur(radius: 46)
          .offset(
            x: CGFloat(cos(phase * 0.78)) * proxy.size.width * 0.28,
            y: -proxy.size.height * 0.20
          )

        LinearGradient(
          colors: [.clear, .black.opacity(0.64)],
          startPoint: .center,
          endPoint: .bottom
        )

        VStack(spacing: MaxSpace.sm) {
          Spacer()
          Image(systemName: item.kind == "video" ? "play.rectangle.fill" : "photo.fill")
            .font(.system(size: 42, weight: .medium))
            .foregroundStyle(.white.opacity(isPlaying ? 0.34 : 0.76))
            .accessibilityHidden(true)
          Text(verbatim: item.title)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
          Spacer().frame(height: 132)
        }
        .padding(MaxSpace.lg)
      }
    }
    .ignoresSafeArea()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: item.title))
    .accessibilityIdentifier("ui_player_demo_surface")
  }
}
