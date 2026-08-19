import Foundation
import Observation

@MainActor
@Observable
final class TransferStore {
  private struct DownloadManifestEntry: Codable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let remoteURL: URL?
    let sizeBytes: Int
    let downloadedAt: Date
    let kind: String
  }

  private let api: any MaxService
  private let storageNamespace: String
  private let allowsLocalFixtureURLs: Bool

  private(set) var records: [TransferRecord]
  private(set) var items: [LocalDownload]
  private(set) var uploadPhase: LoadState<[String]> = .idle
  private(set) var lastUploadedFileIDs: [String] = []

  @ObservationIgnored private var runningTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingUploadFiles: [UUID: MobileUploadFile] = [:]
  @ObservationIgnored private weak var networkMonitor: NetworkMonitor?

  init(
    api: any MaxService,
    storageNamespace: String = "MaxTransfers",
    allowsLocalFixtureURLs: Bool = false
  ) {
    self.api = api
    self.storageNamespace = Self.safeStorageNamespace(storageNamespace)
    self.allowsLocalFixtureURLs = allowsLocalFixtureURLs
    self.items = Self.loadDownloads(storageNamespace: self.storageNamespace)
    self.records = Self.loadTransferRecords(storageNamespace: self.storageNamespace)

    var downloadsByID: [String: LocalDownload] = [:]
    for item in self.items {
      downloadsByID[item.id] = item
    }
    for index in self.records.indices {
      if self.records[index].state.isActive {
        self.records[index].state = .failed
        self.records[index].progress = nil
        self.records[index].errorReason = String(localized: "error.transfer.interrupted")
        self.records[index].updatedAt = Date()
      }
      if self.records[index].kind == .download,
         let sourceID = self.records[index].sourceID,
         let download = downloadsByID[sourceID] {
        self.records[index].localURL = download.localURL
        if self.records[index].state == .completed {
          self.records[index].progress = 1
        }
      }
    }
    Self.saveTransferRecords(self.records, storageNamespace: self.storageNamespace)
  }

  var activeRecords: [TransferRecord] {
    records.filter { $0.state.isActive }
  }

  var completedRecords: [TransferRecord] {
    records.filter { $0.state == .completed }
  }

  var usedBytes: Int {
    let total = items.reduce(Int64(0)) { partial, item in
      partial + Int64(max(item.sizeBytes, 0))
    }
    return total > Int64(Int.max) ? Int.max : Int(total)
  }

  var progress: [String: Double] {
    var result: [String: Double] = [:]
    for record in records.sorted(by: { $0.updatedAt < $1.updatedAt }) {
      guard record.kind == .download,
            let sourceID = record.sourceID,
            record.state.isActive,
            let progress = record.progress else {
        continue
      }
      result[sourceID] = progress
    }
    return result
  }

  var failures: [String: String] {
    var result: [String: String] = [:]
    for record in records.sorted(by: { $0.updatedAt < $1.updatedAt }) {
      guard record.kind == .download,
            let sourceID = record.sourceID,
            record.state == .failed,
            let reason = record.errorReason else {
        continue
      }
      result[sourceID] = reason
    }
    return result
  }

  func record(id: UUID) -> TransferRecord? {
    records.first { $0.id == id }
  }

  func reset() {
    cancelAll()
    pendingUploadFiles = [:]
    uploadPhase = .idle
    lastUploadedFileIDs = []
  }

  func resetDemoStorage() {
    guard storageNamespace == "MaxDemoTransfers" else { return }
    cancelAll()
    if let root = try? Self.rootDirectory(storageNamespace: storageNamespace) {
      try? FileManager.default.removeItem(at: root)
    }
    items = []
    records = []
    pendingUploadFiles = [:]
    uploadPhase = .idle
    lastUploadedFileIDs = []
    Self.saveDownloads([], storageNamespace: storageNamespace)
    Self.saveTransferRecords([], storageNamespace: storageNamespace)
  }

  @discardableResult
  func upload(
    files: [MobileUploadFile],
    spaceID: String? = nil
  ) async -> [String]? {
    guard !files.isEmpty else { return nil }
    uploadPhase = .loading

    let recordIDs = files.map { enqueueUpload($0, spaceID: spaceID) }
    for recordID in recordIDs {
      await startAndWait(recordID)
    }

    let fileIDs = recordIDs.compactMap { record(id: $0)?.resultingFileID }
    lastUploadedFileIDs = fileIDs
    guard fileIDs.count == recordIDs.count else {
      let reason = recordIDs
        .compactMap { record(id: $0)?.errorReason }
        .first ?? String(localized: "error.upload.incomplete")
      uploadPhase = .failed(reason)
      return nil
    }

    uploadPhase = .loaded(fileIDs)
    return fileIDs
  }

  /// Wires the one signal the download-network policy needs. It is optional so
  /// the store can still be constructed in tests and in the demo service.
  func configure(networkMonitor: NetworkMonitor?) {
    self.networkMonitor = networkMonitor
  }

  func download(_ item: MaxMediaItem) async {
    if localURL(for: item) != nil { return }

    // The single enforcement point for the download-network preference. Nine
    // call sites used to reach this method with no check at all, which is what
    // made the Settings picker a no-op.
    if !Self.allowsCellularDownloads, networkMonitor?.isExpensive == true {
      let blockedID = enqueueDownload(item)
      markFailed(
        blockedID,
        reason: String(localized: "error.product.download_policy.reason")
      )
      return
    }

    if let existing = records.last(where: {
      $0.kind == .download && $0.sourceID == item.id && $0.state.isActive
    }) {
      await waitForRunningTask(existing.id)
      return
    }

    let recordID = enqueueDownload(item)
    await startAndWait(recordID)
  }

  func retry(_ recordID: UUID) {
    guard let record = record(id: recordID),
          record.state.canRetry,
          runningTasks[recordID] == nil else {
      return
    }

    mutateRecord(recordID) { record in
      record.state = .retrying
      record.progress = nil
      record.errorReason = nil
    }
    if record.kind == .upload {
      uploadPhase = .loading
    }

    let task = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self else { return }
      await self.perform(recordID)
      self.runningTasks[recordID] = nil
    }
    runningTasks[recordID] = task
  }

  func cancel(_ recordID: UUID) {
    guard let record = record(id: recordID), record.state.canCancel else { return }
    runningTasks[recordID]?.cancel()
    if runningTasks[recordID] == nil {
      markCancelled(recordID)
    }
  }

  func cancelAll() {
    let cancellableIDs = records.filter { $0.state.canCancel }.map(\.id)
    for recordID in cancellableIDs {
      cancel(recordID)
    }
  }

  func localURL(for item: MaxMediaItem) -> URL? {
    guard let url = items.first(where: { $0.id == item.id })?.localURL,
          FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  func remove(_ item: LocalDownload) {
    if FileManager.default.fileExists(atPath: item.localURL.path) {
      try? FileManager.default.removeItem(at: item.localURL)
    }
    items.removeAll { $0.id == item.id }
    Self.saveDownloads(items, storageNamespace: storageNamespace)

    for index in records.indices where
      records[index].kind == .download && records[index].sourceID == item.id {
      records[index].state = .cancelled
      records[index].progress = nil
      records[index].localURL = nil
      records[index].errorReason = nil
      records[index].updatedAt = Date()
    }
    persistRecords()
  }

  func removeAllDownloads() {
    for item in items {
      if FileManager.default.fileExists(atPath: item.localURL.path) {
        try? FileManager.default.removeItem(at: item.localURL)
      }
    }
    items = []
    Self.saveDownloads(items, storageNamespace: storageNamespace)

    for index in records.indices where records[index].kind == .download {
      records[index].state = .cancelled
      records[index].progress = nil
      records[index].localURL = nil
      records[index].errorReason = nil
      records[index].updatedAt = Date()
    }
    persistRecords()
  }

  func clearFinishedRecords() {
    let removable = Set(
      records.filter { !$0.state.isActive }.map(\.id)
    )
    records.removeAll { removable.contains($0.id) }
    persistRecords()
  }

  private func enqueueUpload(_ file: MobileUploadFile, spaceID: String?) -> UUID {
    let recordID = UUID()
    let record = TransferRecord(
      id: recordID,
      kind: .upload,
      displayName: Self.safeFileName(
        file.fileName,
        fallback: String(localized: "transfer.kind.upload")
      ),
      createdAt: Date(),
      state: .queued,
      progress: nil,
      bytesTransferred: 0,
      totalBytes: Int64(file.byteCount),
      sourceID: file.id.uuidString,
      sourceURL: nil,
      mediaKind: nil,
      stagedFileURL: nil,
      mimeType: Self.safeMIMEType(file.mimeType),
      spaceID: spaceID,
      resultingFileID: nil,
      localURL: nil,
      errorReason: nil,
      attemptCount: 0,
      updatedAt: Date()
    )
    records.append(record)
    pendingUploadFiles[recordID] = file
    persistRecords()
    return recordID
  }

  private func enqueueDownload(_ item: MaxMediaItem) -> UUID {
    let recordID = UUID()
    let record = TransferRecord(
      id: recordID,
      kind: .download,
      displayName: item.title,
      createdAt: Date(),
      state: .queued,
      progress: nil,
      bytesTransferred: 0,
      totalBytes: item.sizeBytes > 0 ? Int64(item.sizeBytes) : nil,
      sourceID: item.id,
      sourceURL: item.downloadable ? item.mediaUrl : nil,
      mediaKind: item.kind,
      stagedFileURL: nil,
      mimeType: nil,
      spaceID: nil,
      resultingFileID: nil,
      localURL: nil,
      errorReason: item.downloadable
        ? nil
        : String(localized: "error.download.unavailable"),
      attemptCount: 0,
      updatedAt: Date()
    )
    records.append(record)
    persistRecords()
    return recordID
  }

  private func startAndWait(_ recordID: UUID) async {
    if let existing = runningTasks[recordID] {
      await existing.value
      return
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.perform(recordID)
    }
    runningTasks[recordID] = task
    await task.value
    runningTasks[recordID] = nil
  }

  private func waitForRunningTask(_ recordID: UUID) async {
    await runningTasks[recordID]?.value
  }

  private func perform(_ recordID: UUID) async {
    guard let record = record(id: recordID), record.state != .completed else { return }
    do {
      try Task.checkCancellation()
      switch record.kind {
      case .upload:
        try await performUpload(recordID)
      case .download:
        try await performDownload(recordID)
      }
    } catch is CancellationError {
      markCancelled(recordID)
    } catch let error as URLError where error.code == .cancelled {
      markCancelled(recordID)
    } catch {
      markFailed(
        recordID,
        reason: ProductError.from(
          error,
          area: .transfers,
          fallback: .downloadFailed
        ).reason
      )
    }
  }

  private func performUpload(_ recordID: UUID) async throws {
    mutateRecord(recordID) { record in
      record.state = .preparing
      record.attemptCount += 1
      record.progress = 0
      record.bytesTransferred = 0
      record.errorReason = nil
    }

    guard var transfer = record(id: recordID) else { throw TransferStoreError.missingRecord }
    var stagedURL = transfer.stagedFileURL
    if stagedURL == nil || !FileManager.default.fileExists(atPath: stagedURL?.path ?? "") {
      guard let file = pendingUploadFiles[recordID] else {
        throw TransferStoreError.missingUploadSource
      }
      let storageNamespace = storageNamespace
      stagedURL = try await Task.detached(priority: .utility) {
        try Self.stage(
          file: file,
          recordID: recordID,
          storageNamespace: storageNamespace
        )
      }.value
      mutateRecord(recordID) { record in
        record.stagedFileURL = stagedURL
      }
    }
    pendingUploadFiles[recordID] = nil

    guard let stagedURL else { throw TransferStoreError.missingUploadSource }
    try Task.checkCancellation()
    mutateRecord(recordID) { record in
      record.state = .uploading
      record.progress = 0
    }

    transfer = record(id: recordID) ?? transfer
    let response = try await api.uploadMultipart(
      fileURL: stagedURL,
      mimeType: transfer.mimeType ?? "application/octet-stream",
      spaceID: transfer.spaceID,
      fileName: transfer.displayName,
      progress: { [weak self] progress in
        Task { @MainActor [weak self] in
          self?.updateProgress(recordID, progress: progress)
        }
      }
    )
    try Task.checkCancellation()
    guard let fileID = response.fileId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !fileID.isEmpty else {
      throw TransferStoreError.missingUploadedFileID
    }

    try? FileManager.default.removeItem(at: stagedURL)
    mutateRecord(recordID) { record in
      record.state = .completed
      record.progress = 1
      record.bytesTransferred = record.totalBytes ?? record.bytesTransferred
      record.resultingFileID = fileID
      record.stagedFileURL = nil
      record.errorReason = nil
    }
    lastUploadedFileIDs = Self.unique(lastUploadedFileIDs + [fileID])
    uploadPhase = .loaded(lastUploadedFileIDs)
  }

  private func performDownload(_ recordID: UUID) async throws {
    mutateRecord(recordID) { record in
      record.state = .preparing
      record.attemptCount += 1
      record.progress = 0
      record.bytesTransferred = 0
      record.errorReason = nil
    }
    guard let transfer = record(id: recordID) else { throw TransferStoreError.missingRecord }
    guard let remoteURL = transfer.sourceURL else {
      throw TransferStoreError.missingDownloadURL
    }
    guard MaxConfiguration.isValidRemoteMediaURL(remoteURL)
      || (allowsLocalFixtureURLs && Self.isSafeDemoFixtureURL(remoteURL)) else {
      throw TransferStoreError.invalidDownloadURL
    }
    try Task.checkCancellation()

    mutateRecord(recordID) { record in
      record.state = .downloading
      record.progress = 0
    }
    let temporary = try await api.downloadFile(
      from: remoteURL,
      progress: { [weak self] progress in
        Task { @MainActor [weak self] in
          self?.updateProgress(recordID, progress: progress)
        }
      }
    )
    var shouldRemoveTemporary = true
    defer {
      if shouldRemoveTemporary {
        try? FileManager.default.removeItem(at: temporary.url)
      }
    }
    try Task.checkCancellation()

    let directory = try Self.downloadDirectory(storageNamespace: storageNamespace)
    let sourceID = transfer.sourceID ?? recordID.uuidString
    let remoteName = temporary.suggestedFilename?.removingPercentEncoding
      ?? remoteURL.lastPathComponent.removingPercentEncoding
      ?? remoteURL.lastPathComponent
    let safeName = Self.safeFileName(remoteName, fallback: sourceID)
    let safeSourceID = Self.safeFileName(sourceID, fallback: recordID.uuidString)
    let targetURL = directory.appendingPathComponent("\(safeSourceID)-\(safeName)")
    if FileManager.default.fileExists(atPath: targetURL.path) {
      try FileManager.default.removeItem(at: targetURL)
    }
    try FileManager.default.moveItem(at: temporary.url, to: targetURL)
    shouldRemoveTemporary = false
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: targetURL.path
    )

    let attributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
    guard size > 0 else {
      try? FileManager.default.removeItem(at: targetURL)
      throw TransferStoreError.emptyDownload
    }
    if let expected = temporary.expectedContentLength,
       expected > 0,
       Int64(size) != expected {
      try? FileManager.default.removeItem(at: targetURL)
      throw TransferStoreError.incompleteDownload
    }

    let download = LocalDownload(
      id: sourceID,
      title: transfer.displayName,
      localURL: targetURL,
      remoteURL: remoteURL,
      sizeBytes: size,
      downloadedAt: Date(),
      kind: transfer.mediaKind ?? "document"
    )
    items.removeAll { $0.id == sourceID }
    items.append(download)
    Self.saveDownloads(items, storageNamespace: storageNamespace)

    mutateRecord(recordID) { record in
      record.state = .completed
      record.progress = 1
      record.bytesTransferred = Int64(size)
      record.totalBytes = Int64(size)
      record.localURL = targetURL
      record.errorReason = nil
    }
  }

  private func updateProgress(_ recordID: UUID, progress: TransferProgress) {
    mutateRecord(recordID, persist: false) { record in
      guard record.state == .uploading || record.state == .downloading else { return }
      record.bytesTransferred = progress.bytesTransferred
      record.totalBytes = progress.totalBytes ?? record.totalBytes
      record.progress = progress.fractionCompleted
    }
  }

  private func markCancelled(_ recordID: UUID) {
    mutateRecord(recordID) { record in
      record.state = .cancelled
      record.progress = nil
      record.errorReason = nil
    }
    if record(id: recordID)?.kind == .upload {
      uploadPhase = .failed(String(localized: "error.upload.cancelled"))
    }
  }

  private func markFailed(_ recordID: UUID, reason: String) {
    mutateRecord(recordID) { record in
      record.state = .failed
      record.progress = nil
      record.errorReason = reason.isEmpty ? "Transfer failed" : reason
    }
    if record(id: recordID)?.kind == .upload {
      uploadPhase = .failed(
        reason.isEmpty ? String(localized: "error.upload.failed") : reason
      )
    }
  }

  private func mutateRecord(
    _ recordID: UUID,
    persist: Bool = true,
    _ mutation: (inout TransferRecord) -> Void
  ) {
    guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
    mutation(&records[index])
    records[index].updatedAt = Date()
    if persist { persistRecords() }
  }

  private func persistRecords() {
    Self.saveTransferRecords(records, storageNamespace: storageNamespace)
  }

  nonisolated private static func stage(
    file: MobileUploadFile,
    recordID: UUID,
    storageNamespace: String
  ) throws -> URL {
    let directory = try uploadStagingDirectory(storageNamespace: storageNamespace)
    let fileName = safeFileName(file.fileName, fallback: "upload")
    let url = directory.appendingPathComponent("\(recordID.uuidString)-\(fileName)")

    switch file.source {
    case .data(let data):
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    case .file(let sourceURL, let removeAfterStaging):
      try FileManager.default.copyItem(at: sourceURL, to: url)
      if removeAfterStaging {
        try? FileManager.default.removeItem(at: sourceURL)
      }
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: url.path
      )
    }
    return url
  }

  nonisolated private static func rootDirectory(storageNamespace: String) throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let folder = root.appendingPathComponent(
      safeStorageNamespace(storageNamespace),
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: folder.path
    )
    return folder
  }

  private static func downloadDirectory(storageNamespace: String) throws -> URL {
    let folder = try rootDirectory(storageNamespace: storageNamespace)
      .appendingPathComponent("Downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: folder.path
    )
    return folder
  }

  nonisolated private static func uploadStagingDirectory(storageNamespace: String) throws -> URL {
    let folder = try rootDirectory(storageNamespace: storageNamespace)
      .appendingPathComponent("UploadStaging", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: folder.path
    )
    return folder
  }

  private static func transferManifestURL(storageNamespace: String) throws -> URL {
    try rootDirectory(storageNamespace: storageNamespace)
      .appendingPathComponent("transfers.json")
  }

  private static func downloadManifestURL(storageNamespace: String) throws -> URL {
    try downloadDirectory(storageNamespace: storageNamespace)
      .appendingPathComponent("manifest.json")
  }

  private static func loadTransferRecords(storageNamespace: String) -> [TransferRecord] {
    guard let url = try? transferManifestURL(storageNamespace: storageNamespace),
          let data = try? Data(contentsOf: url),
          let records = try? JSONDecoder().decode([TransferRecord].self, from: data) else {
      return []
    }
    return records.sorted { $0.createdAt < $1.createdAt }
  }

  private static func saveTransferRecords(
    _ records: [TransferRecord],
    storageNamespace: String
  ) {
    guard let url = try? transferManifestURL(storageNamespace: storageNamespace),
          let data = try? JSONEncoder().encode(records) else {
      return
    }
    try? data.write(to: url, options: [.atomic, .completeFileProtection])
  }

  private static func loadDownloads(storageNamespace: String) -> [LocalDownload] {
    if let manifestURL = try? downloadManifestURL(storageNamespace: storageNamespace),
       let data = try? Data(contentsOf: manifestURL),
       let entries = try? JSONDecoder().decode([DownloadManifestEntry].self, from: data),
       let directory = try? downloadDirectory(storageNamespace: storageNamespace) {
      return entries.compactMap { entry in
        let safeName = safeFileName(entry.fileName, fallback: entry.id)
        let localURL = directory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        let actualSize = (attributes?[.size] as? NSNumber)?.intValue ?? entry.sizeBytes
        guard actualSize > 0 else { return nil }
        return LocalDownload(
          id: entry.id,
          title: entry.title,
          localURL: localURL,
          remoteURL: entry.remoteURL,
          sizeBytes: actualSize,
          downloadedAt: entry.downloadedAt,
          kind: entry.kind
        )
      }
    }
    guard storageNamespace == "MaxTransfers" else { return [] }
    return migrateLegacyDownloads(storageNamespace: storageNamespace)
  }

  private static func migrateLegacyDownloads(storageNamespace: String) -> [LocalDownload] {
    guard let applicationSupport = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ),
    let destinationDirectory = try? downloadDirectory(storageNamespace: storageNamespace) else {
      return []
    }
    let legacyDirectory = applicationSupport.appendingPathComponent("Downloads", isDirectory: true)
    let legacyManifest = legacyDirectory.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: legacyManifest),
          let legacy = try? JSONDecoder().decode([LocalDownload].self, from: data) else {
      return []
    }

    let migrated = legacy.compactMap { download -> LocalDownload? in
      guard FileManager.default.fileExists(atPath: download.localURL.path) else { return nil }
      let name = safeFileName(download.localURL.lastPathComponent, fallback: download.id)
      let destination = destinationDirectory.appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: destination.path) {
        do {
          try FileManager.default.moveItem(at: download.localURL, to: destination)
        } catch {
          guard (try? FileManager.default.copyItem(at: download.localURL, to: destination)) != nil
          else { return nil }
        }
      }
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: destination.path
      )
      return LocalDownload(
        id: download.id,
        title: download.title,
        localURL: destination,
        remoteURL: download.remoteURL,
        sizeBytes: download.sizeBytes,
        downloadedAt: download.downloadedAt,
        kind: download.kind
      )
    }
    saveDownloads(migrated, storageNamespace: storageNamespace)
    return migrated
  }

  private static func saveDownloads(
    _ downloads: [LocalDownload],
    storageNamespace: String
  ) {
    let entries = downloads.map { download in
      DownloadManifestEntry(
        id: download.id,
        title: download.title,
        fileName: download.localURL.lastPathComponent,
        remoteURL: download.remoteURL,
        sizeBytes: download.sizeBytes,
        downloadedAt: download.downloadedAt,
        kind: download.kind
      )
    }
    guard let url = try? downloadManifestURL(storageNamespace: storageNamespace),
          let data = try? JSONEncoder().encode(entries) else {
      return
    }
    try? data.write(to: url, options: [.atomic, .completeFileProtection])
  }

  /// Mirrors `AppPreferencesStore.allowsCellularDownloads` by reading the same
  /// stored value, so this store needs no dependency on a type constructed
  /// after it. `wifiOnly` is the stored default.
  nonisolated private static var allowsCellularDownloads: Bool {
    UserDefaults.standard.string(forKey: "app.max.preferences.downloadNetwork") == "wifiAndCellular"
  }

  nonisolated private static func safeFileName(
    _ source: String,
    fallback: String
  ) -> String {
    let illegal = CharacterSet(charactersIn: "/\\:\0\r\n\t\"")
      .union(.controlCharacters)
    let cleaned = source
      .components(separatedBy: illegal)
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = cleaned.isEmpty ? fallback : cleaned
    return String(candidate.prefix(160))
  }

  nonisolated private static func safeStorageNamespace(_ source: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed.count <= 64,
          trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      return "MaxTransfers"
    }
    return trimmed
  }

  nonisolated private static func isSafeDemoFixtureURL(_ url: URL) -> Bool {
    if url.scheme == "max-demo", url.host == "fixture" { return true }
    guard url.isFileURL,
          let resources = Bundle.main.resourceURL?.standardizedFileURL else {
      return false
    }
    let candidate = url.standardizedFileURL
    let rootPath = resources.path.hasSuffix("/") ? resources.path : resources.path + "/"
    return candidate.path.hasPrefix(rootPath)
  }

  private static func safeMIMEType(_ source: String) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.contains("\r"),
          !trimmed.contains("\n") else {
      return "application/octet-stream"
    }
    return trimmed
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}

enum TransferStoreError: Error, LocalizedError, Sendable {
  case missingRecord
  case missingUploadSource
  case missingUploadedFileID
  case missingDownloadURL
  case invalidDownloadURL
  case emptyDownload
  case incompleteDownload

  var errorDescription: String? {
    switch self {
    case .missingRecord:
      String(localized: "error.transfer.missing_record")
    case .missingUploadSource:
      String(localized: "error.upload.source_missing")
    case .missingUploadedFileID:
      String(localized: "error.upload.missing_file_id")
    case .missingDownloadURL:
      String(localized: "error.download.missing_url")
    case .invalidDownloadURL:
      String(localized: "error.download.invalid_url")
    case .emptyDownload:
      String(localized: "error.download.empty_file")
    case .incompleteDownload:
      String(localized: "error.download.incomplete_file")
    }
  }
}
