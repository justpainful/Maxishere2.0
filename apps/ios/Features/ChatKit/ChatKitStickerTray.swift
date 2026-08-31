import PhotosUI
import SwiftUI
import UIKit

/// The sticker tray: the caller's stickers (favorites first — the server
/// orders), a tap sends into the thread, a context menu manages favorite and
/// remove, and an add tile pushes a picked photo through the same store —
/// downscaled to ≤512 px locally before upload. Mirrors the desktop's
/// StickerTray popover as a sheet.
struct ChatKitStickerTray: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let threadID: String
  let replyToID: String?
  var onSent: () -> Void = {}

  @State private var pickedSticker: PhotosPickerItem?
  @State private var isUploading = false
  @State private var sendingID: String?

  private var store: ChatStore { model.chatStore }
  private var stickers: [MaxSticker] { store.stickers ?? [] }

  private let grid = [GridItem(.adaptive(minimum: 84), spacing: MaxSpace.sm)]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: grid, spacing: MaxSpace.sm) {
          ForEach(stickers) { sticker in
            stickerCell(sticker)
          }
          addTile
        }
        .padding(MaxSpace.md)

        if stickers.isEmpty {
          Text("No stickers yet. Add one from your photos.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, MaxSpace.md)
        }
      }
      .navigationTitle("Stickers")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
      }
      .maxScreenBackground()
      .task { await store.loadStickers() }
      .onChange(of: pickedSticker) { handlePickedSticker() }
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_chatkit_sticker_tray")
  }

  private func stickerCell(_ sticker: MaxSticker) -> some View {
    Button {
      send(sticker)
    } label: {
      ZStack(alignment: .topTrailing) {
        MaxAsyncImage(url: sticker.url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFit()
          } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.quaternary)
              .overlay {
                Text(verbatim: sticker.emoji ?? "🙂")
                  .font(.title2)
              }
          }
        }
        .frame(width: 84, height: 84)

        if sticker.favorite {
          Image(systemName: "star.fill")
            .font(.caption2)
            .foregroundStyle(.yellow)
            .padding(4)
        }
        if sendingID == sticker.id {
          ProgressView()
            .frame(width: 84, height: 84)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(sendingID != nil)
    .contextMenu {
      Button {
        Task { await store.toggleStickerFavorite(sticker.id) }
      } label: {
        if sticker.favorite {
          Label("Unfavorite", systemImage: "star.slash")
        } else {
          Label("Favorite", systemImage: "star")
        }
      }
      Button(role: .destructive) {
        Task { await store.removeSticker(sticker.id) }
      } label: {
        Label("Remove", systemImage: "trash")
      }
    }
    .accessibilityLabel(Text("Send sticker"))
  }

  private var addTile: some View {
    PhotosPicker(selection: $pickedSticker, matching: .images) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        if isUploading {
          ProgressView()
        } else {
          Image(systemName: "plus")
            .font(.title2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 84, height: 84)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .disabled(isUploading)
    .accessibilityLabel(Text("Add sticker"))
    .accessibilityIdentifier("ui_chatkit_sticker_add")
  }

  private func send(_ sticker: MaxSticker) {
    guard sendingID == nil else { return }
    sendingID = sticker.id
    Task {
      let sent = await store.sendSticker(
        to: threadID,
        stickerID: sticker.id,
        replyToID: replyToID
      )
      sendingID = nil
      if sent != nil {
        onSent()
        dismiss()
      }
    }
  }

  private func handlePickedSticker() {
    guard let item = pickedSticker, !isUploading else { return }
    pickedSticker = nil
    isUploading = true
    Task {
      defer { isUploading = false }
      guard let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let jpeg = Self.stickerJPEGData(from: image) else {
        return
      }
      _ = await store.createSticker(imageData: jpeg, mimeType: "image/jpeg")
    }
  }

  /// Downscales a picked image so its longest side is at most 512 px, then
  /// re-encodes as JPEG — sticker size, mirroring the desktop's resize.
  static func stickerJPEGData(from image: UIImage) -> Data? {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return nil }
    let scale = longest > 512 ? 512 / longest : 1
    let target = CGSize(
      width: max(image.size.width * scale, 1),
      height: max(image.size.height * scale, 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: target, format: format)
    let resized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.jpegData(compressionQuality: 0.85)
  }
}
