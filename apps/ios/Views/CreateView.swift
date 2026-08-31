import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let destination: UploadDestination

  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var stagedFiles: [MobileUploadFile] = []
  @State private var caption = ""
  @State private var isImportingDocuments = false
  @State private var isPreparing = false
  @State private var preparationError: String?
  @State private var sendError: String?

  private let maximumFiles = 12
  private let maximumFileBytes = 250 * 1_024 * 1_024

  var body: some View {
    NavigationStack {
      List {
        Section {
          destinationRow
            .listRowBackground(Rectangle().fill(MaxColor.surface))
        } header: {
          MaxListSectionHeader("upload.destination")
        }

        Section {
          PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: maximumFiles,
            matching: .any(of: [.images, .videos])
          ) {
            UploadSourceLabel(
              title: "upload.choose_photos",
              symbol: "photo.on.rectangle.angled",
              color: .blue
            )
          }
          .buttonStyle(.plain)
          .disabled(isPreparing || isUploading)

          Button {
            isImportingDocuments = true
          } label: {
            UploadSourceLabel(
              title: "upload.choose_files",
              symbol: "folder.badge.plus",
              color: .purple
            )
          }
          .buttonStyle(.plain)
          .disabled(isPreparing || isUploading)
        } header: {
          MaxListSectionHeader("upload.sources")
        } footer: {
          Text("upload.sources.footer")
        }

        if !stagedFiles.isEmpty {
          Section {
            HStack {
              Label("upload.selected", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MaxColor.textPrimary)
              Spacer(minLength: MaxSpace.sm)
              Text(verbatim: "\(stagedFiles.count) / \(maximumFiles)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(MaxColor.textSecondary)
              Text(verbatim: stagedFiles.reduce(0) { $0 + $1.byteCount }.byteString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(MaxColor.textTertiary)
            }

            ForEach(stagedFiles) { file in
              HStack(spacing: MaxSpace.md) {
                Image(systemName: symbol(for: file.mimeType))
                  .foregroundStyle(MaxColor.accent)
                  .frame(width: 30)
                VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                  Text(verbatim: file.fileName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                  Text(verbatim: file.byteCount.byteString)
                    .font(.caption)
                    .foregroundStyle(MaxColor.textSecondary)
                }
                Spacer(minLength: 0)
                Button("action.remove", systemImage: "xmark.circle", role: .destructive) {
                  file.discardOwnedSource()
                  stagedFiles.removeAll { $0.id == file.id }
                }
                .labelStyle(.iconOnly)
                .disabled(isUploading)
              }
            }
          } header: {
            MaxListSectionHeader("upload.selected")
          }
        }

        if case .chat = destination {
          Section("upload.message") {
            TextField("chat.composer.placeholder", text: $caption, axis: .vertical)
              .lineLimit(2...6)
          }
        }

        if isPreparing {
          Section {
            HStack(spacing: MaxSpace.sm) {
              ProgressView()
              Text("upload.preparing")
            }
          }
        }

        if let error = (
          preparationError
            ?? sendError
            ?? model.transferStore.uploadPhase.errorMessage
        ) {
          Section {
            Label {
              Text(verbatim: error)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(MaxColor.danger)
          }
        }

        let activeUploads = model.transferStore.activeRecords.filter { $0.kind == .upload }
        if !activeUploads.isEmpty {
          Section {
            VStack(alignment: .leading, spacing: MaxSpace.sm) {
              HStack {
                Label("transfers.active", systemImage: "arrow.up.circle.fill")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(MaxColor.textPrimary)
                Spacer()
                Button("action.cancel") {
                  model.transferStore.cancelAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ui_upload_cancel_queue")
              }

              let totalBytes = activeUploads.reduce(0) { $0 + ($1.totalBytes ?? 0) }
              let transferredBytes = activeUploads.reduce(0) { $0 + $1.bytesTransferred }
              let progress = totalBytes > 0 ? Double(transferredBytes) / Double(totalBytes) : 0.0

              ProgressView(value: progress)
                .progressViewStyle(.linear)

              HStack {
                Text(verbatim: "\(Int(clamping: transferredBytes).byteString) of \(Int(clamping: totalBytes).byteString)")
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(MaxColor.textSecondary)
                Spacer()
                Text(verbatim: "\(Int(progress * 100))%")
                  .font(.caption2.bold().monospacedDigit())
                  .foregroundStyle(MaxColor.textPrimary)
              }
            }
            .padding(.vertical, MaxSpace.xs)

            ForEach(activeUploads) { record in
              TransferRow(record: record, isCompact: true)
            }
          } header: {
            MaxListSectionHeader("transfers.active")
          }
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("upload.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
            .disabled(isPreparing)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("upload.start") { beginUpload() }
            .disabled(stagedFiles.isEmpty || isPreparing || isUploading)
            .buttonStyle(MaxToolbarButtonStyle())
            .accessibilityIdentifier("ui_upload_start")
        }
      }
      .fileImporter(
        isPresented: $isImportingDocuments,
        allowedContentTypes: [.image, .movie, .audio, .pdf, .data],
        allowsMultipleSelection: true,
        onCompletion: handleDocumentSelection
      )
      .onChange(of: selectedPhotos) { _, items in
        guard !items.isEmpty else { return }
        Task { await preparePhotoItems(items) }
      }
      .onDisappear {
        stagedFiles.forEach { $0.discardOwnedSource() }
      }
      .interactiveDismissDisabled(isUploading || isPreparing)
      .accessibilityIdentifier("ui_upload_sheet")
    }
    .presentationDetents([.large])
    .maxScreenBackground()
  }

  private var isUploading: Bool {
    model.transferStore.uploadPhase.isLoading
  }

  private var destinationRow: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: destinationSymbol)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(
          LinearGradient(
            colors: [MaxColor.sky, MaxColor.periwinkle],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          in: RoundedRectangle(cornerRadius: MaxRadius.small, style: .continuous)
        )
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(destinationTitle)
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
        Text(verbatim: destinationName)
          .font(.body.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
      }
    }
    .padding(.vertical, MaxSpace.xxs)
    .accessibilityElement(children: .combine)
  }

  private var destinationTitle: LocalizedStringKey {
    switch destination {
    case .personal: "upload.destination.vault"
    case .workspace: "upload.destination.workspace"
    case .chat: "upload.destination.chat"
    }
  }

  private var destinationName: String {
    switch destination {
    case .personal:
      String(localized: "tab.vault")
    case .workspace(_, let name), .chat(_, let name):
      name
    }
  }

  private var destinationSymbol: String {
    switch destination {
    case .personal: "archivebox"
    case .workspace: "person.2"
    case .chat: "bubble.left.and.bubble.right"
    }
  }

  private func beginUpload() {
    sendError = nil
    let files = stagedFiles
    Task {
      guard let fileIDs = await model.transferStore.upload(
        files: files,
        spaceID: destination.spaceID
      ), !fileIDs.isEmpty else {
        return
      }

      switch destination {
      case .chat(let id, _):
        let sent = await model.chatStore.sendMessage(
          to: id,
          content: caption,
          mediaFileIDs: fileIDs
        )
        guard sent != nil else {
          sendError = model.chatStore.sendStateByChat[id]?.errorMessage
            ?? String(localized: "chat.send.failed")
          return
        }
      case .personal, .workspace:
        await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
      }
      dismiss()
    }
  }

  private func preparePhotoItems(_ items: [PhotosPickerItem]) async {
    isPreparing = true
    preparationError = nil
    defer {
      isPreparing = false
      selectedPhotos = []
    }

    for (index, item) in items.prefix(maximumFiles - stagedFiles.count).enumerated() {
      do {
        guard let imported = try await item.loadTransferable(type: ImportedPickerFile.self)
        else {
          throw UploadPreparationError.unreadable
        }
        var shouldDiscardImportedFile = true
        defer {
          if shouldDiscardImportedFile { imported.discard() }
        }
        let values = try imported.url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else { throw UploadPreparationError.unreadable }
        try append(
          fileURL: imported.url,
          byteCount: fileSize,
          suggestedName: photoName(for: item, index: index),
          mimeType: photoMIMEType(for: item)
        )
        shouldDiscardImportedFile = false
      } catch {
        preparationError = ProductError.from(
          error,
          area: .transfers,
          fallback: .uploadFailed
        ).reason
        break
      }
    }
  }

  private func handleDocumentSelection(_ result: Result<[URL], Error>) {
    Task { @MainActor in
      isPreparing = true
      preparationError = nil
      defer { isPreparing = false }

      do {
        let urls = try result.get()
        for url in urls.prefix(maximumFiles - stagedFiles.count) {
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }

          let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard values.isRegularFile == true else { throw UploadPreparationError.unreadable }
          if let fileSize = values.fileSize, fileSize > maximumFileBytes {
            throw UploadPreparationError.tooLarge
          }
          let copy = try UploadSelectionFiles.copy(url)
          let type = UTType(filenameExtension: url.pathExtension)
          try append(
            fileURL: copy,
            byteCount: values.fileSize ?? 0,
            suggestedName: url.lastPathComponent,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream"
          )
        }
      } catch {
        preparationError = ProductError.from(
          error,
          area: .transfers,
          fallback: .uploadFailed
        ).reason
      }
    }
  }

  private func append(
    fileURL: URL,
    byteCount: Int,
    suggestedName: String,
    mimeType: String
  ) throws {
    do {
      guard byteCount > 0 else { throw UploadPreparationError.unreadable }
      guard byteCount <= maximumFileBytes else { throw UploadPreparationError.tooLarge }
      guard stagedFiles.count < maximumFiles else { throw UploadPreparationError.tooMany }
      stagedFiles.append(
        MobileUploadFile(
          fileURL: fileURL,
          byteCount: byteCount,
          fileName: suggestedName,
          mimeType: mimeType
        )
      )
    } catch {
      try? FileManager.default.removeItem(at: fileURL)
      throw error
    }
  }

  private func photoName(for item: PhotosPickerItem, index: Int) -> String {
    let type = item.supportedContentTypes.first
    let ext = type?.preferredFilenameExtension ?? "bin"
    return "Max-\(index + 1).\(ext)"
  }

  private func photoMIMEType(for item: PhotosPickerItem) -> String {
    item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
  }

  private func symbol(for mimeType: String) -> String {
    if mimeType.hasPrefix("image/") { return "photo" }
    if mimeType.hasPrefix("video/") { return "video" }
    if mimeType.hasPrefix("audio/") { return "waveform" }
    return "doc"
  }
}

