import PhotosUI
import SwiftUI
import UIKit

struct MaxS6AttachmentPickerTray: View {
  @Environment(\.maxThemePalette) private var palette

  @Binding var selection: [PhotosPickerItem]
  let isBusy: Bool
  let chooseFiles: () -> Void
  let takePhoto: () -> Void
  let createPoll: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      HStack {
        Label("chat.attachments", systemImage: "paperclip")
          .font(.caption.weight(.bold))
          .foregroundStyle(palette.secondaryText)
        Spacer(minLength: 0)
        if isBusy { ProgressView().controlSize(.small) }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MaxSpace.sm) {
        PhotosPicker(
          selection: $selection,
          maxSelectionCount: 6,
          matching: .any(of: [.images, .videos]),
          preferredItemEncoding: .current
        ) {
          MaxS6AttachmentChoice(
            title: "upload.choose_photos",
            systemName: "photo.on.rectangle.angled",
            tint: palette.accent
          )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          Button(action: takePhoto) {
            MaxS6AttachmentChoice(
              title: "chat.camera",
              systemName: "camera.fill",
              tint: palette.success
            )
          }
          .buttonStyle(.plain)
          .disabled(isBusy)
        }

        Button(action: chooseFiles) {
          MaxS6AttachmentChoice(
            title: "upload.choose_files",
            systemName: "doc.fill",
            tint: palette.warning
          )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)

        Button(action: createPoll) {
          MaxS6AttachmentChoice(
            title: "chat.poll.create",
            systemName: "chart.bar.fill",
            tint: palette.success
          )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        }
      }
    }
    .padding(MaxSpace.sm)
    .background(
      palette.elevatedContentSurface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
        .stroke(palette.separator.opacity(0.68), lineWidth: 0.75)
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .accessibilityIdentifier("ui_s6_attachment_picker")
  }
}

private struct MaxS6AttachmentChoice: View {
  let title: LocalizedStringKey
  let systemName: String
  let tint: Color

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: systemName)
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 36, height: 36)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MaxColor.textPrimary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .frame(width: 150)
    .padding(MaxSpace.xs)
    .background(MaxColor.surfaceSoft, in: RoundedRectangle(cornerRadius: MaxRadius.small))
  }
}

struct MaxS6CameraPicker: UIViewControllerRepresentable {
  let onCapture: (UIImage) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.cameraCaptureMode = .photo
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
      self.onCapture = onCapture
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage {
        onCapture(image)
      } else {
        onCancel()
      }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
    }
  }
}

struct MaxS6ComposerInput: View {
  @Environment(\.maxThemePalette) private var palette

  @Binding var text: String
  @Binding var showsAttachmentPicker: Bool
  let focus: FocusState<Bool>.Binding
  let isBusy: Bool
  let isRecording: Bool
  let recordingDuration: Int
  let toggleRecording: () -> Void
  let send: () -> Void

  private var canSend: Bool {
    !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: MaxSpace.xs) {
      Button {
        withAnimation(MaxMotion.quick) {
          showsAttachmentPicker.toggle()
        }
      } label: {
        Group {
          if isBusy {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: showsAttachmentPicker ? "xmark" : "plus")
              .font(.system(size: 18, weight: .semibold))
          }
        }
        .frame(width: 40, height: 40)
        .foregroundStyle(
          showsAttachmentPicker ? palette.accentForeground : palette.primaryText
        )
        .background {
          MaxControlMaterial(
            Circle(),
            tone: showsAttachmentPicker ? .prominent : .standard,
            interactive: true
          )
        }
      }
      .buttonStyle(.plain)
      .disabled(isBusy)
      .accessibilityLabel(Text("chat.attachments"))
      .accessibilityIdentifier("ui_s6_composer_attachment")

      TextField("chat.composer.placeholder", text: $text, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          palette.elevatedContentSurface,
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(
              focus.wrappedValue
                ? palette.accent.opacity(0.44)
                : palette.separator.opacity(0.58),
              lineWidth: focus.wrappedValue ? 1.2 : 0.75
            )
        }
        .focused(focus)
        .submitLabel(.send)
        .onSubmit {
          if canSend { send() }
        }
        .accessibilityIdentifier("ui_chat_composer")

      Button(action: composerAction) {
        Group {
          if isBusy {
            ProgressView().controlSize(.small)
          } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
              .font(.system(size: 16, weight: .bold))
          } else {
            Image(systemName: "arrow.up")
              .font(.system(size: 17, weight: .bold))
          }
        }
        .foregroundStyle(isRecording ? Color.white : palette.accentForeground)
        .frame(width: 40, height: 40)
        .background {
          if isRecording {
            Circle().fill(Color.red)
          } else {
            MaxControlMaterial(
              Circle(),
              tone: canSend ? .prominent : .standard,
              interactive: canSend || !isBusy
            )
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(isBusy)
      .accessibilityLabel(Text(
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? (isRecording ? "chat.voice.stop" : "chat.voice.record")
          : "chat.send"
      ))
      .accessibilityIdentifier("ui_chat_send")
    }
    .overlay(alignment: .topTrailing) {
      if isRecording {
        Text(verbatim: String(format: "%d:%02d", recordingDuration / 60, recordingDuration % 60))
          .font(.caption2.weight(.bold).monospacedDigit())
          .foregroundStyle(.red)
          .offset(x: -2, y: -18)
      }
    }
    .accessibilityIdentifier("ui_s6_composer_input")
  }

  private func composerAction() {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      toggleRecording()
    } else if canSend {
      send()
    }
  }
}

struct MaxS6ReplyBanner: View {
  @Environment(\.maxThemePalette) private var palette
  let message: ChatMessage
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: MaxSpace.sm) {
      Capsule()
        .fill(palette.accent)
        .frame(width: 3)
      Image(systemName: "arrowshape.turn.up.left.fill")
        .foregroundStyle(palette.accent)
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(message.sender?.displayName ?? String(localized: "chat.replying_to"))
          .font(.caption.weight(.bold))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
        Text(verbatim: message.content ?? String(localized: "chat.message.media"))
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      Button("common.dismiss", systemImage: "xmark.circle.fill", action: dismiss)
        .labelStyle(.iconOnly)
    }
    .padding(MaxSpace.sm)
    .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: MaxRadius.small))
    .accessibilityIdentifier("ui_s6_reply_banner")
  }
}
