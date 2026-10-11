import SwiftUI

/// App-wide VoiceOver announcer with per-category coalescing.
///
/// Generalizes the S6Clean `ComposerAccessibilityAnnouncer` idea (which is
/// excluded from the build) into a compiled, key-driven helper: callers hand a
/// localization key plus arguments, and every announcement in the same
/// category inside a 1.5 s window is folded into ONE utterance — so a burst of
/// realtime events ("X joined", "Y joined", 12 reactions) never turns
/// VoiceOver into a firehose. Reaction announcements coalesce into counts.
@MainActor
final class MaxAccessibilityAnnouncer {
  /// One coalescing lane. Messages in different categories never merge, so a
  /// roster change cannot swallow a sync warning.
  enum Category: Hashable, Sendable {
    case roster
    case sync
    case control
    case host
    case settings
    case queue
    case vote
    case reaction
    case lifecycle
    case generic
  }

  static let shared = MaxAccessibilityAnnouncer()

  /// How long a category buffers before speaking, letting rapid-fire events
  /// merge into a single sentence.
  static let coalescingWindow: TimeInterval = 1.5

  private var pendingByCategory: [Category: [String]] = [:]
  private var reactionCounts: [String: Int] = [:]
  private var reactionOrder: [String] = []
  private var flushTasks: [Category: Task<Void, Never>] = [:]

  /// Queues one localized announcement. `key` names a catalog entry whose
  /// value may carry `String(format:)` placeholders filled from `args`.
  func announce(key: String, args: [String] = [], category: Category = .generic) {
    let format = String(localized: String.LocalizationValue(key))
    let message = args.isEmpty
      ? format
      : String(format: format, arguments: args.map { $0 as CVarArg })
    guard !message.isEmpty else { return }
    pendingByCategory[category, default: []].append(message)
    scheduleFlush(for: category)
  }

  /// Queues one flying reaction. Unlike plain announcements these fold into
  /// per-emoji counts ("3 ❤️") so twenty hearts read as one phrase.
  func announceReaction(emoji: String) {
    if reactionCounts[emoji] == nil { reactionOrder.append(emoji) }
    reactionCounts[emoji, default: 0] += 1
    scheduleFlush(for: .reaction)
  }

  /// Drops everything queued without speaking — for teardown (leaving a room).
  func cancelPending() {
    for task in flushTasks.values { task.cancel() }
    flushTasks = [:]
    pendingByCategory = [:]
    reactionCounts = [:]
    reactionOrder = []
  }

  private func scheduleFlush(for category: Category) {
    guard flushTasks[category] == nil else { return }
    flushTasks[category] = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.coalescingWindow))
      guard !Task.isCancelled else { return }
      self?.flush(category)
    }
  }

  private func flush(_ category: Category) {
    flushTasks[category] = nil
    let message: String
    if category == .reaction {
      guard !reactionOrder.isEmpty else { return }
      let separator = String(localized: "watch.a11y.list_separator")
      let parts = reactionOrder.map { emoji in
        String(
          format: String(localized: "watch.a11y.reaction_count"),
          arguments: ["\(reactionCounts[emoji] ?? 0)" as CVarArg, emoji as CVarArg]
        )
      }
      reactionCounts = [:]
      reactionOrder = []
      message = String(
        format: String(localized: "watch.a11y.reactions"),
        arguments: [parts.joined(separator: separator) as CVarArg]
      )
    } else {
      let queued = pendingByCategory[category] ?? []
      pendingByCategory[category] = nil
      guard !queued.isEmpty else { return }
      message = queued.joined(separator: String(localized: "watch.a11y.list_separator"))
    }
    AccessibilityNotification.Announcement(message).post()
  }
}