private struct UploadSourceLabel: View {
  let title: LocalizedStringKey
  let symbol: String
  let color: Color

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .foregroundStyle(color)
        .frame(width: 48, height: 48)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(MaxColor.textPrimary)
      Spacer(minLength: 0)
      Image(systemName: "plus.circle.fill")
        .font(.title3)
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surfaceSoft,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .contentShape(Rectangle())
  }
}

private struct MaxListSectionHeader: View {
  let title: LocalizedStringKey

  init(_ title: LocalizedStringKey) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(MaxColor.textPrimary)
      .textCase(nil)
  }
}

struct TransferManagerView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if model.transferStore.records.isEmpty {
          MaxEmptyState(
            title: "transfers.empty",
            subtitle: "transfers.empty.subtitle",
            symbol: "arrow.up.arrow.down"
          )
        } else {
          List {
            if !activeRecords.isEmpty {
              Section("transfers.active") {
                ForEach(activeRecords) { record in
                  TransferRow(record: record)
                }
              }
            }
            if !finishedRecords.isEmpty {
              Section("transfers.history") {
                ForEach(finishedRecords) { record in
                  TransferRow(record: record)
                }
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .maxScreenBackground()
      .navigationTitle("transfers.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.close") { dismiss() }
        }
        if !finishedRecords.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("transfers.clear") {
              model.transferStore.clearFinishedRecords()
            }
          }
        }
      }
      .accessibilityIdentifier("ui_transfer_manager")
    }
    .presentationDetents([.medium, .large])
  }

  private var activeRecords: [TransferRecord] {
    model.transferStore.records
      .filter(\.state.isActive)
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  private var finishedRecords: [TransferRecord] {
    model.transferStore.records
      .filter { !$0.state.isActive }
      .sorted { $0.updatedAt > $1.updatedAt }
  }
}

