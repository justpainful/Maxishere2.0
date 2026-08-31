import SwiftUI

struct CompactRatingChip: View {
  let subject: RatingSubject
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        MaxAvatar(
          name: subject.user.displayName,
          imageURL: subject.user.avatarUrl,
          size: 28
        )
        Text(verbatim: subject.score.map { "\($0)" } ?? "—")
          .font(.subheadline.monospacedDigit().bold())
          .contentTransition(.numericText())
        Text(verbatim: "/10")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.trailing, 4)
      .frame(minHeight: 44)
    }
    .buttonStyle(.glass)
    .accessibilityLabel(Text(verbatim: subject.user.displayName))
    .accessibilityValue(
      Text(verbatim: subject.score.map { "\($0) / 10" } ?? "— / 10")
    )
    .accessibilityHint(Text("rating.open_sheet"))
    .accessibilityIdentifier("ui_player_rating_\(subject.id.maxAccessibilityToken)")
  }
}

struct CompactRatingLoadingChip: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "person.2.fill")
        ProgressView()
          .controlSize(.small)
      }
      .frame(minWidth: 76, minHeight: 44)
    }
    .buttonStyle(.glass)
    .accessibilityLabel(Text("action.rate"))
    .accessibilityIdentifier("ui_player_rating_loading")
  }
}

struct CompactRatingEmptyChip: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "person.2.fill")
        Text(verbatim: "— /10")
          .font(.subheadline.monospacedDigit().bold())
      }
      .frame(minWidth: 76, minHeight: 44)
    }
    .buttonStyle(.glass)
    .accessibilityLabel(Text("action.rate"))
    .accessibilityIdentifier("ui_player_rating_empty")
  }
}
