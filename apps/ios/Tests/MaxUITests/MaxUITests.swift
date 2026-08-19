import XCTest

final class MaxUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
    app = XCUIApplication()

    let isWalkthrough = name.contains("testDemoWalkthrough")
    app.launchArguments += [
      "-MaxUITestMode",
      "-MAX_DEMO_MODE", "1",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
    ]
    app.launchEnvironment["MAX_DEMO_MODE"] = "1"
    app.launchEnvironment["MAX_UI_TESTING"] = "1"
    app.launchEnvironment["MAX_UI_TEST_DOUBLE_LOCK_BYPASS"] = "1"
    app.launchEnvironment["MAX_UI_TEST_THEME"] = "max"
    app.launchEnvironment["MAX_UI_TEST_LANGUAGE"] = "en"
    app.launchEnvironment["MAX_UI_TEST_AUTHENTICATED"] = isWalkthrough ? "0" : "1"
    if isWalkthrough {
      app.launchEnvironment["MAX_UI_TEST_RESET_DEMO"] = "1"
    }
    app.launch()

    let initialSurface = isWalkthrough ? "ui_login_screen" : "ui_authenticated_shell"
    XCTAssertTrue(
      element(initialSurface).waitForExistence(timeout: 15),
      "The deterministic Demo surface \(initialSurface) did not appear"
    )
    if !isWalkthrough {
      dismissReleaseAnnouncementIfNeeded()
    }
  }

  override func tearDownWithError() throws {
    app = nil
    try super.tearDownWithError()
  }

  // This is the release-recording path. Keep the numbered markers aligned with the
  // 1...41 walkthrough in Max IOS26 Goal.txt so xcresult remains useful evidence.
  func testDemoWalkthrough() throws {
    markStep(1, "Launch")

    // 2. Login.
    element("ui_entry_continue").tap()
    assertScreen(identifier: "ui_login_credentials_sheet")
    let email = element("ui_login_email")
    // iOS 26.5 exposes the system reveal-password button with the secure
    // field's identifier too, so query the editable field by element type.
    let password = app.secureTextFields["ui_login_password"]
    email.tap()
    email.typeText("demo@max.local")
    password.tap()
    password.typeText("demo")
    element("ui_login_submit").tap()
    assertScreen(identifier: "ui_authenticated_shell", timeout: 15)
    dismissReleaseAnnouncementIfNeeded()
    markStep(2, "Login")
    captureCheckpoint("01-login")

    // 3. Change language, then return to English for deterministic action labels.
    selectTab(.profile)
    openSettingsFromProfile()
    chooseLanguage("ar")
    captureCheckpoint("01b-language-arabic")
    chooseLanguage("en")
    markStep(3, "Change language")
    navigateBack()

    // 4...7. Vault, search, filter, and open a video.
    selectTab(.vault)
    markStep(4, "Open Vault")

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5), "Vault search field is missing")
    search.tap()
    search.typeText("Aurora")
    let aurora = scrollToVisible("ui_vault_media_demo-media-aurora", direction: .up)
    XCTAssertTrue(aurora.exists, "Vault search did not reveal the deterministic video")
    markStep(5, "Search")

    element("ui_vault_filters").tap()
    require("ui_vault_filter_video").tap()
    XCTAssertTrue(scrollToVisible("ui_vault_media_demo-media-aurora", direction: .up).exists)
    markStep(6, "Filter")
    captureCheckpoint("02-vault-search-filter")

    element("ui_vault_media_demo-media-aurora").tap()
    assertScreen(identifier: "ui_player_screen", timeout: 10)
    XCTAssertTrue(element("ui_player_demo_surface").waitForExistence(timeout: 5))
    markStep(7, "Open video")

    // 8. Seek.
    let seek = app.sliders["ui_player_seek"]
    XCTAssertTrue(seek.waitForExistence(timeout: 5), "Player seek control is missing")
    seek.adjust(toNormalizedSliderPosition: 0.42)
    markStep(8, "Seek")
    captureCheckpoint("03-player-seek")

    // 9. End in a saved state. Aurora starts saved, so exercise unsave then save.
    let favorite = app.buttons["ui_player_favorite"]
    XCTAssertTrue(favorite.waitForExistence(timeout: 5))
    favorite.tap()
    waitForLabel(of: favorite, equalTo: "Save")
    favorite.tap()
    waitForLabel(of: favorite, equalTo: "Unsave")
    markStep(9, "Save")

    // 10...12. Own 8, other 6, clear 6 by selecting it again, then set 7.
    require("ui_player_rating_demo-primary").tap()
    assertScreen(identifier: "ui_rating_sheet", timeout: 10)
    let ownRating = require("ui_rating_rail_demo-primary")
    let otherRating = require("ui_rating_rail_demo-second")

    tapRating(8, on: ownRating)
    waitForValue(of: ownRating, containing: "8")
    tapRating(5, on: otherRating)
    waitForValue(of: otherRating, containing: "5")
    tapRating(6, on: otherRating)
    waitForValue(of: otherRating, containing: "6")
    markStep(10, "Set both ratings")
    captureCheckpoint("04-dual-ratings")

    tapRating(6, on: otherRating)
    waitForValue(of: otherRating, containing: "—")
    markStep(11, "Clear one rating by selecting the same value")

    tapRating(7, on: otherRating)
    waitForValue(of: otherRating, containing: "7")
    markStep(12, "Set the cleared rating again")
    element("ui_rating_close").tap()
    assertScreen(identifier: "ui_player_screen")

    // 13. Send the currently open video to the local deterministic participant.
    element("ui_player_send_to_chat").tap()
    assertScreen(identifier: "ui_player_send_chat_sheet")
    require("ui_player_send_chat_demo-chat-bot").tap()
    waitForNonExistence(element("ui_player_send_chat_sheet"), timeout: 10)
    markStep(13, "Send video to chat")
    element("ui_player_close").tap()
    assertScreen(identifier: "ui_vault_screen")

    // 14...18. Deterministic bot, compose, edit, reply, and delete.
    selectTab(.chats)
    element("ui_chat_thread_demo-chat-bot").tap()
    assertScreen(identifier: "ui_chat_detail", timeout: 10)
    let videoAcknowledgement = text(containing: "Video received")
    XCTAssertTrue(
      videoAcknowledgement.waitForExistence(timeout: 10),
      "The local video acknowledgement did not arrive"
    )
    XCTAssertTrue(
      text(containing: "opened the Demo copy").waitForExistence(timeout: 10),
      "The local video opened-and-saved acknowledgement did not arrive"
    )
    markStep(14, "Receive demo reply")
    captureCheckpoint("05-chat-video-reply")

    let composer = require("ui_chat_composer")
    composer.tap()
    composer.typeText("Hello from the deterministic walkthrough.")
    element("ui_chat_send").tap()
    let sentText = app.staticTexts["Hello from the deterministic walkthrough."]
    let textReply = text(containing: "Demo reply received")
    XCTAssertTrue(sentText.waitForExistence(timeout: 10))
    XCTAssertTrue(textReply.waitForExistence(timeout: 10))
    markStep(15, "Type message")

    let sentMessageRow = require("ui_chat_message_demo-message-104")
    openMessageAction(on: sentMessageRow, label: "Edit")
    assertScreen(identifier: "ui_chat_edit_sheet")
    replaceText(
      in: require("ui_chat_edit_editor"),
      with: "Edited during the deterministic walkthrough."
    )
    element("ui_chat_edit_save").tap()
    waitForNonExistence(element("ui_chat_edit_sheet"), timeout: 10)
    XCTAssertTrue(
      app.staticTexts["Edited during the deterministic walkthrough."].waitForExistence(timeout: 5)
    )
    markStep(16, "Edit")

    let textReplyRow = require("ui_chat_message_demo-bot-message-105")
    openMessageAction(on: textReplyRow, label: "Reply")
    XCTAssertTrue(element("ui_chat_reply_preview").waitForExistence(timeout: 5))
    composer.tap()
    composer.typeText("Replying locally.")
    element("ui_chat_send").tap()
    XCTAssertTrue(app.staticTexts["Replying locally."].waitForExistence(timeout: 10))
    markStep(17, "Reply")

    openMessageAction(on: sentMessageRow, label: "Delete")
    XCTAssertTrue(app.staticTexts["Delete Message?"].waitForExistence(timeout: 5))
    let destructiveDelete = app.buttons["Delete"].firstMatch
    XCTAssertTrue(destructiveDelete.waitForExistence(timeout: 5))
    destructiveDelete.tap()
    XCTAssertTrue(app.staticTexts["This message was deleted"].waitForExistence(timeout: 5))
    markStep(18, "Delete")

    // Prove the chat attachment opens and stays saved before downloading it.
    let sentVideo = scrollToVisible("ui_chat_media_open_demo-media-aurora", direction: .down)
    sentVideo.tap()
    assertScreen(identifier: "ui_player_screen")
    element("ui_player_close").tap()
    assertScreen(identifier: "ui_chat_detail")

    let chatSave = scrollToVisible("ui_media_save_demo-media-aurora", direction: .down)
    chatSave.tap()
    waitForLabel(of: chatSave, equalTo: "Save")
    chatSave.tap()
    waitForLabel(of: chatSave, equalTo: "Unsave")

    // 19. Persist the sent video into the isolated Demo download namespace.
    let download = scrollToVisible("ui_media_download_demo-media-aurora", direction: .down)
    download.tap()
    XCTAssertTrue(
      element("ui_media_offline_demo-media-aurora").waitForExistence(timeout: 10),
      "The Demo download did not become offline-ready"
    )
    markStep(19, "Download media")

    // 20...23. Library destinations and offline playback.
    selectTab(.library)
    markStep(20, "Open Library")

    element("ui_library_saved").tap()
    assertScreen(identifier: "ui_saved_screen")
    markStep(21, "Open Saved")
    navigateBack()

    element("ui_library_ratings").tap()
    assertScreen(identifier: "ui_ratings_screen")
    let averageLabels = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] 'average'")
    )
    XCTAssertFalse(
      averageLabels.firstMatch.exists,
      "The product must not display an averaged rating"
    )
    markStep(22, "Open Ratings")
    captureCheckpoint("06-library-ratings")
    navigateBack()

    element("ui_library_offline").tap()
    assertScreen(identifier: "ui_offline_screen")
    markStep(23, "Open Offline")
    element("ui_offline_open_demo-media-aurora").tap()
    assertScreen(identifier: "ui_player_screen")
    XCTAssertTrue(element("ui_player_demo_surface").waitForExistence(timeout: 5))
    element("ui_player_close").tap()
    assertScreen(identifier: "ui_offline_screen")
    navigateBack()

    // 24...28. Memories stays hidden for the non-allowlisted Demo account.
    XCTAssertFalse(element("ui_library_memories").exists)
    markStep(24, "Memories hidden by feature flag")
    markStep(25, "Memories remains unavailable")
    markStep(26, "Memories remains unavailable")
    markStep(27, "Memories remains unavailable")
    markStep(28, "Memories remains unavailable")

    // 29...30. Shared files and spaces.
    selectTab(.shared)
    markStep(29, "Open Shared")
    element("ui_shared_segment_spaces").tap()
    XCTAssertTrue(element("ui_shared_space_demo-space-studio").waitForExistence(timeout: 5))
    element("ui_shared_segment_files").tap()
    XCTAssertTrue(element("ui_shared_file_demo-media-blue-hour").waitForExistence(timeout: 5))
    markStep(30, "Switch Files and Spaces")
    captureCheckpoint("09-shared-files-spaces")

    // 31...37. Profile editor uses only bundled Demo assets.
    selectTab(.profile)
    markStep(31, "Open Profile")
    element("ui_profile_edit").tap()
    assertScreen(identifier: "ui_profile_edit_screen")

    scrollToVisible("ui_profile_edit_avatar", direction: .up).tap()
    require("ui_profile_demo_avatar_0").tap()
    assertScreen(identifier: "ui_profile_crop_canvas")
    element("ui_profile_crop_use").tap()
    assertScreen(identifier: "ui_profile_edit_screen")
    markStep(32, "Edit avatar")

    scrollToVisible("ui_profile_edit_header", direction: .up).tap()
    require("ui_profile_demo_cover_0").tap()
    assertScreen(identifier: "ui_profile_crop_canvas")
    element("ui_profile_crop_use").tap()
    assertScreen(identifier: "ui_profile_edit_screen")
    markStep(33, "Edit header")

    replaceText(
      in: scrollToVisible("ui_profile_edit_name", direction: .up),
      with: "Max Demo Explorer"
    )
    markStep(34, "Edit name")
    replaceText(
      in: scrollToVisible("ui_profile_edit_username", direction: .up),
      with: "max_demo_explorer"
    )
    markStep(35, "Edit username")
    replaceText(
      in: scrollToVisible("ui_profile_edit_bio", direction: .up),
      with: "A completely local and repeatable Max walkthrough."
    )
    markStep(36, "Edit bio")

    scrollToVisible("ui_profile_edit_save", direction: .up).tap()
    assertScreen(identifier: "ui_profile_screen", timeout: 10)
    XCTAssertTrue(app.staticTexts["Max Demo Explorer"].waitForExistence(timeout: 5))
    markStep(37, "Save")
    captureCheckpoint("10-profile-edited")

    // 38...41. Settings, all three themes, both languages, and Sign Out reachability.
    openSettingsFromProfile()
    markStep(38, "Open Settings")

    for theme in ["light", "dark", "max", "clouds"] {
      let option = scrollToVisible("ui_theme_\(theme)", direction: .up)
      option.tap()
      XCTAssertTrue(option.isSelected, "Theme \(theme) was not selected")
      captureCheckpoint("11-theme-\(theme)")
    }
    markStep(39, "Switch Light, Dark, and Max")

    chooseLanguage("ar")
    captureCheckpoint("11-settings-arabic")
    chooseLanguage("en")
    markStep(40, "Switch English and Arabic")

    let signOut = scrollToVisible("ui_profile_signout", direction: .up)
    XCTAssertTrue(signOut.isHittable, "Sign Out is not reachable")
    markStep(41, "Reach Sign Out")
    captureCheckpoint("12-settings-sign-out")
  }

  func testFiveTabShellAndSettingsNavigation() throws {
    for tab in RootTab.allCases {
      selectTab(tab)
    }
    openSettingsFromProfile()
    assertScreen(identifier: "ui_settings_screen")
    XCTAssertTrue(element("ui_theme_max").waitForExistence(timeout: 5))
    XCTAssertFalse(element("ui_theme_system").exists)
    captureCheckpoint("five-tab-shell-settings")
  }

  func testContextualVaultUploadSheet() throws {
    selectTab(.vault)
    element("ui_vault_upload").tap()
    assertScreen(identifier: "ui_upload_sheet")
    captureCheckpoint("vault-upload-sheet")
    app.buttons["Close"].tap()
    assertScreen(identifier: "ui_vault_screen")
  }

  func testCoreShellAccessibility() throws {
    for tab in RootTab.allCases {
      selectTab(tab)
      try app.performAccessibilityAudit(
        for: [.hitRegion, .sufficientElementDescription]
      )
    }
  }

  func testRootOccupiesFullViewport() throws {
    let viewport = element("ui_authenticated_shell")
    XCTAssertTrue(viewport.waitForExistence(timeout: 5))
    let screenshot = app.screenshot()
    let screenSize = screenshot.image.size

    XCTAssertGreaterThanOrEqual(viewport.frame.width / screenSize.width, 0.98)
    XCTAssertGreaterThanOrEqual(viewport.frame.height / screenSize.height, 0.98)
    XCTAssertLessThanOrEqual(abs(viewport.frame.minX), 2)
    XCTAssertLessThanOrEqual(abs(viewport.frame.minY), 2)
    captureCheckpoint(screenshot, named: "full-viewport-max")
  }

  func testThemePickerOffersAllSupportedAppearances() throws {
    selectTab(.profile)
    openSettingsFromProfile()
    for theme in ["light", "dark", "max", "spectrum", "clouds"] {
      let option = scrollToVisible("ui_theme_\(theme)", direction: .up)
      option.tap()
      XCTAssertTrue(option.isSelected)
    }
    XCTAssertFalse(element("ui_theme_system").exists)
  }

  func testAuthenticationSheetAcrossAllThemes() throws {
    for theme in ["light", "dark", "max", "spectrum", "clouds"] {
      relaunch(theme: theme, authenticated: false)
      assertScreen(identifier: "ui_login_screen")
      XCTAssertTrue(element("ui_entry_continue").waitForExistence(timeout: 5))
      element("ui_entry_continue").tap()
      assertScreen(identifier: "ui_login_credentials_sheet")
      XCTAssertTrue(element("ui_login_email").waitForExistence(timeout: 5))
      XCTAssertTrue(element("ui_login_password").exists)
      captureCheckpoint("theme-\(theme)-authentication")
    }
  }

  func testArabicRightToLeftSettings() throws {
    relaunch(theme: "max", language: "ar")
    selectTab(.profile)
    openSettingsFromProfile()
    assertScreen(identifier: "ui_settings_screen")
    captureCheckpoint("theme-max-arabic-rtl")
  }

  func testAccessibilityExtraExtraExtraLargeSettings() throws {
    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    ]
    app.launchEnvironment["MAX_UI_TEST_INITIAL_TAB"] = "profile"
    app.launch()
    XCTAssertTrue(element("ui_authenticated_shell").waitForExistence(timeout: 15))
    dismissReleaseAnnouncementIfNeeded()
    assertScreen(identifier: "ui_profile_screen")
    openSettingsFromProfile()
    XCTAssertTrue(element("ui_theme_max").waitForExistence(timeout: 5))
    captureCheckpoint("theme-max-accessibility-xxxl")
    try app.performAccessibilityAudit(
      for: [.hitRegion, .sufficientElementDescription]
    )
  }

  private func assertScreen(
    identifier: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      element(identifier).waitForExistence(timeout: timeout),
      "Expected screen \(identifier)",
      file: file,
      line: line
    )
  }

  private func selectTab(_ tab: RootTab) {
    let button = app.buttons[tab.identifier]
    XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(tab.rawValue) tab")
    button.tap()
    assertScreen(identifier: tab.screenIdentifier)
  }

  private func openSettingsFromProfile() {
    scrollToVisible("ui_profile_settings", direction: .up)
    let settings = element("ui_profile_settings")
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    assertScreen(identifier: "ui_settings_screen")
  }

  private func dismissReleaseAnnouncementIfNeeded() {
    // Announcement is suppressed via MAX_UI_TESTING env var; this is a no-op safety net
    for label in ["Got it", "Start now", "Open now", "فهمت", "ابدأ الآن", "افتحها الآن"] {
      let cta = app.buttons[label]
      if cta.exists && cta.isHittable {
        cta.tap()
        return
      }
    }
  }

  private func chooseLanguage(_ language: String) {
    let picker = scrollToVisible("ui_settings_language", direction: .up)
    picker.tap()
    let option = require("ui_language_\(language)", timeout: 5)
    option.tap()
    assertScreen(identifier: "ui_settings_screen")
    let settingsTitle = language == "ar" ? "الإعدادات" : "Settings"
    XCTAssertTrue(
      app.navigationBars[settingsTitle].waitForExistence(timeout: 5),
      "Settings did not apply language \(language)"
    )
  }

  private func tapRating(_ score: Int, on rail: XCUIElement) {
    XCTAssertTrue((1...10).contains(score))
    let x = (CGFloat(score) - 0.5) / 10
    rail.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
  }

  private func waitForValue(
    of element: XCUIElement,
    containing value: String,
    timeout: TimeInterval = 8
  ) {
    let predicate = NSPredicate(format: "value CONTAINS %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
  }

  private func waitForLabel(
    of element: XCUIElement,
    equalTo label: String,
    timeout: TimeInterval = 8
  ) {
    let predicate = NSPredicate(format: "label == %@", label)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
  }

  private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
  }

  private func openMessageAction(on messageContent: XCUIElement, label: String) {
    for _ in 0..<8 where !messageContent.isHittable {
      app.swipeDown()
    }
    XCTAssertTrue(messageContent.waitForExistence(timeout: 5))
    XCTAssertTrue(messageContent.isHittable)
    messageContent.press(forDuration: 0.9)
    let action = app.buttons[label].firstMatch
    XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing \(label) message action")
    action.tap()
  }

  private func replaceText(in field: XCUIElement, with replacement: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.press(forDuration: 0.9)
    let selectAll = app.buttons["Select All"].firstMatch
    XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "Select All edit action is missing")
    selectAll.tap()
    field.typeText(replacement)
  }

  private func navigateBack() {
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5), "Navigation back button is missing")
    back.tap()
  }

  @discardableResult
  private func scrollToVisible(
    _ identifier: String,
    direction: ScrollDirection,
    attempts: Int = 8
  ) -> XCUIElement {
    let target = element(identifier)
    for _ in 0..<attempts where !target.isHittable {
      switch direction {
      case .up: app.swipeUp()
      case .down: app.swipeDown()
      }
    }
    XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing \(identifier)")
    XCTAssertTrue(target.isHittable, "\(identifier) exists but is not reachable")
    return target
  }

  private func relaunch(
    theme: String,
    language: String = "en",
    authenticated: Bool = true
  ) {
    app.terminate()
    app.launchEnvironment["MAX_UI_TEST_THEME"] = theme
    app.launchEnvironment["MAX_UI_TEST_LANGUAGE"] = language
    app.launchEnvironment["MAX_UI_TEST_AUTHENTICATED"] = authenticated ? "1" : "0"
    app.launch()
    let surface = authenticated ? "ui_authenticated_shell" : "ui_login_screen"
    assertScreen(identifier: surface, timeout: 15)
    if authenticated {
      dismissReleaseAnnouncementIfNeeded()
    }
  }

  private func markStep(_ number: Int, _ title: String) {
    let attachment = XCTAttachment(string: "Step \(number) completed: \(title)")
    attachment.name = String(format: "walkthrough-step-%02d-%@", number, title)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func captureCheckpoint(_ name: String) {
    captureCheckpoint(app.screenshot(), named: name)
  }

  private func captureCheckpoint(_ screenshot: XCUIScreenshot, named name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func require(
    _ identifier: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    let result = element(identifier)
    XCTAssertTrue(
      result.waitForExistence(timeout: timeout),
      "Missing \(identifier)",
      file: file,
      line: line
    )
    return result
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func text(containing fragment: String) -> XCUIElement {
    app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", fragment)
    ).firstMatch
  }
}

private enum RootTab: String, CaseIterable {
  case vault
  case library
  case shared
  case chats
  case profile

  var identifier: String { "ui_tab_\(rawValue)" }

  var screenIdentifier: String {
    switch self {
    case .vault: "ui_vault_screen"
    case .library: "ui_library_screen"
    case .shared: "ui_shared_screen"
    case .chats: "ui_chats_screen"
    case .profile: "ui_profile_screen"
    }
  }
}

private enum ScrollDirection {
  case up
  case down
}