/// The transfer's leading tile: the media itself when a poster is known,
/// a kind-specific glyph otherwise. A row that shows only an arrow and a file
/// name makes the user do the remembering.
struct TransferLeadingThumb: View {
  let record: TransferRecord
  var tint: Color = .accentColor
  var size: CGFloat = 44

  var body: some View {
    Group {
      if let url = record.thumbnailURL {
        MaxAsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          default:
            glyph
          }
        }
      } else {
        glyph
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityHidden(true)
  }

  private var glyph: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.quaternary.opacity(0.6))
      Image(systemName: glyphName)
        .font(.system(size: size * 0.42, weight: .medium))
        .foregroundStyle(tint)
    }
  }

  private var glyphName: String {
    switch record.mediaKind?.lowercased() {
    case "image": return "photo"
    case "video": return "film"
    case "audio": return "waveform"
    default: return record.kind == .upload ? "arrow.up.circle" : "arrow.down.circle"
    }
  }
}

struct TransferRow: View {
  @Environment(\.maxThemePalette) private var palette
  @Environment(MaxAppModel.self) private var model
  let record: TransferRecord
  var isCompact = false

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      HStack(spacing: MaxSpace.sm) {
        TransferLeadingThumb(record: record, tint: stateColor, size: isCompact ? 36 : 44)
        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: record.displayName)
            .font(.body.weight(.semibold))
            .lineLimit(isCompact ? 1 : 2)
          Text(record.state.titleKey)
            .font(.caption)
            .foregroundStyle(MaxColor.textSecondary)
        }
        Spacer(minLength: 0)
        if record.state.canCancel {
          Button("transfer.cancel", systemImage: "xmark", role: .cancel) {
            model.transferStore.cancel(record.id)
          }
          .labelStyle(.iconOnly)
        } else if record.state.canRetry {
          Button("common.retry", systemImage: "arrow.clockwise") {
            model.transferStore.retry(record.id)
          }
          .labelStyle(.iconOnly)
        } else if record.state == .completed {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(MaxColor.mint)
            .accessibilityLabel(Text("transfer.state.completed"))
        }
      }

      if record.state.isActive {
        if let progress = record.progress {
          ProgressView(value: progress)
        } else {
          ProgressView()
        }
        if record.bytesTransferred > 0 {
          Text(verbatim: transferredBytesLabel)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(MaxColor.textSecondary)
        }
      }

      if let reason = record.errorReason, !reason.isEmpty, !isCompact {
        Text(verbatim: reason)
          .font(.caption)
          .foregroundStyle(MaxColor.danger)
      }
    }
    .padding(.vertical, MaxSpace.xxs)
  }

  private var transferredBytesLabel: String {
    let current = Int(clamping: record.bytesTransferred).byteString
    guard let total = record.totalBytes else { return current }
    return "\(current) / \(Int(clamping: total).byteString)"
  }

  private var stateColor: Color {
    switch record.state {
    case .completed: palette.success
    case .failed: palette.destructive
    case .cancelled: .secondary
    default: palette.accent
    }
  }
}

