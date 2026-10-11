import Foundation
import UIKit

@MainActor
protocol MemoryCycleStore {
  func loadState() -> MemoriesLocalState
  func saveState(_ state: MemoriesLocalState)
  func resetState()
}

@MainActor
final class LocalMemoriesFileStore {
  private let fileManager: FileManager
  private let rootURL: URL
  private let stateURL: URL
  private let indexURL: URL
  private let thumbnailsURL: URL
  private let exportsURL: URL
  private let encoder: JSONEncoder
  private let decoder = JSONDecoder()
  private var thumbnailWriteCount = 0

  init(
    fileManager: FileManager = .default,
    namespace: String = "MaxLocalMemories",
    rootOverride: URL? = nil
  ) {
    self.fileManager = fileManager
    let applicationSupport = (try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? fileManager.temporaryDirectory
    let root = rootOverride
      ?? applicationSupport.appendingPathComponent(namespace, isDirectory: true)
    rootURL = root
    stateURL = root.appendingPathComponent("state.json")
    indexURL = root.appendingPathComponent("index.json")
    thumbnailsURL = root.appendingPathComponent("Thumbnails", isDirectory: true)
    exportsURL = root.appendingPathComponent("Exports", isDirectory: true)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    prepareDirectories()
  }

  func loadState() -> MemoriesLocalState {
    decode(MemoriesLocalState.self, from: stateURL) ?? MemoriesLocalState()
  }

  func saveState(_ state: MemoriesLocalState) {
    encode(state, to: stateURL)
  }

  func resetState() {
    try? fileManager.removeItem(at: stateURL)
  }

  func loadIndex() -> MemoryIndexSnapshot? {
    decode(MemoryIndexSnapshot.self, from: indexURL)
  }

  func saveIndex(_ candidates: [MemoryCandidate], generatedAt: Date = Date()) async {
    let destination = indexURL
    let snapshot = MemoryIndexSnapshot(generatedAt: generatedAt, candidates: candidates)
    await Task.detached(priority: .utility) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      guard let data = try? encoder.encode(snapshot) else { return }
      do {
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
      } catch {
        try? data.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: destination.path
        )
      }
    }.value
  }

  func loadThumbnail(identifier: String) -> UIImage? {
    let url = thumbnailURL(identifier: identifier)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }

  func saveThumbnail(_ image: UIImage, identifier: String) {
    guard let data = image.jpegData(compressionQuality: 0.82) else { return }
    writeProtected(data, to: thumbnailURL(identifier: identifier))
    thumbnailWriteCount += 1
    if thumbnailWriteCount.isMultiple(of: 24) {
      pruneThumbnailCache(maximumFileCount: 240)
    }
  }

  func clearThumbnailCache() {
    try? fileManager.removeItem(at: thumbnailsURL)
    createProtectedDirectory(at: thumbnailsURL)
  }

  func resetIndexAndCaches() {
    try? fileManager.removeItem(at: indexURL)
    try? fileManager.removeItem(at: thumbnailsURL)
    try? fileManager.removeItem(at: exportsURL)
    createProtectedDirectory(at: thumbnailsURL)
    createProtectedDirectory(at: exportsURL)
  }

  func nextExportURL(pathExtension: String) -> URL {
    cleanupStaleExports()
    let fileExtension = pathExtension.isEmpty ? "bin" : pathExtension
    return exportsURL
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fileExtension)
  }

  func protectExport(at url: URL) {
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
  }

  func metrics() -> MemoryStorageMetrics {
    let snapshot = loadIndex()
    return MemoryStorageMetrics(
      indexedAssetCount: snapshot?.candidates.count ?? 0,
      thumbnailCacheBytes: directorySize(at: thumbnailsURL),
      lastIndexedAt: snapshot?.generatedAt
    )
  }

  private func prepareDirectories() {
    createProtectedDirectory(at: rootURL)
    createProtectedDirectory(at: thumbnailsURL)
    createProtectedDirectory(at: exportsURL)
  }

  private func createProtectedDirectory(at url: URL) {
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    var protectedURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? protectedURL.setResourceValues(values)
  }

  private func encode<T: Encodable>(_ value: T, to url: URL) {
    guard let data = try? encoder.encode(value) else { return }
    writeProtected(data, to: url)
  }

  private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(type, from: data)
  }

  private func writeProtected(_ data: Data, to url: URL) {
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    } catch {
      try? data.write(to: url, options: .atomic)
      try? fileManager.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: url.path
      )
    }
  }

  private func thumbnailURL(identifier: String) -> URL {
    thumbnailsURL
      .appendingPathComponent(stableFilename(for: identifier))
      .appendingPathExtension("jpg")
  }

  private func stableFilename(for value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= prime
    }
    return String(hash, radix: 16)
  }

  private func cleanupStaleExports() {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let files = try? fileManager.contentsOfDirectory(
      at: exportsURL,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }
    let expirationDate = Date().addingTimeInterval(-86_400)
    for file in files {
      let modifiedAt = try? file.resourceValues(forKeys: Set(keys)).contentModificationDate
      if modifiedAt.map({ $0 < expirationDate }) ?? true {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  private func directorySize(at url: URL) -> Int64 {
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }
    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
      size += Int64(values?.fileSize ?? 0)
    }
    return size
  }

  private func pruneThumbnailCache(maximumFileCount: Int) {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard var files = try? fileManager.contentsOfDirectory(
      at: thumbnailsURL,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ), files.count > maximumFileCount else {
      return
    }
    files.sort { lhs, rhs in
      let left = try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate
      let right = try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate
      return (left ?? .distantPast) < (right ?? .distantPast)
    }
    for file in files.prefix(files.count - maximumFileCount) {
      try? fileManager.removeItem(at: file)
    }
  }
}

@MainActor
final class AppMemoryCycleStore: MemoryCycleStore {
  private let files: LocalMemoriesFileStore

  init(files: LocalMemoriesFileStore = LocalMemoriesFileStore()) {
    self.files = files
  }

  func loadState() -> MemoriesLocalState {
    files.loadState()
  }

  func saveState(_ state: MemoriesLocalState) {
    files.saveState(state)
  }

  func resetState() {
    files.resetState()
  }
}
