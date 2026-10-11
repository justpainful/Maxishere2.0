import XCTest
@testable import Max

final class MaxChatUIAdapterTests: XCTestCase {
  func testFilteringMatchesTitlesAndLastMessages() {
    let threads = [
      makeThread(id: "one", title: "Family", lastMessage: "Dinner tonight"),
      makeThread(id: "two", title: "Owen", lastMessage: "Project Max"),
    ]

    XCTAssertEqual(MaxChatUIAdapter.filteredThreads(threads, query: "family").map(\.id), ["one"])
    XCTAssertEqual(MaxChatUIAdapter.filteredThreads(threads, query: "max").map(\.id), ["two"])
    XCTAssertEqual(MaxChatUIAdapter.filteredThreads(threads, query: "  ").map(\.id), ["one", "two"])
  }

  func testMessageClusteringUsesSenderAndFiveMinuteWindow() {
    let messages = [
      makeMessage(id: "one", senderID: "a", createdAt: "2026-07-16T10:00:00Z"),
      makeMessage(id: "two", senderID: "a", createdAt: "2026-07-16T10:02:00Z"),
      makeMessage(id: "three", senderID: "b", createdAt: "2026-07-16T10:03:00Z"),
      makeMessage(id: "four", senderID: "b", createdAt: "2026-07-16T10:10:00Z"),
    ]

    XCTAssertEqual(MaxChatUIAdapter.clusterPosition(in: messages, at: 0), .first)
    XCTAssertEqual(MaxChatUIAdapter.clusterPosition(in: messages, at: 1), .last)
    XCTAssertEqual(MaxChatUIAdapter.clusterPosition(in: messages, at: 2), .single)
    XCTAssertEqual(MaxChatUIAdapter.clusterPosition(in: messages, at: 3), .single)
  }

  func testMessageCapabilitiesRespectOwnershipAndDeletedState() {
    let incoming = makeMessage(id: "incoming", senderID: "other")
    let outgoing = makeMessage(id: "outgoing", senderID: "me")
    let deleted = makeMessage(id: "deleted", senderID: "me", isDeleted: true)

    let incomingCapabilities = MaxChatUIAdapter.capabilities(
      for: incoming,
      isCurrentUser: false
    )
    XCTAssertTrue(incomingCapabilities.contains(.reply))
    XCTAssertTrue(incomingCapabilities.contains(.copy))
    XCTAssertFalse(incomingCapabilities.contains(.edit))
    XCTAssertFalse(incomingCapabilities.contains(.delete))

    let outgoingCapabilities = MaxChatUIAdapter.capabilities(
      for: outgoing,
      isCurrentUser: true
    )
    XCTAssertTrue(outgoingCapabilities.contains(.edit))
    XCTAssertTrue(outgoingCapabilities.contains(.delete))
    XCTAssertTrue(MaxChatUIAdapter.capabilities(for: deleted, isCurrentUser: true).isEmpty)
  }

  private func makeThread(id: String, title: String, lastMessage: String) -> ChatThread {
    ChatThread(
      id: id,
      title: title,
      isGroup: false,
      ownerId: nil,
      partnerId: nil,
      avatarUrl: nil,
      lastMessage: lastMessage,
      lastMessageAt: nil,
      unreadCount: 0
    )
  }

  private func makeMessage(
    id: String,
    senderID: String,
    createdAt: String = "2026-07-16T10:00:00Z",
    isDeleted: Bool = false
  ) -> ChatMessage {
    ChatMessage(
      id: id,
      dmId: "thread",
      senderId: senderID,
      content: "Hello",
      mediaUrl: nil,
      mediaType: nil,
      dmMediaId: nil,
      mediaName: nil,
      isEdited: false,
      isDeleted: isDeleted,
      isHardDeleted: false,
      readAt: nil,
      replyToId: nil,
      createdAt: createdAt,
      mediaReferences: nil
    )
  }
}
