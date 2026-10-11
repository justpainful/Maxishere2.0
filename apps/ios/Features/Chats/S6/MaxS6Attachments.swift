import SwiftUI

struct MaxS6LinkPreviewView: View {
  @Environment(\.maxThemePalette) private var palette
  let url: URL

  private var displayHost: String {
    url.host(percentEncoded: false) ?? url.absoluteString
  }

  var body: some View {
    Link(destination: url) {
      HStack(spacing: 10) {
        Image(systemName: "link")
          .font(.body.weight(.semibold))
          .foregroundStyle(palette.accent)
          .frame(width: 38, height: 38)
          .background(palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: displayHost)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
          Text(verbatim: url.absoluteString)
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(palette.tertiaryText)
      }
      .padding(9)
      .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .stroke(palette.separator.opacity(0.6), lineWidth: 0.75)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ui_s6_link_preview")
  }
}

struct MaxS6FileAttachmentView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  let item: MaxMediaItem

  private var isAudio: Bool { item.kind.lowercased() == "audio" }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: isAudio ? "waveform" : "doc.fill")
          .font(.title3.weight(.semibold))
          .foregroundStyle(isAudio ? palette.accent : palette.warning)
          .frame(width: 44, height: 44)
          .background(
            (isAudio ? palette.accent : palette.warning).opacity(0.13),
            in: RoundedRectangle(cornerRadius: 13)
          )
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: item.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .lineLimit(2)
          Text(verbatim: ByteCountFormatter.string(
            fromByteCount: Int64(item.sizeBytes),
            countStyle: .file
          ))
          .font(.caption2)
          .foregroundStyle(palette.secondaryText)
        }
      }

      HStack(spacing: 7) {
        if isAudio {
          Button("action.play", systemImage: "play.fill") {
            model.openPlayer(for: item)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        MaxMediaTransferControl(item: item)
      }
    }
    .padding(9)
    .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityIdentifier("ui_s6_file_attachment_\(item.id)")
  }
}
