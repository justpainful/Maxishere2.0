import Foundation
import SwiftUI

struct PlayerCollectionPickerSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let item: MaxMediaItem

  @State private var addingCollectionID: String?
  @State private var presentedError: ProductError?

  private var collections: [CollectionSummary] {
    model.libraryStore.phase.value?.collections ?? []
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: MaxSpace.sm) {
          if let presentedError {
            PlayerActionErrorView(error: presentedError)
          }

          if collections.isEmpty {
            emptyOrLoading
          } else {
            ForEach(collections) { collection in
              Button { add(to: collection) } label: {
                HStack(spacing: MaxSpace.md) {
                  Image(systemName: "rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(MaxColor.accent)
                    .frame(width: 44, height: 44)
                    .background(
                      MaxColor.surfaceStrong,
                      in: RoundedRectangle(
                        cornerRadius: MaxRadius.small,
                        style: .continuous
                      )
                    )

                  VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                    Text(verbatim: collection.name ?? String(localized: "common.collection"))
                      .font(.body.weight(.semibold))
                      .foregroundStyle(MaxColor.textPrimary)
                      .lineLimit(1)
                    Text(
                      verbatim: (collection.itemCount ?? 0).formatted()
                        + " " + String(localized: "common.items")
                    )
                    .font(.caption)
                    .foregroundStyle(MaxColor.textSecondary)
                  }

                  Spacer(minLength: 0)

                  if addingCollectionID == collection.id {
                    ProgressView()
                  } else {
                    Image(systemName: "plus.circle.fill")
                      .foregroundStyle(MaxColor.accent)
                  }
                }
                .padding(MaxSpace.md)
                .background(
                  MaxColor.surface,
                  in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
                )
              }
              .buttonStyle(.plain)
              .disabled(addingCollectionID != nil)
              .accessibilityIdentifier(
                "ui_player_collection_\(collection.id.maxAccessibilityToken)"
              )
            }
          }
        }
        .padding(MaxSpace.md)
      }
      .navigationTitle("player.add_to_collection")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel", action: dismiss.callAsFunction)
        }
      }
      .task {
        guard model.libraryStore.phase.value == nil else { return }
        await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
      }
      .accessibilityIdentifier("ui_player_collection_sheet")
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private var emptyOrLoading: some View {
    if model.libraryStore.phase.isLoading {
      HStack(spacing: MaxSpace.sm) {
        ProgressView()
        Text("library.loading")
      }
      .frame(maxWidth: .infinity, minHeight: 100)
    } else {
      ContentUnavailableView(
        "library.collections.empty",
        systemImage: "rectangle.stack.badge.plus",
        description: Text("library.collections.empty.subtitle")
      )
    }
  }

  private func add(to collection: CollectionSummary) {
    addingCollectionID = collection.id
    presentedError = nil
    Task {
      let added = await model.libraryStore.add(
        fileID: item.id,
        toCollectionID: collection.id
      )
      if added {
        dismiss()
      } else {
        presentedError = ProductError(
          area: .library,
          code: .unknown,
          title: String(localized: "error.product.collection_add.title"),
          reason: String(localized: "error.product.collection_add.reason"),
          recoverySuggestion: String(localized: "error.product.retry")
        )
      }
      addingCollectionID = nil
    }
  }
}
