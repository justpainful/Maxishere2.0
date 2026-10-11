import Foundation

/// Max-owned presentation adapter between the product's chat domain models and SwiftUI.
///
/// Keeping grouping, filtering, permissions, and date parsing here prevents the views from
/// becoming coupled to a hosted chat SDK. `ChatStore` remains the sole data source and Max's
/// mobile API remains the source of truth.
enum MaxChatUIAdapter {
  static func filteredThreads(_ threads: [ChatThread], query: String) -> [ChatThread] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return threads }
    return threads.filter {
      $0.title.localizedCaseInsensitiveContains(normalized)
        || $0.lastMessage.localizedCaseInsensitiveContains(normalized)
    }
  }

  static func clusterPosition(
    in messages: [ChatMessage],
    at index: Int
  ) -> MaxChatMessageClusterPosition {
    guard messages.indices.contains(index) else { return .single }
    let message = messages[index]
    let joinsPrevious = messages.indices.contains(index - 1)
      && belongsToSameCluster(messages[index - 1], message)
    let joinsNext = messages.indices.contains(index + 1)
      && belongsToSameCluster(message, messages[index + 1])

    switch (joinsPrevious, joinsNext) {
    case (false, false): return .single
    case (false, true): return .first
    case (true, true): return .middle
    case (true, false): return .last
    }
  }

  static func startsNewDay(in messages: [ChatMessage], at index: Int) -> Bool {
    guard messages.indices.contains(index) else { return false }
    guard messages.indices.contains(index - 1) else { return true }
    guard let current = date(from: messages[index].createdAt),
          let previous = date(from: messages[index - 1].createdAt) else {
      return false
    }
    return !Calendar.autoupdatingCurrent.isDate(current, inSameDayAs: previous)
  }

  static func dayLabel(for rawValue: String?) -> String? {
    date(from: rawValue)?.formatted(date: .abbreviated, time: .omitted)
  }

  static func messageTime(for rawValue: String?) -> String? {
    date(from: rawValue)?.formatted(date: .omitted, time: .shortened)
  }

  static func threadTime(for rawValue: String?, now: Date = Date()) -> String? {
    guard let date = date(from: rawValue) else { return nil }
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDate(date, inSameDayAs: now) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if let recentBoundary = calendar.date(byAdding: .day, value: -6, to: now),
       date >= recentBoundary {
      return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(date: .numeric, time: .omitted)
  }

  static func capabilities(
    for message: ChatMessage,
    isCurrentUser: Bool
  ) -> MaxChatMessageCapabilities {
    guard !message.isDeleted, !message.isHardDeleted else { return [] }

    var result: MaxChatMessageCapabilities = [.reply, .forward, .pin, .select]
    if let content = message.content,
       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result.insert(.copy)
      if isCurrentUser { result.insert(.edit) }
    }
    if isCurrentUser { result.insert(.delete) }
    return result
  }

  static func isPlainText(_ message: ChatMessage) -> Bool {
    guard !message.isDeleted, !message.isHardDeleted,
          message.forwardedFrom == nil,
          message.replyPreview == nil,
          message.poll == nil,
          message.isViewOnce != true,
          // The server now delivers media as `attachments[]`; a message carrying
          // one is never plain text even when the legacy projection is empty.
          message.attachments?.isEmpty != false,
          message.mediaReferences?.isEmpty != false,
          message.mediaName?.isEmpty != false else {
      return false
    }
    return true
  }

  static func date(from rawValue: String?) -> Date? {
    guard let rawValue else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: rawValue) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: rawValue)
  }

  private static func belongsToSameCluster(
    _ earlier: ChatMessage,
    _ later: ChatMessage
  ) -> Bool {
    guard earlier.senderId == later.senderId,
          !earlier.isDeleted,
          !earlier.isHardDeleted,
          !later.isDeleted,
          !later.isHardDeleted,
          let earlierDate = date(from: earlier.createdAt),
          let laterDate = date(from: later.createdAt) else {
      return false
    }
    return laterDate.timeIntervalSince(earlierDate) >= 0
      && laterDate.timeIntervalSince(earlierDate) <= 5 * 60
  }
}

enum MaxChatMessageClusterPosition: Equatable, Sendable {
  case single
  case first
  case middle
  case last

  var startsCluster: Bool { self == .single || self == .first }
  var endsCluster: Bool { self == .single || self == .last }
}

struct MaxChatMessageCapabilities: OptionSet, Sendable {
  let rawValue: UInt8

  static let reply = Self(rawValue: 1 << 0)
  static let copy = Self(rawValue: 1 << 1)
  static let pin = Self(rawValue: 1 << 2)
  static let forward = Self(rawValue: 1 << 3)
  static let edit = Self(rawValue: 1 << 4)
  static let delete = Self(rawValue: 1 << 5)
  static let select = Self(rawValue: 1 << 6)
}
