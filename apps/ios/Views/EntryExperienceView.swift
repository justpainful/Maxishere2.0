import SwiftUI
import UIKit

/// Logged-out introduction to Max. The dot lattice has fixed positions; only its
/// illumination masks move, so the background remains calm and legible.
struct EntryExperienceView: View {
  private enum PresentedSheet: Identifiable {
    case credentials

    var id: String { "credentials" }
  }

  @State private var presentedSheet: PresentedSheet?
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    ZStack {
      EntryDotField()

      VStack(alignment: .leading, spacing: MaxSpace.lg) {
        Spacer(minLength: MaxSpace.xl)

        MaxWordmark()
          .accessibilityIdentifier("ui_login_screen")

        EntryHeadline()

        Text("entry.description")
          .font(MaxTypography.body)
          .foregroundStyle(MaxColor.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 380, alignment: .leading)

        Spacer(minLength: MaxSpace.md)

        if appTheme == .council {
          Button {
            presentedSheet = .credentials
          } label: {
            Label("entry.continue", systemImage: "arrow.right")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(CouncilButtonStyle(temperature: .ember))
          .controlSize(.large)
          .frame(minHeight: 56)
          .accessibilityIdentifier("ui_entry_continue")
        } else {
          Button {
            presentedSheet = .credentials
          } label: {
            Label("entry.continue", systemImage: "arrow.right")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .frame(minHeight: 56)
          .accessibilityIdentifier("ui_entry_continue")
        }
      }
      .padding(.horizontal, MaxSpace.lg)
      .padding(.vertical, MaxSpace.xl)
      .frame(maxWidth: 520, maxHeight: .infinity, alignment: .leading)
    }
    .sheet(item: $presentedSheet) { _ in
      LoginView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

private struct MaxWordmark: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Text("Max")
      .font(appTheme == .solarInk ? .system(size: 54, weight: .black, design: .rounded) : .system(.title2, design: isCouncil ? .serif : .rounded).weight(.black))
      .tracking(appTheme == .solarInk ? -2 : 0)
      .foregroundStyle(appTheme == .solarInk ? palette.accent : palette.primaryText)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Max")
  }
}

private struct EntryHeadline: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.locale) private var locale
  @Environment(\.appTheme) private var appTheme
  @State private var displayedPhrase = ""

  private var isCalm: Bool {
    reduceMotion || !motionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
  }

  private var phrases: [String] {
    [
      String(localized: "entry.headline.together"),
      String(localized: "entry.headline.memories"),
      String(localized: "entry.headline.moments"),
      String(localized: "entry.headline.next"),
    ]
  }

  var body: some View {
    let isCouncil = appTheme == .council
    Text(displayedPhrase)
      .font(isCouncil ? .system(size: 42, weight: .bold, design: .serif) : .system(size: 42, weight: .bold, design: .rounded))
      .foregroundStyle(MaxColor.textPrimary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: 420, minHeight: 118, alignment: .leading)
      .accessibilityLabel(displayedPhrase)
      // Keyed on the motion gate too, so toggling Reduce Motion while the login
      // screen is open actually restarts (and therefore stops) the typewriter.
      .task(id: "\(locale.identifier)-\(isCalm)") {
        await runCycle()
      }
  }

  @MainActor
  private func runCycle() async {
    guard !phrases.isEmpty else { return }

    if isCalm {
      displayedPhrase = phrases[0]
      return
    }

    // One prepared generator fired at phrase boundaries. The old code allocated
    // an unprepared selection generator every four characters — a haptic pulse
    // roughly every 216 ms for as long as the user stayed logged out.
    let impact = UIImpactFeedbackGenerator(style: .soft)
    impact.prepare()

    var phraseIndex = 0
    while !Task.isCancelled {
      let phrase = phrases[phraseIndex]
      let characters = Array(phrase)
      displayedPhrase = ""

      for offset in characters.indices {
        guard !Task.isCancelled else { return }
        displayedPhrase.append(characters[offset])
        try? await Task.sleep(for: .milliseconds(54))
      }

      impact.impactOccurred(intensity: 0.55)
      try? await Task.sleep(for: .seconds(1.7))

      for _ in characters.indices.reversed() {
        guard !Task.isCancelled else { return }
        displayedPhrase.removeLast()
        try? await Task.sleep(for: .milliseconds(32))
      }

      phraseIndex = (phraseIndex + 1) % phrases.count
      try? await Task.sleep(for: .milliseconds(240))
    }
  }
}

private struct EntryDotField: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.maxThemePalette) private var palette

  private var isCalm: Bool {
    reduceMotion || !motionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
  }

  var body: some View {
    TimelineView(
      .animation(minimumInterval: 1.0 / 18.0, paused: isCalm)
    ) { timeline in
      Canvas(rendersAsynchronously: true) { context, size in
        drawDots(
          in: &context,
          size: size,
          phase: isCalm ? 0 : timeline.date.timeIntervalSinceReferenceDate
        )
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func drawDots(in context: inout GraphicsContext, size: CGSize, phase: TimeInterval) {
    let spacing: CGFloat = 15
    let columns = Int(size.width / spacing) + 2
    let rows = Int(size.height / spacing) + 2
    let coolCenter = CGPoint(
      x: size.width * (0.33 + 0.10 * sin(phase / 11)),
      y: size.height * (0.30 + 0.06 * cos(phase / 13))
    )
    let warmCenter = CGPoint(
      x: size.width * (0.73 + 0.05 * cos(phase / 15)),
      y: size.height * (0.60 + 0.07 * sin(phase / 12))
    )

    for row in 0..<rows {
      for column in 0..<columns {
        let point = CGPoint(x: CGFloat(column) * spacing, y: CGFloat(row) * spacing)
        let cool = maskIntensity(at: point, center: coolCenter, radius: size.width * 0.46)
        let warm = organicMaskIntensity(at: point, center: warmCenter, radius: size.width * 0.29)
        let emphasis = max(cool, warm)
        let diameter = 1.2 + emphasis * 2.8
        let opacity = 0.10 + emphasis * 0.78
        let color = warm > cool
          ? Color(red: 0.96, green: 0.34, blue: 0.24).opacity(opacity)
          : palette.accent.opacity(opacity)
        let rect = CGRect(
          x: point.x - diameter / 2,
          y: point.y - diameter / 2,
          width: diameter,
          height: diameter
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
      }
    }
  }

  private func maskIntensity(at point: CGPoint, center: CGPoint, radius: CGFloat) -> CGFloat {
    let distance = hypot(point.x - center.x, point.y - center.y)
    return max(0, 1 - distance / radius)
  }

  private func organicMaskIntensity(at point: CGPoint, center: CGPoint, radius: CGFloat) -> CGFloat {
    let offsets = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: radius * 0.42, y: -radius * 0.18),
      CGPoint(x: -radius * 0.30, y: radius * 0.36),
    ]
    return offsets.reduce(0) { intensity, offset in
      max(intensity, maskIntensity(
        at: point,
        center: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
        radius: radius * 0.68
      ))
    }
  }
}

private struct AnyButtonStyle: ButtonStyle {
  private let _makeBody: (Configuration) -> AnyView

  init<S: ButtonStyle>(_ style: S) {
    self._makeBody = { configuration in
      AnyView(style.makeBody(configuration: configuration))
    }
  }

  func makeBody(configuration: Configuration) -> some View {
    _makeBody(configuration)
  }
}
