import Foundation

enum TransferKind: String, Codable, CaseIterable, Sendable {
  case upload
  case download
}

enum TransferState: String, Codable, CaseIterable, Sendable {
  case queued
  case preparing
  case uploading
  case downloading
  case completed
  case failed
  case cancelled
  case retrying

  var isActive: Bool {
    switch self {
    case .queued, .preparing, .uploading, .downloading, .retrying:
      true
    case .completed, .failed, .cancelled:
      false
    }
  }

  var canRetry: Bool {
    self == .failed || self == .cancelled
  }

  var canCancel: Bool {
    isActive
  }
}

struct TransferRecord: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  let kind: TransferKind
  let displayName: String
  let createdAt: Date

  var state: TransferState
  var progress: Double?
  var bytesTransferred: Int64
  var totalBytes: Int64?
  var sourceID: String?
  var sourceURL: URL?
  var mediaKind: String?
  var stagedFileURL: URL?
  var mimeType: String?
  var spaceID: String?
  var resultingFileID: String?
  var localURL: URL?
  var errorReason: String?
  var attemptCount: Int
  var updatedAt: Date
}

enum MobileUploadSource: Sendable {
  case data(Data)
  case file(URL, removeAfterStaging: Bool)
}

struct MobileUploadFile: Sendable, Identifiable {
  let id: UUID
  let source: MobileUploadSource
  let byteCount: Int
  let fileName: String
  let mimeType: String

  init(
    id: UUID = UUID(),
    data: Data,
    fileName: String,
    mimeType: String
  ) {
    self.id = id
    self.source = .data(data)
    self.byteCount = data.count
    self.fileName = fileName
    self.mimeType = mimeType
  }

  init(
    id: UUID = UUID(),
    fileURL: URL,
    byteCount: Int,
    fileName: String,
    mimeType: String,
    removeAfterStaging: Bool = true
  ) {
    self.id = id
    self.source = .file(fileURL, removeAfterStaging: removeAfterStaging)
    self.byteCount = max(byteCount, 0)
    self.fileName = fileName
    self.mimeType = mimeType
  }

  func discardOwnedSource() {
    guard case .file(let url, removeAfterStaging: true) = source else { return }
    try? FileManager.default.removeItem(at: url)
  }
}

struct TransferProgress: Sendable {
  let bytesTransferred: Int64
  let totalBytes: Int64?

  var fractionCompleted: Double? {
    guard let totalBytes, totalBytes > 0 else { return nil }
    return min(max(Double(bytesTransferred) / Double(totalBytes), 0), 1)
  }
}
