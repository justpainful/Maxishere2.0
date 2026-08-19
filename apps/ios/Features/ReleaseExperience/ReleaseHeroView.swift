import SwiftUI

struct ReleaseHeroView: View {
  let announcement: ReleaseAnnouncement
  let personalDisplayName: String?
  let onCTA: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @State private var logoVisible = false
  @State private var previewVisible = false
  @State private var titleVisible = false
  @State private var visibleFeatureCount = 0
  @State private var ctaVisible = false

  private var isLongLaunch: Bool {
    announcement.presentationStyle == .longLaunch
  }

  var body: some View {
    VStack(spacing: isLongLaunch ? MaxSpace.lg : MaxSpace.md) {
      Spacer(minLength: isLongLaunch ? MaxSpace.lg : MaxSpace.sm)

      logo
        .opacity(logoVisible ? 1 : 0)
        .scaleEffect(logoVisible ? 1 : 0.96)

      ReleaseFeaturePreview(visualStyle: announcement.visualStyle)
        .opacity(previewVisible ? 1 : 0)
        .offset(y: previewVisible || reduceMotion ? 0 : 90)
        .padding(.top, isLongLaunch ? MaxSpace.sm : 0)

      titleBlock
        .opacity(titleVisible ? 1 : 0)
        .offset(y: titleVisible || reduceMotion ? 0 : 12)

      ReleaseTimeline(
        featureItems: announcement.featureItems,
        visibleCount: visibleFeatureCount
      )
      .frame(maxWidth: 420)

      ReleaseCTAButton(titleKey: announcement.presentationStyle.ctaTitleKey, action: onCTA)
        .opacity(ctaVisible ? 1 : 0)
        .offset(y: ctaVisible || reduceMotion ? 0 : 12)
        .frame(maxWidth: 420)
        .padding(.top, MaxSpace.xs)

      Spacer(minLength: MaxSpace.md)
    }
    .padding(.horizontal, MaxSpace.lg)
    .multilineTextAlignment(.center)
    .task(id: announcement.id) {
      await runSequence()
    }
  }

  private var logo: some View {
    HStack(spacing: MaxSpace.sm) {
      MaxIdentityMark(size: 34)
      Text("Max")
        .font(.system(.title2, design: .rounded).weight(.black))
        .foregroundStyle(MaxColor.textPrimary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Max")
  }

  private var titleBlock: some View {
    VStack(spacing: MaxSpace.sm) {
      if let personalMessage {
        Text(personalMessage)
          .font(MaxTypography.caption.weight(.semibold))
          .foregroundStyle(MaxColor.accent)
          .fixedSize(horizontal: false, vertical: true)
      }

      Text(LocalizedStringKey(announcement.title))
        .font(.system(isLongLaunch ? .largeTitle : .title2, design: .rounded).weight(.black))
        .foregroundStyle(MaxColor.textPrimary)
        .lineLimit(3)
        .minimumScaleFactor(0.78)
        .fixedSize(horizontal: false, vertical: true)

      Text(LocalizedStringKey(announcement.subtitle))
        .font(MaxTypography.body.weight(.medium))
        .foregroundStyle(MaxColor.textSecondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: 430)
  }

  private var personalMessage: String? {
    guard
      announcement.presentationStyle == .compactLaunch,
      let personalDisplayName,
      !personalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return String(
      format: NSLocalizedString("release.mobile_launch.personal_message", comment: ""),
      personalDisplayName
    )
  }

  private func runSequence() async {
    // Rewind silently: animating the reset made a second announcement flash the
    // previous hero out to blank before the new sequence began.
    var rewind = Transaction()
    rewind.disablesAnimations = true
    withTransaction(rewind) { reset() }

    if reduceMotion || !motionEnabled {
      withAnimation(.easeOut(duration: 0.18)) {
        logoVisible = true
        previewVisible = true
        titleVisible = true
        visibleFeatureCount = announcement.featureItems.count
        ctaVisible = true
      }
      return
    }

    switch announcement.presentationStyle {
    case .longLaunch:
      await runLongLaunchSequence()
    case .compactLaunch, .featureUpdate:
      await runCompactSequence()
    }
  }

  private func runLongLaunchSequence() async {
    withAnimation(.easeOut(duration: 0.35)) {
      logoVisible = true
    }

    try? await Task.sleep(nanoseconds: 350_000_000)
    withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
      previewVisible = true
    }

    try? await Task.sleep(nanoseconds: 850_000_000)
    withAnimation(.easeOut(duration: 0.48)) {
      titleVisible = true
    }

    try? await Task.sleep(nanoseconds: 800_000_000)
    if !announcement.featureItems.isEmpty {
      for count in 1...announcement.featureItems.count {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
          visibleFeatureCount = count
        }
        try? await Task.sleep(nanoseconds: 266_000_000)
      }
    }

    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
      ctaVisible = true
    }
  }

  private func runCompactSequence() async {
    withAnimation(.easeOut(duration: 0.22)) {
      logoVisible = true
      titleVisible = true
    }
    try? await Task.sleep(nanoseconds: 140_000_000)
    withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
      previewVisible = true
    }
    try? await Task.sleep(nanoseconds: 180_000_000)
    withAnimation(.easeOut(duration: 0.2)) {
      visibleFeatureCount = announcement.featureItems.count
      ctaVisible = true
    }
  }

  private func reset() {
    logoVisible = false
    previewVisible = false
    titleVisible = false
    visibleFeatureCount = 0
    ctaVisible = false
  }
}
