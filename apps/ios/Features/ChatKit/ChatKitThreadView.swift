import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// ChatKit conversation screen: the rebuilt message thread. Bottom-anchored
/// bubble list with day separators, sender grouping, read receipts and a live
/// typing indicator, plus a lightweight composer — all driven by the proven
/// ChatStore (REST history + WebSocket realtime + idempotent send).
struct ChatKitThreadView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread

  @State private var showsDeleteConfirm = false
  @State private var replyingTo: ChatMessage?
  @State private var editing: ChatMessage?
  @State private var pickedItems: [PhotosPickerItem] = []
  @State private var isUploading = false
  @State private var voiceRecorder: AVAudioRecorder?
  @State private var voiceURL: URL?
  @State private var voiceDuration = 0
  @State private var voiceTimer: Task<Void, Never>?
  @State private var isRecording = false
  @State private var forwarding: ChatMessage?
  @State private var showsSearch = false
  @State private var showsInfo = false
  @State private var scrollTarget: String?

  private var store: ChatStore { model.chatStore }
  private var myID: String? { model.sessionStore.user?.id }
  private var messages: [ChatMessage] { store.messagesByChat[thread.id]?.value ?? [] }
  private var isTyping: Bool { store.typingUserIDByChat[thread.id] != nil }

  var body: some View {
    VStack(spacing: 0) {
      messageList
      composer
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbarTitle }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { showsInfo = true } label: { Label("Details", systemImage: "info.circle") }
          Button { showsSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
          Divider()
          Button(role: .destructive) { showsDeleteConfirm = true } label: {
            Label("Delete Conversation", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .confirmationDialog(
      "Delete this conversation?",
      isPresented: $showsDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        Task {
          if await store.deleteChat(thread.id) { dismiss() }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the conversation from your inbox.")
    }
    .sheet(item: $forwarding) { message in
      ChatKitForwardSheet(message: message, sourceThreadID: thread.id)
    }
    .sheet(isPresented: $showsSearch) {
      ChatKitSearchSheet(threadID: thread.id) { messageID in
        showsSearch = false
        scrollTarget = messageID
      }
    }
    .sheet(isPresented: $showsInfo) {
      ChatKitInfoSheet(thread: thread)
    }
    .maxScreenBackground()
    .task {
      store.selectedThreadID = thread.id
      store.startRealtime(for: thread.id)
      if store.messagesByChat[thread.id]?.value == nil {
        await store.loadMessages(for: thread.id)
      }
      await store.markRead(thread.id)
    }
    .onDisappear {
      if store.selectedThreadID == thread.id { store.selectedThreadID = nil }
    }
    .accessibilityIdentifier("ui_chatkit_thread")
  }

  // MARK: - Message list

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          if store.messagesByChat[thread.id]?.isLoading == true, messages.isEmpty {
            ProgressView().controlSize(.large).padding(.top, MaxSpace.xl)
          }

          ForEach(rows) { row in
            switch row {
            case .day(_, let label):
              DaySeparator(label: label)
                .padding(.vertical, MaxSpace.xs)
            case .message(let message, let isMine, let showsSender):
              ChatKitBubble(
                message: message,
                isMine: isMine,
                showsSender: showsSender,
                onReply: {
                  editing = nil
                  replyingTo = message
                },
                onEdit: { startEditing(message) },
                onForward: { forwarding = message }
              )
              .padding(.horizontal, MaxSpace.md)
              .id(message.id)
            }
          }

          if isTyping {
            TypingBubble()
              .padding(.horizontal, MaxSpace.md)
              .padding(.top, 2)
          }

          Color.clear.frame(height: 1).id(Self.bottomAnchor)
        }
        .padding(.vertical, MaxSpace.sm)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: messages.count) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
      }
      .onChange(of: isTyping) {
        withAnimation { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
      }
      .onChange(of: scrollTarget) {
        guard let target = scrollTarget else { return }
        withAnimation { proxy.scrollTo(target, anchor: .center) }
        scrollTarget = nil
      }
      .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
    }
  }

  private static let bottomAnchor = "chatkit.bottom"

  // MARK: - Composer

  private var composer: some View {
    VStack(spacing: 0) {
      if let replyingTo {
        composerBanner(
          icon: "arrowshape.turn.up.left",
          title: "Replying to \(replyingTo.sender?.displayName ?? "message")",
          subtitle: replyingTo.content ?? "Attachment"
        ) { self.replyingTo = nil }
      } else if let editing {
        composerBanner(
          icon: "pencil",
          title: "Editing message",
          subtitle: editing.content ?? ""
        ) {
          self.editing = nil
          store.setDraft("", for: thread.id)
        }
      }

      if isRecording {
        recordingBar
      } else {
        HStack(alignment: .bottom, spacing: MaxSpace.sm) {
          if isUploading {
            ProgressView()
              .frame(width: 30, height: 30)
          } else if editing == nil {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 6, matching: .images) {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(MaxColor.accent)
            }
            .accessibilityIdentifier("ui_chatkit_attach")
          }

          TextField("Message", text: draftBinding, axis: .vertical)
            .lineLimit(1...5)
            .padding(.horizontal, MaxSpace.md)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

          if canSend || editing != nil {
            Button(action: send) {
              Image(systemName: editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(canSend ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
            }
            .disabled(!canSend)
            .accessibilityIdentifier("ui_chatkit_send")
          } else {
            Button {
              Task { await startVoiceRecording() }
            } label: {
              Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(MaxColor.accent)
            }
            .disabled(isUploading)
            .accessibilityIdentifier("ui_chatkit_mic")
          }
        }
      }
    }
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
    .background(.bar)
    .onChange(of: pickedItems) { handlePickedItems() }
  }

  private var recordingBar: some View {
    HStack(spacing: MaxSpace.sm) {
      Button {
        cancelVoiceRecording()
      } label: {
        Image(systemName: "trash").foregroundStyle(.red)
      }
      Circle()
        .fill(.red)
        .frame(width: 9, height: 9)
      Text(voiceDurationText)
        .font(.subheadline.monospacedDigit())
      Spacer()
      Text("Recording…")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button {
        stopAndSendVoice()
      } label: {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 30))
          .foregroundStyle(MaxColor.accent)
      }
    }
  }

  private var voiceDurationText: String {
    String(format: "%d:%02d", voiceDuration / 60, voiceDuration % 60)
  }

  private func handlePickedItems() {
    let items = pickedItems
    guard !items.isEmpty, !isUploading else { return }
    isUploading = true
    Task {
      var files: [MobileUploadFile] = []
      for (index, item) in items.enumerated() {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
          files.append(
            MobileUploadFile(data: data, fileName: "photo-\(index + 1).jpg", mimeType: "image/jpeg")
          )
        }
      }
      pickedItems = []
      await sendUploadedFiles(files)
      isUploading = false
    }
  }

  /// Uploads the files then sends one message carrying them, applying the
  /// current draft as a caption and any active reply target.
  private func sendUploadedFiles(_ files: [MobileUploadFile]) async {
    guard !files.isEmpty, let fileIDs = await model.transferStore.upload(files: files) else { return }
    let text = store.draft(for: thread.id).trimmingCharacters(in: .whitespacesAndNewlines)
    store.setDraft("", for: thread.id)
    let replyID = replyingTo?.id
    replyingTo = nil
    _ = await store.sendMessage(
      to: thread.id,
      content: text.isEmpty ? nil : text,
      mediaFileIDs: fileIDs,
      replyToID: replyID
    )
  }

  // MARK: - Voice messages

  private func startVoiceRecording() async {
    guard await AVAudioApplication.requestRecordPermission() else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true)
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChatKitVoice", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
      let recorder = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
      )
      recorder.prepareToRecord()
      guard recorder.record() else { return }
      voiceURL = url
      voiceRecorder = recorder
      voiceDuration = 0
      isRecording = true
      voiceTimer?.cancel()
      voiceTimer = Task { @MainActor in
        while !Task.isCancelled, voiceRecorder?.isRecording == true {
          try? await Task.sleep(for: .seconds(1))
          if Task.isCancelled { return }
          voiceDuration += 1
        }
      }
    } catch {
      isRecording = false
    }
  }

  private func stopAndSendVoice() {
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceTimer?.cancel()
    voiceTimer = nil
    isRecording = false
    guard let url = voiceURL else { return }
    voiceURL = nil
    isUploading = true
    Task {
      var files: [MobileUploadFile] = []
      if let count = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, count > 0 {
        files.append(MobileUploadFile(fileURL: url, byteCount: count, fileName: "Voice.m4a", mimeType: "audio/mp4"))
      }
      await sendUploadedFiles(files)
      try? FileManager.default.removeItem(at: url)
      isUploading = false
    }
  }

  private func cancelVoiceRecording() {
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceTimer?.cancel()
    voiceTimer = nil
    isRecording = false
    if let url = voiceURL {
      try? FileManager.default.removeItem(at: url)
    }
    voiceURL = nil
  }

  private func composerBanner(
    icon: String,
    title: String,
    subtitle: String,
    onCancel: @escaping () -> Void
  ) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: icon).foregroundStyle(MaxColor.accent)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(MaxColor.accent)
        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      Button(action: onCancel) {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, MaxSpace.xs)
  }

  private var draftBinding: Binding<String> {
    Binding(
      get: { store.draft(for: thread.id) },
      set: { store.setDraft($0, for: thread.id) }
    )
  }

  private var canSend: Bool {
    !store.draft(for: thread.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func send() {
    let text = store.draft(for: thread.id).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    store.setDraft("", for: thread.id)

    if let editing {
      let messageID = editing.id
      self.editing = nil
      Task { _ = await store.editMessage(messageID, in: thread.id, content: text) }
    } else {
      let replyID = replyingTo?.id
      replyingTo = nil
      Task { _ = await store.sendMessage(to: thread.id, content: text, replyToID: replyID) }
    }
  }

  private func startEditing(_ message: ChatMessage) {
    replyingTo = nil
    editing = message
    store.setDraft(message.content ?? "", for: thread.id)
  }

  // MARK: - Toolbar

  private var toolbarTitle: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Button { showsInfo = true } label: {
        HStack(spacing: MaxSpace.sm) {
          ChatKitAvatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
            .frame(width: 32, height: 32)
          VStack(alignment: .leading, spacing: 0) {
            Text(thread.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if isTyping {
              Text("typing…")
                .font(.caption2)
                .foregroundStyle(MaxColor.accent)
            } else if thread.isGroup {
              Text("Group")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Rows

  private var rows: [ChatKitRow] {
    var out: [ChatKitRow] = []
    var lastDay = ""
    var lastSender: String?
    for message in messages {
      let day = ChatKitTime.dayKey(message.createdAt)
      if day != lastDay {
        out.append(.day(id: "day-\(day)", label: ChatKitTime.daySeparatorLabel(message.createdAt)))
        lastDay = day
        lastSender = nil
      }
      let isMine = myID != nil && message.senderId == myID
      let showsSender = thread.isGroup && !isMine && message.senderId != lastSender
      out.append(.message(message, isMine: isMine, showsSender: showsSender))
      lastSender = message.senderId
    }
    return out
  }
}

private enum ChatKitRow: Identifiable {
  case day(id: String, label: String)
  case message(ChatMessage, isMine: Bool, showsSender: Bool)

  var id: String {
    switch self {
    case .day(let id, _): return id
    case .message(let message, _, _): return message.id
    }
  }
}

// MARK: - Bubble

private struct ChatKitBubble: View {
  @Environment(MaxAppModel.self) private var model
  let message: ChatMessage
  let isMine: Bool
  let showsSender: Bool
  var onReply: () -> Void = {}
  var onEdit: () -> Void = {}
  var onForward: () -> Void = {}

  private static let reactionChoices = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

  var body: some View {
    HStack(spacing: 0) {
      if isMine { Spacer(minLength: 52) }

      VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
        if showsSender, let name = message.sender?.displayName, !name.isEmpty {
          Text(name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MaxColor.accent)
            .padding(.leading, 8)
        }
        bubbleBody
          .contextMenu { contextMenu }
        reactionsRow
      }

      if !isMine { Spacer(minLength: 52) }
    }
    .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
  }

  @ViewBuilder
  private var contextMenu: some View {
    if !message.isDeleted, !message.isHardDeleted {
      ControlGroup {
        ForEach(Self.reactionChoices, id: \.self) { emoji in
          Button(emoji) { react(emoji) }
        }
      }
      .environment(\.layoutDirection, .leftToRight)
      Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
      Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
      if let text = message.content, !text.isEmpty {
        Button {
          UIPasteboard.general.string = text
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
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
      HStack(spacing: 4) {
        ForEach(reactions, id: \.key) { reaction in
          Button {
            react(reaction.reactedByMe ? nil : reaction.key)
          } label: {
            Text(verbatim: "\(reaction.key) \(reaction.count)")
              .font(.caption2)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                reaction.reactedByMe ? AnyShapeStyle(MaxColor.accent.opacity(0.25)) : AnyShapeStyle(.regularMaterial),
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 6)
      .environment(\.layoutDirection, .leftToRight)
    }
  }

  private func react(_ key: String?) {
    Task { _ = await model.chatStore.setReaction(key, messageID: message.id, in: message.dmId) }
  }

  private var bubbleBody: some View {
    VStack(alignment: .leading, spacing: 4) {
      messageContent

      HStack(spacing: 4) {
        if message.isEdited {
          Text("chat.message.edited").font(.caption2)
        }
        Text(ChatKitTime.clock(message.createdAt)).font(.caption2)
        if isMine { deliveryTicks }
      }
      .foregroundStyle(isMine ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(.secondary))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .foregroundStyle(isMine ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.isDeleted || message.isHardDeleted {
      Text("This message was deleted")
        .italic()
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(mediaItems) { item in
          mediaThumbnail(item)
        }
        if hasLockedReference {
          Label("Locked media", systemImage: "lock.fill")
            .font(.subheadline)
        }
        if let text = message.content, !text.isEmpty {
          Text(text)
        } else if mediaItems.isEmpty, !hasLockedReference {
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

  private var mediaItems: [MaxMediaItem] {
    (message.mediaReferences ?? []).compactMap { reference in
      if case .media(let item) = reference.file { return item }
      return nil
    }
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
        .frame(width: 220, height: 200)
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
    .foregroundStyle(isRead ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.7)))
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
    isMine ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.regularMaterial)
  }
}

// MARK: - Small pieces

private struct DaySeparator: View {
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

private struct TypingBubble: View {
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
