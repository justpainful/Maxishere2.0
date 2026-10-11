import Foundation
import SwiftUI
import UIKit

// ChatKit's bubble row and its small thread companions, extracted verbatim
// from ChatKitThreadView so other surfaces (the watch-room overlay chat) can
// render the same bubbles. Internal on purpose; behavior is unchanged.

// MARK: - Bubble

struct ChatKitBubble: View {
  @Environment(MaxAppModel.self) private var model
  let message: ChatMessage
  let isMine: Bool
  let showsSender: Bool
  let audioPlayer: ChatKitAudioPlayer
  var onReply: () -> Void = {}
  var onEdit: () -> Void = {}
  var onForward: () -> Void = {}
  var onTranslate: () -> Void = {}

  @State private var showReactionPicker = false

  /// The reaction key the current user already placed on this message.
  private var myReactionKey: String? {
    (message.reactions ?? []).first(where: { $0.reactedByMe })?.key
  }

  var body: some View {
    HStack(spacing: 0) {
      if isMine { Spacer(minLength: 52) }

      VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
        if showsSender, let name = message.sender?.displayName, !name.isEmpty {
          Text(name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Self.senderColor(for: message.senderId.isEmpty ? name : message.senderId))
            .padding(.leading, 8)
        }
        bubbleBody
          .contextMenu { contextMenu }
          // Double-tap = quick heart, the gesture every chat thumb expects.
          .onTapGesture(count: 2) {
            guard !message.isDeleted, !message.isHardDeleted else { return }
            react(myReactionKey == "❤️" ? nil : "❤️")
          }
          .popover(isPresented: $showReactionPicker, arrowEdge: .top) {
            ChatKitReactionPicker(current: myReactionKey) { key in
              showReactionPicker = false
              react(key)
            }
            .presentationCompactAdaptation(.popover)
          }
        reactionsRow
      }

      if !isMine { Spacer(minLength: 52) }
    }
    .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
  }

  @ViewBuilder
  private var contextMenu: some View {
    if !message.isDeleted, !message.isHardDeleted {
      // The emoji strip used to live HERE, as a ControlGroup the system menu
      // rendered as a cramped segmented row. It is now ChatKitReactionPicker,
      // a real surface of its own.
      Button { showReactionPicker = true } label: { Label("Add Reaction", systemImage: "face.smiling") }
      Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
      Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
      Button {
        let target = !(message.isPinned ?? false)
        Task { _ = await model.chatStore.setPinned(target, messageID: message.id, in: message.dmId) }
      } label: {
        if message.isPinned == true {
          Label("Unpin", systemImage: "pin.slash")
        } else {
          Label("Pin", systemImage: "pin")
        }
      }
      if let text = message.content, !text.isEmpty {
        Button {
          UIPasteboard.general.string = text
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        Button { onTranslate() } label: {
          Label("Translate", systemImage: "translate")
        }
      }
      if !isMine, let sticker = stickerAttachments.first {
        Button { adoptSticker(sticker) } label: {
          Label("Add to My Stickers", systemImage: "plus.square.on.square")
        }
      }
      if isMine {
        if message.content?.isEmpty == false {
          Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
        }
        Button(role: .destructive) {
          Task { _ = await model.chatStore.deleteMessage(message.id, in: message.dmId) }
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
  }

  private var reactions: [ChatReaction] { message.reactions ?? [] }

  @ViewBuilder
  private var reactionsRow: some View {
    if !reactions.isEmpty {
      HStack(spacing: 5) {
        ForEach(reactions, id: \.key) { reaction in
          Button {
            react(reaction.reactedByMe ? nil : reaction.key)
          } label: {
            HStack(spacing: 3) {
              Text(verbatim: reaction.key)
                .font(.system(size: 24))
              if reaction.count > 1 {
                Text(verbatim: "\(reaction.count)")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(reaction.reactedByMe ? MaxColor.accent : .secondary)
                  .contentTransition(.numericText())
              }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
              reaction.reactedByMe ? AnyShapeStyle(MaxColor.accent.opacity(0.22)) : AnyShapeStyle(.regularMaterial),
              in: Capsule()
            )
            .overlay(
              Capsule().strokeBorder(
                reaction.reactedByMe ? MaxColor.accent.opacity(0.55) : Color.clear,
                lineWidth: 1
              )
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 1)
      .environment(\.layoutDirection, .leftToRight)
      .animation(.spring(response: 0.3, dampingFraction: 0.75), value: reactions.map(\.count))
    }
  }

  private func react(_ key: String?) {
    Task { _ = await model.chatStore.setReaction(key, messageID: message.id, in: message.dmId) }
  }

  /// Copies someone else's sticker into my tray, then reloads the tray so the
  /// adopted sticker shows up on the next open.
  private func adoptSticker(_ attachment: ChatAttachment) {
    Task {
      guard (try? await model.apiClient.adoptSticker(mediaID: attachment.mediaId)) != nil else {
        return
      }
      await model.chatStore.loadStickers()
    }
  }

  private var bubbleBody: some View {
    VStack(alignment: .leading, spacing: 4) {
      messageContent

      HStack(spacing: 4) {
        if message.isEdited {
          Text("chat.message.edited").font(.caption2)
        }
        Text(ChatKitTime.clock(message.createdAt)).font(.caption2)
        if let expiresAt = message.expiresAt {
          ChatKitExpiryChip(expiresAt: expiresAt)
        }
        if isMine { deliveryTicks }
      }
      .foregroundStyle(
        isMine && !isBare
          ? AnyShapeStyle(Color.white.opacity(0.75))
          : AnyShapeStyle(.secondary)
      )
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .foregroundStyle(isMine && !isBare ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.isDeleted || message.isHardDeleted {
      Text("This message was deleted")
        .italic()
        .foregroundStyle(.secondary)
    } else if message.isWatchInvite {
      // A Watch Together invite travels as a marker message; the card resolves
      // the live room by conversation and renders its own state machine.
      WatchInviteBubbleView(
        conversationID: message.dmId,
        scheduledID: message.watchInviteScheduledID
      )
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(stickerAttachments) { attachment in
          stickerImage(attachment)
        }
        ForEach(mediaItems) { item in
          mediaThumbnail(item)
        }
        ForEach(audioAttachments) { attachment in
          ChatKitAudioBubble(
            attachment: attachment,
            player: audioPlayer,
            isMine: isMine,
            threadID: message.dmId,
            messageID: message.id
          )
        }
        ForEach(fileAttachments) { attachment in
          ChatKitFileBubble(attachment: attachment)
        }
        if hasLockedReference {
          Label("Locked media", systemImage: "lock.fill")
            .font(.subheadline)
        }
        if let text = message.content, !text.isEmpty {
          if let size = jumboFontSize {
            Text(text).font(.system(size: size))
          } else {
            Text(text)
          }
        } else if mediaItems.isEmpty, audioAttachments.isEmpty, fileAttachments.isEmpty,
                  stickerAttachments.isEmpty, !hasLockedReference {
          if hasLegacyMedia {
            Label(message.mediaName ?? "Attachment", systemImage: "paperclip")
              .font(.subheadline)
          } else {
            Text(" ")
          }
        }
      }
    }
  }

  /// Image and video attachments, preferring the server's `attachments[]`
  /// payload and falling back to the legacy media-reference projection.
  private var mediaItems: [MaxMediaItem] {
    let visual = (message.attachments ?? [])
      .filter { $0.resolvedKind == "image" || $0.resolvedKind == "video" }
      .compactMap(\.mediaItem)
    if !visual.isEmpty { return visual }
    return (message.mediaReferences ?? []).compactMap { reference in
      if case .media(let item) = reference.file { return item }
      return nil
    }
  }

  private var audioAttachments: [ChatAttachment] {
    (message.attachments ?? []).filter { $0.resolvedKind == "audio" }
  }

  private var stickerAttachments: [ChatAttachment] {
    (message.attachments ?? []).filter { $0.resolvedKind == "sticker" }
  }

  private var fileAttachments: [ChatAttachment] {
    (message.attachments ?? []).filter {
      let kind = $0.resolvedKind
      return kind != "image" && kind != "video" && kind != "audio" && kind != "sticker"
    }
  }

  /// A sticker with no text renders naked — no bubble surface behind it.
  /// Mirrors the desktop's `stickerOnly` logic.
  /// How many emoji this message is, when it is ONLY emoji — 0 otherwise.
  ///
  /// A handful of emoji on their own is a gesture, not a sentence, and at body
  /// size inside a bubble a lone 👍 reads like a typo. Counted by grapheme
  /// cluster, because 👍🏽 and 👨‍👩‍👧 are one emoji each to a reader and several
  /// scalars each to the string: counting scalars would call a two-emoji
  /// message a five-emoji one and never enlarge it.
  private var jumboEmojiCount: Int {
    guard !message.isDeleted, !message.isHardDeleted,
          stickerAttachments.isEmpty, mediaItems.isEmpty,
          audioAttachments.isEmpty, fileAttachments.isEmpty, message.poll == nil
    else { return 0 }
    let text = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return 0 }
    var count = 0
    for character in text {
      if character.isWhitespace { continue }
      // Letters and digits first: in Swift the ASCII digits report isEmoji
      // true, because they can head a keycap sequence, so an emoji test alone
      // would call "123" three emoji and blow it up to 38 points.
      guard !character.isLetter, !character.isNumber, !character.isPunctuation else { return 0 }
      guard character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.generalCategory == .otherSymbol })
      else { return 0 }
      count += 1
      if count > 3 { return 0 }
    }
    return count
  }

  /// A stable colour per person, the same in every group and across launches.
  ///
  /// Seeded from the sender id rather than the display name, so renaming
  /// yourself does not repaint your history. Saturation and brightness are
  /// fixed and only the hue varies, which keeps every name legible against
  /// both the light and the dark canvas instead of leaving half the palette
  /// unreadable on one of them.
  static func senderColor(for seed: String) -> Color {
    var hash: UInt64 = 0
    for byte in seed.utf8 { hash = hash &* 31 &+ UInt64(byte) }
    return Color(hue: Double(hash % 360) / 360.0, saturation: 0.62, brightness: 0.85)
  }

  private var jumboFontSize: CGFloat? {
    switch jumboEmojiCount {
    case 1: return 56
    case 2: return 46
    case 3: return 38
    default: return nil
    }
  }

  private var isStickerOnly: Bool {
    !message.isDeleted
      && !message.isHardDeleted
      && !stickerAttachments.isEmpty
      && (message.content ?? "").isEmpty
      && mediaItems.isEmpty
      && audioAttachments.isEmpty
      && fileAttachments.isEmpty
      && message.poll == nil
  }

  /// The sticker itself: a plain image up to ~160 pt, never inside a card.
  private func stickerImage(_ attachment: ChatAttachment) -> some View {
    MaxAsyncImage(url: attachment.url) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.quaternary)
      }
    }
    .frame(width: 200, height: 200)
    .accessibilityLabel(Text("Sticker"))
  }

  private var hasLockedReference: Bool {
    (message.mediaReferences ?? []).contains { reference in
      if case .locked = reference.file { return true }
      return false
    }
  }

  private var hasLegacyMedia: Bool {
    message.mediaUrl != nil || message.mediaType != nil
  }

  private func mediaThumbnail(_ item: MaxMediaItem) -> some View {
    Button {
      model.openPlayer(for: item)
    } label: {
      ZStack {
        MaxAsyncImage(url: item.posterURL) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            Rectangle().fill(.quaternary)
          }
        }
        .frame(width: 260, height: 260)
        .clipped()

        if item.kind.lowercased() == "video" {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 42))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(radius: 4)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  /// Sent is one tick, read is two — the convention every messenger already
  /// taught our users. The previous pairing (a bare checkmark against a filled
  /// circled one) asked people to tell two unrelated glyphs apart, and neither
  /// carried a label for VoiceOver.
  private var deliveryTicks: some View {
    HStack(spacing: -2.5) {
      Image(systemName: "checkmark")
      if isRead {
        Image(systemName: "checkmark")
      }
    }
    .font(.system(size: 10, weight: .bold))
    // Read ticks sit at full strength against the accent bubble; an unread one
    // stays at the timestamp's weight so the change is legible at a glance.
    // A sticker-only message has no bubble surface, so white would vanish on a
    // light background — the ticks borrow the timestamp's secondary weight.
    .foregroundStyle(
      isStickerOnly
        ? (isRead ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
        : (isRead ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.7)))
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(receiptLabel))
  }

  private var receiptLabel: LocalizedStringKey {
    isRead ? "chat.receipt.read" : "chat.receipt.sent"
  }

  private var isRead: Bool {
    (message.readReceipts?.isEmpty == false) || (message.readAt != nil)
  }

  private var bubbleBackground: AnyShapeStyle {
    // Stickers and lone emoji both sit on nothing: a coloured slab behind them
    // is the bubble refusing to get out of the way.
    if isStickerOnly || jumboFontSize != nil { return AnyShapeStyle(Color.clear) }
    return isMine ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.regularMaterial)
  }

  /// True when the bubble has no surface, so text on it must not use the
  /// on-accent white it would otherwise inherit.
  private var isBare: Bool { isStickerOnly || jumboFontSize != nil }
}

