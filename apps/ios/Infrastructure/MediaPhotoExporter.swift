import Foundation
import Photos

enum MediaPhotoExportError: LocalizedError {
  case permissionDenied
  case unsupportedMedia
  case sourceUnavailable
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      String(localized: "error.photos.permission.reason")
    case .unsupportedMedia:
      String(localized: "error.photos.unsupported.reason")
    case .sourceUnavailable:
      String(localized: "error.photos.source.reason")
    case .saveFailed:
      String(localized: "error.photos.save.reason")
    }
  }
}

@MainActor
enum MediaPhotoExporter {
  static func save(_ item: MaxMediaItem, transferStore: TransferStore) async throws {
    let kind = item.kind.lowercased()
    guard kind == "video" || kind == "image" else {
      throw MediaPhotoExportError.unsupportedMedia
    }

    let status = await authorizationStatus()
    guard status == .authorized || status == .limited else {
      throw MediaPhotoExportError.permissionDenied
    }

    if transferStore.localURL(for: item) == nil {
      guard item.downloadable else { throw MediaPhotoExportError.sourceUnavailable }
      await transferStore.download(item)
    }
    guard let sourceURL = transferStore.localURL(for: item),
          FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw MediaPhotoExportError.sourceUnavailable
    }

    let isVideo = kind == "video"
    let ext = isVideo ? "mp4" : "jpg"
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)

    do {
      if FileManager.default.fileExists(atPath: tempURL.path) {
        try? FileManager.default.removeItem(at: tempURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: tempURL)
    } catch {
      throw MediaPhotoExportError.sourceUnavailable
    }

    defer {
      try? FileManager.default.removeItem(at: tempURL)
    }

    try await withCheckedThrowingContinuation { continuation in
      PHPhotoLibrary.shared().performChanges {
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
        }
      } completionHandler: { success, error in
        if success {
          continuation.resume(returning: ())
        } else {
          continuation.resume(throwing: error ?? MediaPhotoExportError.saveFailed)
        }
      }
    }
  }

  private static func authorizationStatus() async -> PHAuthorizationStatus {
    let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard current == .notDetermined else { return current }
    return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
  }
}
