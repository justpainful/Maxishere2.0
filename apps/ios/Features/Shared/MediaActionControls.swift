import SwiftUI

enum MaxMediaActionPresentation {
  case iconOnly
  case labeled
}

struct MaxMediaSaveControl: View {
  @Environment(MaxAppModel.self) private var model

  let item: MaxMediaItem
  let presentation: MaxMediaActionPresentation
  let tint: Color?

  @State private var isSaved: Bool

  init(
    item: MaxMediaItem,
    presentation: MaxMediaActionPresentation = .labeled,
    tint: Color? = nil
  ) {
    self.item = item
    self.presentation = presentation
    self.tint = tint
    _isSaved = State(initialValue: item.isFavorite || item.isSaved)
  }

  var body: some View {
    Button {
      isSaved.toggle()
      Task { await model.toggleFavorite(item) }
    } label: {
      actionLabel(
        title: isSaved ? "action.unsave" : "action.save",
        symbol: isSaved ? "heart.fill" : "heart"
      )
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .tint(resolvedTint)
    .accessibilityIdentifier("ui_media_save_\(item.id)")
  }

  private var resolvedTint: Color? {
    if let tint { return tint }
    return isSaved ? MaxColor.coral : nil
  }

  @ViewBuilder
  private func actionLabel(title: LocalizedStringKey, symbol: String) -> some View {
    switch presentation {
    case .iconOnly:
      Label(title, systemImage: symbol)
        .labelStyle(.iconOnly)
    case .labeled:
      Label(title, systemImage: symbol)
    }
  }
}

struct MaxMediaTransferControl: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let item: MaxMediaItem
  let presentation: MaxMediaActionPresentation
  let tint: Color?

  init(
    item: MaxMediaItem,
    presentation: MaxMediaActionPresentation = .labeled,
    tint: Color? = nil
  ) {
    self.item = item
    self.presentation = presentation
    self.tint = tint
  }

  var body: some View {
    Group {
      if model.transferStore.localURL(for: item) != nil {
        actionLabel(title: "player.offline_ready", symbol: "checkmark.circle.fill")
          .foregroundStyle(tint ?? palette.success)
          .accessibilityIdentifier("ui_media_offline_\(item.id)")
      } else if let record = latestRecord, record.state.isActive {
        Button(role: .cancel) {
          model.transferStore.cancel(record.id)
        } label: {
          activeLabel(record)
        }
        .accessibilityLabel(Text("transfer.cancel"))
        .accessibilityValue(Text(verbatim: progressValue(record)))
        .accessibilityIdentifier("ui_media_download_cancel_\(item.id)")
      } else if let record = latestRecord, record.state.canRetry {
        Button {
          model.transferStore.retry(record.id)
        } label: {
          actionLabel(title: "common.retry", symbol: "arrow.clockwise")
        }
        .accessibilityIdentifier("ui_media_download_retry_\(item.id)")
      } else if item.downloadable {
        Button {
          Task { await model.transferStore.download(item) }
        } label: {
          actionLabel(title: "action.download", symbol: "arrow.down.circle")
        }
        .accessibilityIdentifier("ui_media_download_\(item.id)")
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .tint(tint)
  }

  private var latestRecord: TransferRecord? {
    model.transferStore.records
      .filter { $0.kind == .download && $0.sourceID == item.id }
      .max { $0.updatedAt < $1.updatedAt }
  }

  @ViewBuilder
  private func activeLabel(_ record: TransferRecord) -> some View {
    switch presentation {
    case .iconOnly:
      ZStack {
        Image(systemName: "xmark")
        if let progress = record.progress {
          ProgressView(value: progress)
            .progressViewStyle(.circular)
            .allowsHitTesting(false)
        } else {
          ProgressView()
            .controlSize(.mini)
            .allowsHitTesting(false)
        }
      }
    case .labeled:
      HStack(spacing: MaxSpace.xs) {
        if let progress = record.progress {
          ProgressView(value: progress)
            .frame(width: 36)
        } else {
          ProgressView()
            .controlSize(.small)
        }
        Text("transfer.cancel")
      }
    }
  }

  @ViewBuilder
  private func actionLabel(title: LocalizedStringKey, symbol: String) -> some View {
    switch presentation {
    case .iconOnly:
      Label(title, systemImage: symbol)
        .labelStyle(.iconOnly)
    case .labeled:
      Label(title, systemImage: symbol)
    }
  }

  private func progressValue(_ record: TransferRecord) -> String {
    guard let progress = record.progress else {
      return String(localized: "transfer.state.downloading")
    }
    return progress.formatted(.percent.precision(.fractionLength(0)))
  }
}
