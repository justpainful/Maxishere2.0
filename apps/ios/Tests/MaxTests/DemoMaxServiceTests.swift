import XCTest
@testable import Max

@MainActor
final class DemoMaxServiceTests: XCTestCase {
  func testDemoServiceRequiresLocalAuthenticationAndNeverReturnsLiveMediaOrigins() async throws {
    let service = DemoMaxService()

    do {
      _ = try await service.home()
      XCTFail("Demo data must still require its isolated local session")
    } catch DemoServiceError.notAuthenticated {
      // Expected: this check is entirely local and creates no URLSession.
    } catch {
      XCTFail("Unexpected pre-authentication error: \(error)")
    }

    let liveLookingURL = try XCTUnwrap(URL(string: "https://example.com/private"))
    let configuration = try MaxConfiguration(baseURL: liveLookingURL)
    await service.updateConfiguration(configuration)
    _ = try await service.login(email: "demo@max.local", password: "demo")

    let home = try await service.home()
    let media = try await service.media(query: MediaQuery())
    let library = try await service.library()
    let profile = try await service.profile()
    XCTAssertFalse(home.browse.isEmpty)
    for item in home.browse + home.shuffle + media.items + library.saved + profile.favorites {
      assertLocalFixtureURLs(in: item)
    }
    for url in [profile.user.avatarUrl, profile.user.coverUrl].compactMap({ $0 }) {
      assertLocalFixtureURL(url)
    }
  }

  func testDemoResetRestoresProfileRatingsMessagesAndAuthenticationBoundary() async throws {
    let service = DemoMaxService()
    _ = try await service.login(email: "demo@max.local", password: "demo")

    _ = try await service.updateProfile(
      ProfileUpdateRequest(
        displayName: "Changed Demo Name",
        username: "changed_demo",
        bio: "Changed locally"
      )
    )
    _ = try await service.setRating(
      fileID: "demo-media-aurora",
      targetUserID: "demo-primary",
      score: 8
    )
    _ = try await service.sendMessage(
      chatID: "demo-chat-bot",
      caption: "A local mutation",
      mediaFileIDs: [],
      replyToID: nil
    )

    let changedProfile = try await service.profile()
    let changedRatings = try await service.ratings(fileID: "demo-media-aurora")
    let changedMessages = try await service.messages(
      chatID: "demo-chat-bot",
      limit: 100,
      before: nil
    )
    XCTAssertEqual(changedProfile.user.displayName, "Changed Demo Name")
    XCTAssertEqual(
      changedRatings.subjects.first(where: { $0.user.id == "demo-primary" })?.score,
      8
    )
    XCTAssertEqual(changedMessages.messages.count, 3)

    await service.reset()
    do {
      _ = try await service.profile()
      XCTFail("Reset must restore the unauthenticated boundary")
    } catch DemoServiceError.notAuthenticated {
      // Expected.
    } catch {
      XCTFail("Unexpected post-reset error: \(error)")
    }

    _ = try await service.login(email: "demo@max.local", password: "demo")
    let resetProfile = try await service.profile()
    let resetRatings = try await service.ratings(fileID: "demo-media-aurora")
    let resetMessages = try await service.messages(
      chatID: "demo-chat-bot",
      limit: 100,
      before: nil
    )
    XCTAssertEqual(resetProfile.user.displayName, "Max Explorer")
    XCTAssertEqual(
      resetRatings.subjects.first(where: { $0.user.id == "demo-primary" })?.score,
      7
    )
    XCTAssertEqual(resetMessages.messages.map(\.id), ["demo-message-welcome"])
  }

  func testDemoBotStateMachineIsDeterministicForTextAndVideo() async throws {
    let first = DemoMaxService()
    let second = DemoMaxService()

    let firstTranscript = try await transcript(from: first)
    let secondTranscript = try await transcript(from: second)

    XCTAssertEqual(firstTranscript, secondTranscript)
    XCTAssertEqual(
      firstTranscript.map(\.id),
      [
        "demo-message-welcome",
        "demo-message-101",
        "demo-bot-message-102",
        "demo-message-103",
        "demo-bot-message-104",
        "demo-bot-message-105",
      ]
    )

    let botMessages = firstTranscript.filter { $0.senderId == "demo-bot" }
    XCTAssertTrue(botMessages.contains {
      $0.content?.contains("Demo reply received") == true
    })
    XCTAssertTrue(botMessages.contains {
      $0.content?.localizedCaseInsensitiveContains("video received") == true
    })
    XCTAssertTrue(botMessages.contains {
      $0.content?.localizedCaseInsensitiveContains("opened") == true
        || $0.content?.localizedCaseInsensitiveContains("saved") == true
    })
    XCTAssertTrue(botMessages.allSatisfy {
      $0.mediaUrl == nil && $0.mediaReferences == nil
    })
  }

  private func transcript(from service: DemoMaxService) async throws -> [ChatMessage] {
    _ = try await service.login(email: "demo@max.local", password: "demo")
    _ = try await service.sendMessage(
      chatID: "demo-chat-bot",
      caption: "Hello locally",
      mediaFileIDs: [],
      replyToID: nil
    )
    _ = try await service.sendMessage(
      chatID: "demo-chat-bot",
      caption: "",
      mediaFileIDs: ["demo-media-aurora"],
      replyToID: nil
    )
    return try await service.messages(
      chatID: "demo-chat-bot",
      limit: 100,
      before: nil
    ).messages
  }

  private func assertLocalFixtureURLs(
    in item: MaxMediaItem,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let urls = [
      item.mediaUrl,
      item.thumbnailUrl,
      item.videoThumbnailUrl,
      item.uploader.avatarUrl,
    ].compactMap { $0 }
    XCTAssertFalse(urls.isEmpty, "Demo media must have a local presentation URL")
    for url in urls {
      assertLocalFixtureURL(url, file: file, line: line)
    }
  }

  private func assertLocalFixtureURL(
    _ url: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      url.isFileURL || (url.scheme == "max-demo" && url.host == "fixture"),
      "Demo data escaped its bundled/generated origin: \(url.absoluteString)",
      file: file,
      line: line
    )
  }
}
