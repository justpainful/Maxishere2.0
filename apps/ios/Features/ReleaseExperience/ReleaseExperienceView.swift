import SwiftUI

struct ReleaseExperienceView: View {
  let announcement: ReleaseAnnouncement
  var personalDisplayName: String?
  let onDismiss: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        ReleaseHeroView(
          announcement: announcement,
          personalDisplayName: personalDisplayName,
          onCTA: onDismiss
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: proxy.size.height)
      }
      .scrollIndicators(.hidden)
      .background(MaxLivingBackground())
    }
    .accessibilityAction(.escape, onDismiss)
  }
}

#Preview("Release - Mobile Long") {
  ReleaseExperienceView(
    announcement: .mobileLaunch(presentationStyle: .longLaunch),
    onDismiss: {}
  )
}

#Preview("Release - Memories") {
  ReleaseExperienceView(
    announcement: .memories(),
    onDismiss: {}
  )
}

#Preview("Release - Settings") {
  ReleaseExperienceView(
    announcement: .settings(),
    onDismiss: {}
  )
}

#Preview("Release - Feature Preview") {
  ReleaseExperienceView(
    announcement: .featurePreview(),
    personalDisplayName: "Yazan",
    onDismiss: {}
  )
}
