import Foundation
import SwiftUI

/// Compatibility entry point used by the root sheet router and the player.
struct RatingSheetView: View {
  let item: MaxMediaItem

  var body: some View {
    DualRatingSheetView(item: item)
  }
}

struct DualRatingSheetView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let item: MaxMediaItem

  private var subjects: [RatingSubject] {
    model.ratingStore.subjects(for: item.id)
  }

  private var isLoading: Bool {
    model.ratingStore.loadingFileIDs.contains(item.id)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: MaxSpace.md) {
          RatingSheetHeader(item: item)

          if let error = model.ratingStore.presentedError {
            RatingProductErrorView(error: error, retry: reload)
          }

          if subjects.isEmpty {
            emptyOrLoadingState
          } else {
            ForEach(subjects) { subject in
              DualRatingSubjectRow(
                subject: subject,
                isUpdating: model.ratingStore.updatingSubjectIDs.contains(subject.id),
                onCommit: { score in commit(score, for: subject) }
              )
            }
          }
        }
        .padding(MaxSpace.md)
      }
      .navigationTitle("rating.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.close", action: dismiss.callAsFunction)
            .accessibilityIdentifier("ui_rating_close")
        }
      }
      .task(id: item.id) { await model.ratingStore.load(fileID: item.id) }
      .accessibilityIdentifier("ui_rating_sheet")
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private var emptyOrLoadingState: some View {
    if isLoading || model.ratingStore.presentedError == nil {
      MaxContentSurface {
        HStack(spacing: MaxSpace.sm) {
          ProgressView()
          Text("rating.loading")
            .foregroundStyle(MaxColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
      }
      .accessibilityIdentifier("ui_rating_loading")
    } else {
      ContentUnavailableView(
        "rating.empty.title",
        systemImage: "person.2.slash",
        description: Text("rating.empty.subtitle")
      )
      .accessibilityIdentifier("ui_rating_empty")
    }
  }

  private func reload() {
    Task { await model.ratingStore.load(fileID: item.id) }
  }

  private func commit(_ score: Int, for subject: RatingSubject) {
    Task {
      await model.ratingStore.commit(
        fileID: item.id,
        subjectID: subject.id,
        selectedScore: score
      )
    }
  }
}

private struct RatingSheetHeader: View {
  @Environment(\.maxThemePalette) private var palette

  let item: MaxMediaItem

  var body: some View {
    VStack(spacing: MaxSpace.xs) {
      Image(systemName: "person.2.fill")
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.accent)
        .accessibilityHidden(true)
      Text(verbatim: item.title)
        .font(.title3.weight(.semibold))
        .multilineTextAlignment(.center)
      Text("rating.dual.subtitle")
        .font(.subheadline)
        .foregroundStyle(MaxColor.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, MaxSpace.sm)
    .accessibilityElement(children: .combine)
  }
}

private struct DualRatingSubjectRow: View {
  let subject: RatingSubject
  let isUpdating: Bool
  let onCommit: (Int) -> Void

  var body: some View {
    MaxContentSurface {
      VStack(spacing: MaxSpace.md) {
        HStack(spacing: MaxSpace.sm) {
          MaxAvatar(
            name: subject.user.displayName,
            imageURL: subject.user.avatarUrl,
            size: 48
          )

          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text(verbatim: subject.user.displayName)
              .font(.headline)
              .lineLimit(1)
            Text(subject.canEdit ? "rating.editable" : "rating.read_only")
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
          }

          Spacer(minLength: MaxSpace.sm)

          Text(verbatim: subject.score.map { "\($0) / 10" } ?? "— / 10")
            .font(.title2.monospacedDigit().bold())
            .foregroundStyle(MaxColor.textPrimary)
            .contentTransition(.numericText())
        }

        DiscreteRatingControl(
          score: subject.score,
          isEnabled: subject.canEdit,
          isUpdating: isUpdating,
          accessibilityName: subject.user.displayName,
          accessibilityIdentifier: "ui_rating_rail_\(subject.id.maxAccessibilityToken)",
          onCommit: onCommit
        )
      }
    }
    .accessibilityIdentifier("ui_rating_subject_\(subject.id.maxAccessibilityToken)")
  }
}

private struct RatingProductErrorView: View {
  let error: ProductError
  let retry: () -> Void

  var body: some View {
    MaxContentSurface {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        Label(error.title, systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(MaxColor.warning)
        Text(verbatim: error.reason)
          .font(.subheadline)
          .foregroundStyle(MaxColor.textSecondary)
        if let suggestion = error.recoverySuggestion {
          Text(verbatim: suggestion)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
        }
        DisclosureGroup("error.support_details") {
          Text(verbatim: error.supportDetails)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(.top, MaxSpace.xs)
        }
        Button("common.retry", action: retry)
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_rating_retry")
      }
    }
    .accessibilityIdentifier("ui_rating_error")
  }
}

extension String {
  var maxAccessibilityToken: String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
  }
}