private extension TransferState {
  var titleKey: LocalizedStringKey {
    switch self {
    case .queued: "transfer.state.queued"
    case .preparing: "transfer.state.preparing"
    case .uploading: "transfer.state.uploading"
    case .downloading: "transfer.state.downloading"
    case .completed: "transfer.state.completed"
    case .failed: "transfer.state.failed"
    case .cancelled: "transfer.state.cancelled"
    case .retrying: "transfer.state.retrying"
    }
  }
}

struct CompactTransferView: View {
  @Environment(MaxAppModel.self) private var model
  let record: TransferRecord

  var body: some View {
    Button { model.openTransfers() } label: {
      MaxFloatingSurface {
        HStack(spacing: MaxSpace.sm) {
          TransferLeadingThumb(record: record, tint: MaxColor.accent, size: 28)
          VStack(alignment: .leading, spacing: MaxSpace.xxs) {
            Text(verbatim: record.displayName)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if let progress = record.progress {
              ProgressView(value: progress)
                .frame(maxWidth: 180)
            } else {
              ProgressView()
                .controlSize(.mini)
            }
          }
          Image(systemName: "chevron.up")
            .font(.caption.weight(.bold))
            .foregroundStyle(MaxColor.textSecondary)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("transfers.open_active"))
  }
}

private enum UploadPreparationError: LocalizedError {
  case unreadable
  case tooLarge
  case tooMany

  var errorDescription: String? {
    switch self {
    case .unreadable: String(localized: "upload.error.unreadable")
    case .tooLarge: String(localized: "upload.error.too_large")
    case .tooMany: String(localized: "upload.error.too_many")
    }
  }
}

private struct ImportedPickerFile: Transferable, Sendable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      Self(url: try UploadSelectionFiles.copy(received.file))
    }
    FileRepresentation(importedContentType: .movie) { received in
      Self(url: try UploadSelectionFiles.copy(received.file))
    }
  }

  func discard() {
    try? FileManager.default.removeItem(at: url)
  }
}

private enum UploadSelectionFiles {
  static func copy(_ source: URL) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MaxUploadSelections", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: directory.path
    )

    let fileName = source.lastPathComponent.isEmpty ? "selection" : source.lastPathComponent
    let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    try FileManager.default.copyItem(at: source, to: destination)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: destination.path
    )
    return destination
  }
}
