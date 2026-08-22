import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MaxDesktopModel {
  var isAuthenticated: Bool
  var selectedDestination: SidebarDestination
  var selectedLibrarySection: LibrarySection = .overview
  var selectedThreadID: String?
  var selectedMediaID: String?
  var selectedWorkspaceID: String?
  var theme: AppTheme
  var language: AppLanguage
  var media: [MediaItem]
  var workspaces: [Workspace]
  var threads: [ChatThread]
  var profile: MaxProfile
  var transfers: [TransferRecord] = []
  var plugins: [PluginDescriptor]
  var memories: [MemoryMoment]
  var collections: [CollectionDescriptor]
  var isUploadPresented = false
  var isTransfersPresented = false
  var isMediaPresented = false
  var isRatingPresented = false
  var isProfileEditorPresented = false
  var isCommandPalettePresented = false
  var serverURL = "https://max.example.com"
  var doubleLockEnabled = true
  var wifiOnlyDownloads = true
  var diagnosticsEnabled = false
  var lastError: String?

  let apiClient: MaxAPIClient

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    let testMode = environment["MAX_MAC_UI_TESTING"] == "1"
    isAuthenticated = testMode
      ? environment["MAX_MAC_UI_TEST_AUTHENTICATED"] != "0"
      : UserDefaults.standard.bool(forKey: "max.macos.authenticated")

    selectedDestination = SidebarDestination(
      rawValue: environment["MAX_MAC_UI_TEST_DESTINATION"] ?? "vault"
    ) ?? .vault
    selectedThreadID = MaxFixtures.threads.first?.id

    theme = AppTheme(rawValue: environment["MAX_MAC_UI_TEST_THEME"] ?? "max")
      ?? AppTheme(rawValue: UserDefaults.standard.string(forKey: "max.macos.theme") ?? "max")
      ?? .max
    language = AppLanguage(rawValue: environment["MAX_MAC_UI_TEST_LANGUAGE"] ?? "en")
      ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "max.macos.language") ?? "en")
      ?? .english

    media = MaxFixtures.media
    workspaces = MaxFixtures.workspaces
    threads = MaxFixtures.threads
    profile = MaxFixtures.profile
    plugins = MaxFixtures.plugins
    memories = MaxFixtures.memories
    collections = MaxFixtures.collections
    apiClient = MaxAPIClient(baseURL: URL(string: "https://max.example.com")!)
  }

  var palette: MaxPalette {
    MaxPalette.palette(for: theme, colorScheme: theme.preferredColorScheme ?? .dark)
  }

  var activeMedia: MediaItem? {
    guard let selectedMediaID else { return nil }
    return media.first(where: { $0.id == selectedMediaID })
  }

  var activeThread: ChatThread? {
    guard let selectedThreadID else { return nil }
    return threads.first(where: { $0.id == selectedThreadID })
  }

  var activeWorkspace: Workspace? {
    guard let selectedWorkspaceID else { return nil }
    return workspaces.first(where: { $0.id == selectedWorkspaceID })
  }

  func copy(_ key: String) -> String {
    MaxCopy.text(key, language: language)
  }

  func persistPreferences() {
    UserDefaults.standard.set(theme.rawValue, forKey: "max.macos.theme")
    UserDefaults.standard.set(language.rawValue, forKey: "max.macos.language")
  }

  func signIn(email: String, password: String) {
    guard !email.isEmpty, !password.isEmpty else {
      lastError = "Enter an email and password."
      return
    }
    lastError = nil
    isAuthenticated = true
    UserDefaults.standard.set(true, forKey: "max.macos.authenticated")
  }

  func enterDemo() {
    lastError = nil
    isAuthenticated = true
    UserDefaults.standard.set(true, forKey: "max.macos.authenticated")
  }

  func signOut() {
    isAuthenticated = false
    selectedDestination = .vault
    selectedMediaID = nil
    isMediaPresented = false
    UserDefaults.standard.set(false, forKey: "max.macos.authenticated")
  }

  func open(_ item: MediaItem) {
    selectedMediaID = item.id
    isMediaPresented = true
  }

  func toggleSaved(_ itemID: String) {
    guard let index = media.firstIndex(where: { $0.id == itemID }) else { return }
    media[index].isSaved.toggle()
  }

  func toggleOffline(_ itemID: String) {
    guard let index = media.firstIndex(where: { $0.id == itemID }) else { return }
    media[index].isOffline.toggle()
  }

  func setRatings(itemID: String, own: Int?, partner: Int?) {
    guard let index = media.firstIndex(where: { $0.id == itemID }) else { return }
    media[index].ownRating = own
    media[index].partnerRating = partner
  }

  func moveToTrash(_ itemID: String) {
    guard let index = media.firstIndex(where: { $0.id == itemID }) else { return }
    media[index].isTrashed = true
    isMediaPresented = false
  }

  func restoreFromTrash(_ itemID: String) {
    guard let index = media.firstIndex(where: { $0.id == itemID }) else { return }
    media[index].isTrashed = false
  }

  func beginDemoUpload() {
    let transfer = TransferRecord(
      id: UUID(),
      title: "Tahoe Evening.mov",
      progress: 0.42,
      state: .uploading
    )
    transfers.insert(transfer, at: 0)
    isUploadPresented = false
    isTransfersPresented = true
  }

  func completeTransfers() {
    for index in transfers.indices {
      transfers[index].progress = 1
      transfers[index].state = .complete
    }
  }

  func sendMessage(_ body: String) {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let threadID = selectedThreadID,
          let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
    threads[index].messages.append(
      ChatMessage(
        id: UUID().uuidString,
        sender: profile.displayName,
        body: trimmed,
        sentAt: Date(),
        isMine: true,
        reaction: nil,
        isEdited: false,
        mediaID: nil
      )
    )
    threads[index].subtitle = trimmed
  }

  func togglePlugin(_ pluginID: String) {
    guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
    plugins[index].isEnabled.toggle()
  }

  func saveProfile(_ updated: MaxProfile) {
    profile = updated
    isProfileEditorPresented = false
  }
}

