import Foundation

struct DownloadedTemporaryFile: Sendable {
  let url: URL
  let statusCode: Int
  let expectedContentLength: Int64?
  let suggestedFilename: String?
  let contentType: String?
}

private final class CancellableURLSessionTaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var cancellationRequested = false

  func install(_ task: URLSessionTask) {
    lock.lock()
    self.task = task
    let shouldCancel = cancellationRequested
    lock.unlock()
    if shouldCancel { task.cancel() }
  }

  func cancel() {
    lock.lock()
    cancellationRequested = true
    let task = self.task
    lock.unlock()
    task?.cancel()
  }
}

enum URLSessionTransferSupport {
  /// Mirrors `AppPreferencesStore.allowsCellularDownloads` by reading the same
  /// stored value. `wifiOnly` is the stored default.
  private static var allowsCellularDownloads: Bool {
    UserDefaults.standard.string(forKey: "app.max.preferences.downloadNetwork") == "wifiAndCellular"
  }

  static func download(
    session: URLSession,
    request: URLRequest,
    progress: @escaping @Sendable (TransferProgress) -> Void
  ) async throws -> DownloadedTemporaryFile {
    let taskBox = CancellableURLSessionTaskBox()
    // The transport enforces the download-network preference too, so a download
    // that outlives a change of setting — or that starts while the interface is
    // switching — cannot quietly keep spending the user's cellular data.
    let transferRequest: URLRequest = {
      var updated = request
      updated.allowsCellularAccess = allowsCellularDownloads
      return updated
    }()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let task = session.downloadTask(with: transferRequest) { location, response, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          guard let location, let response = response as? HTTPURLResponse else {
            continuation.resume(throwing: MaxAPIError.invalidResponse)
            return
          }

          do {
            let ownedURL = FileManager.default.temporaryDirectory
              .appendingPathComponent("max-download-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: ownedURL)
            let expected = response.expectedContentLength > 0
              ? response.expectedContentLength
              : nil
            continuation.resume(
              returning: DownloadedTemporaryFile(
                url: ownedURL,
                statusCode: response.statusCode,
                expectedContentLength: expected,
                suggestedFilename: response.suggestedFilename,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
              )
            )
          } catch {
            continuation.resume(throwing: error)
          }
        }

        taskBox.install(task)
        task.resume()

        Task.detached(priority: .utility) {
          while task.state == .running || task.state == .suspended {
            let expected = task.countOfBytesExpectedToReceive > 0
              ? task.countOfBytesExpectedToReceive
              : nil
            progress(
              TransferProgress(
                bytesTransferred: max(task.countOfBytesReceived, 0),
                totalBytes: expected
              )
            )
            try? await Task.sleep(nanoseconds: 120_000_000)
          }
        }
      }
    } onCancel: {
      taskBox.cancel()
    }
  }
}

final class URLSessionUploadProgressDelegate:
  NSObject,
  URLSessionTaskDelegate,
  @unchecked Sendable {
  private let progressHandler: @Sendable (TransferProgress) -> Void

  init(progressHandler: @escaping @Sendable (TransferProgress) -> Void) {
    self.progressHandler = progressHandler
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    let expected = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil
    progressHandler(
      TransferProgress(
        bytesTransferred: max(totalBytesSent, 0),
        totalBytes: expected
      )
    )
  }
}
