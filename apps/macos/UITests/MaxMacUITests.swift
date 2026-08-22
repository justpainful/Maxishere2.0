import XCTest

final class MaxMacUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
    app = XCUIApplication()
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
    try super.tearDownWithError()
  }

  func test01WideFeatureScreenshotGallery() throws {
    launch(authenticated: false, width: 1000, height: 720)
    try capture("01-authentication-wide", fullScreen: true)

    let continueButton = app.buttons["Continue to Max"]
    XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
    continueButton.click()
    XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 8))
    try capture("02-authentication-credentials")
    app.terminate()

    launch(authenticated: true, width: 1000, height: 720)
    waitFor("mac_vault_screen")
    try capture("03-vault-wide", fullScreen: true)

    require("mac_media_demo-media-aurora").click()
    waitFor("mac_media_detail")
    try capture("04-player-native-liquid-glass")

    let ratingButton = app.buttons.matching(identifier: "mac_player_rate").firstMatch
    XCTAssertTrue(ratingButton.waitForExistence(timeout: 8), "Missing rating button")
    ratingButton.click()
    waitFor("mac_rating_editor")
    try capture("05-dual-rating-editor")
    let saveRatingButton = app.buttons["Save"].firstMatch
    XCTAssertTrue(saveRatingButton.waitForExistence(timeout: 8), "Missing Save rating button")
    saveRatingButton.click()
    waitFor("mac_media_detail")
    app.typeKey(.escape, modifierFlags: [])
    waitFor("mac_vault_screen")

    app.buttons["Upload"].firstMatch.click()
    waitFor("mac_upload_sheet")
    try capture("06-upload-sheet")
    require("mac_upload_start").click()
    waitFor("mac_transfers_sheet")
    try capture("07-transfer-manager")
    app.typeKey(.escape, modifierFlags: [])

    open(.library, screen: "mac_library_screen")
    try capture("08-library-overview")
    for section in ["saved", "ratings", "offline", "collections", "trash"] {
      require("mac_library_\(section)").click()
      try capture("09-library-\(section)")
    }

    open(.shared, screen: "mac_shared_screen")
    try capture("10-shared-files")
    app.buttons["Spaces"].click()
    waitFor("mac_shared_spaces")
    try capture("11-shared-spaces")
    require("mac_workspace_demo-space-studio").click()
    waitFor("mac_workspace_detail")
    try capture("12-workspace-detail")
    app.typeKey(.escape, modifierFlags: [])

    open(.chats, screen: "mac_chats_screen")
    waitFor("mac_chat_detail")
    try capture("13-chats-conversation")
    require("mac_chat_details").click()
    waitFor("mac_chat_details_panel")
    try capture("14-chat-details-panel")
    require("mac_chat_new").click()
    waitFor("mac_new_conversation")
    try capture("15-new-conversation")
    app.typeKey(.escape, modifierFlags: [])

    open(.profile, screen: "mac_profile_screen")
    try capture("16-profile")
    require("mac_profile_edit").click()
    waitFor("mac_profile_editor")
    try capture("17-profile-editor")
    app.typeKey(.escape, modifierFlags: [])

    open(.memories, screen: "mac_memories_screen")
    try capture("18-memories")
    open(.plugins, screen: "mac_plugins_screen")
    try capture("19-plugin-store")

    require("mac_toolbar_search").click()
    waitFor("mac_command_palette")
    try capture("20-command-palette")
  }

  func test02ThemeRTLAndSettingsGallery() throws {
    launch(authenticated: true, width: 1000, height: 720)
    open(.profile, screen: "mac_profile_screen")
    require("mac_profile_settings").click()
    waitFor("mac_settings_screen", timeout: 15)
    try capture("21-settings-max", fullScreen: true)

    for theme in ["light", "dark", "spectrum", "clouds", "council", "max"] {
      require("mac_theme_\(theme)").click()
      try capture("22-theme-\(theme)", fullScreen: true)
    }

    app.terminate()
    _ = app.wait(for: .notRunning, timeout: 5)
    launch(authenticated: true, width: 1000, height: 720, language: "ar")
    app.typeKey(",", modifierFlags: .command)
    waitFor("mac_settings_screen", timeout: 15)
    XCTAssertTrue(app.staticTexts["المظهر"].waitForExistence(timeout: 8), "Arabic interface did not appear")
    try capture("23-settings-arabic-rtl", fullScreen: true)
  }

  func test03CompactWindowAndDesktopCaptureGallery() throws {
    launch(authenticated: true, width: 900, height: 650)
    waitFor("mac_vault_screen")
    try capture("24-vault-compact", fullScreen: true)
    open(.library, screen: "mac_library_screen")
    try capture("25-library-compact")
    open(.chats, screen: "mac_chats_screen")
    try capture("26-chats-compact")
    open(.profile, screen: "mac_profile_screen")
    try capture("27-profile-compact")
  }

  private func launch(authenticated: Bool, width: Int, height: Int, language: String = "en") {
    app.launchArguments = [
      "-MaxMacUITestMode",
      authenticated ? "-MaxMacUITestAuthenticated" : "-MaxMacUITestLoggedOut",
    ]
    app.launchEnvironment["MAX_MAC_UI_TESTING"] = "1"
    app.launchEnvironment["MAX_MAC_UI_TEST_AUTHENTICATED"] = authenticated ? "1" : "0"
    app.launchEnvironment["MAX_MAC_UI_TEST_THEME"] = "max"
    app.launchEnvironment["MAX_MAC_UI_TEST_LANGUAGE"] = language
    app.launchEnvironment["MAX_MAC_WINDOW_WIDTH"] = "\(width)"
    app.launchEnvironment["MAX_MAC_WINDOW_HEIGHT"] = "\(height)"
    app.launch()
    if !app.windows.firstMatch.waitForExistence(timeout: 5) {
      app.activate()
      app.typeKey("n", modifierFlags: .command)
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "The Max window did not appear")
    if authenticated {
      waitFor("mac_vault_screen", timeout: 15)
    } else {
      waitFor("mac_authentication", timeout: 15)
    }
  }

  private func open(_ destination: Destination, screen: String) {
    require("mac_sidebar_\(destination.rawValue)").click()
    waitFor(screen)
  }

  private func waitFor(
    _ identifier: String,
    timeout: TimeInterval = 8,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      element(identifier).waitForExistence(timeout: timeout),
      "Missing \(identifier)",
      file: file,
      line: line
    )
  }

  @discardableResult
  private func require(
    _ identifier: String,
    timeout: TimeInterval = 8,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    let result = element(identifier)
    XCTAssertTrue(result.waitForExistence(timeout: timeout), "Missing \(identifier)", file: file, line: line)
    return result
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: identifier)
      .firstMatch
  }

  private func capture(_ name: String, fullScreen: Bool = false) throws {
    let screenshot = fullScreen ? XCUIScreen.main.screenshot() : app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)

    let sourceFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = sourceFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let output = repositoryRoot.appending(path: "artifacts/screenshots", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try screenshot.pngRepresentation.write(to: output.appendingPathComponent("\(name).png"), options: .atomic)
  }
}

private enum Destination: String {
  case vault
  case library
  case shared
  case chats
  case profile
  case memories
  case plugins
}