// MARK: - Small pieces

/// Tiny "timer + remaining" chip beside a disappearing message's timestamp.
/// Ticks every second only inside the final minute; above that a static
/// relative value is close enough and costs nothing.
struct ChatKitExpiryChip: View {
  let expiresAt: String

  var body: some View {
    if let expiry = ChatKitTime.date(expiresAt) {
      if expiry.timeIntervalSinceNow <= 60 {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          chip(remaining: expiry.timeIntervalSince(context.date))
        }
      } else {
        chip(remaining: expiry.timeIntervalSinceNow)
      }
    }
  }

  private func chip(remaining: TimeInterval) -> some View {
    HStack(spacing: 2) {
      Image(systemName: "timer")
      Text(ChatKitTime.compactDuration(Int(remaining.rounded())))
    }
    .font(.caption2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Disappearing message"))
  }
}

struct DaySeparator: View {
  let label: String
  var body: some View {
    Text(label)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(.thinMaterial, in: Capsule())
      .frame(maxWidth: .infinity)
  }
}

struct TypingBubble: View {
  @State private var phase = 0.0
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<3) { index in
        Circle()
          .frame(width: 7, height: 7)
          .foregroundStyle(.secondary)
          .opacity(phase == Double(index) ? 1 : 0.3)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      withAnimation(.easeInOut(duration: 0.6).repeatForever()) { phase = 2 }
    }
  }
}
