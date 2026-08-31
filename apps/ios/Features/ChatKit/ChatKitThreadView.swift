import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import Translation
import UIKit
import UniformTypeIdentifiers

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
  @State private var showsPinned = false
  @State private var showsInfo = false
  @State private var showsScheduled = false
  @State private var showsStickers = false
  @State private var showsTranslation = false
  @State private var translationText = ""
  @State private var showsMicDeniedAlert = false
  @State private var isImportingFile = false
  @State private var scrollTarget: String?
  @State private var audioPlayer = ChatKitAudioPlayer()
  @State private var showsWatchStart = false
  @State private var showsWatchHistory = false
  @State private var showsWatchScheduled = false
  /// The falling-emoji celebration currently playing over the thread, if any.
  @State private var celebration: ChatKitCelebration?

  private var store: ChatStore { model.chatStore }
  private var myID: String? { model.sessionStore.user?.id }
  private var messages: [ChatMessage] { store.messagesByChat[thread.id]?.value ?? [] }
  private var isTyping: Bool { store.typingUserIDByChat[thread.id] != nil }

  var body: some View {
    VStack(spacing: 0) {
      // Watch Together strips: the live-room join banner and the T-10
      // scheduled reminder, both fed by the room store's realtime events.
      if model.watchPartiesEnabled {
        WatchThreadBanner(conversationID: thread.id)
      }
      messageList
      composer
    }
    // Send effects: a lone 🎉, 🎊 or ❤️ rains a brief, untouchable burst.
    .overlay {
      if let celebration {
        ChatKitEmojiBurstView(emoji: celebration.emoji)
          .id(celebration.id)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .onChange(of: messages.last?.id) { oldValue, _ in
      // `oldValue == nil` is the initial history load — history never parties.
      guard oldValue != nil else { return }
      triggerCelebrationIfNeeded()
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbarTitle }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { showsInfo = true } label: { Label("Details", systemImage: "info.circle") }
          Button { showsSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
          Button { showsPinned = true } label: { Label("Pinned Messages", systemImage: "pin") }
          Button {
            showsScheduled = true
            Task { await store.loadScheduled(for: thread.id) }
          } label: {
            Label("Scheduled", systemImage: "timer")
          }
          if model.watchPartiesEnabled {
            Button { showsWatchHistory = true } label: {
              Label("watch.history.title", systemImage: "play.tv")
            }
            Button {
              showsWatchScheduled = true
            } label: {
              Label("watch.scheduled.title", systemImage: "calendar.badge.clock")
            }
          }
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
    .sheet(isPresented: $showsPinned) {
      ChatKitPinnedSheet(threadID: thread.id) { messageID in
        showsPinned = false
        scrollTarget = messageID
      }
    }
    .sheet(isPresented: $showsInfo) {
      ChatKitInfoSheet(thread: thread)
    }
    .sheet(isPresented: $showsScheduled) {
      ChatKitScheduledSheet(threadID: thread.id)
    }
    .sheet(isPresented: $showsStickers) {
      ChatKitStickerTray(threadID: thread.id, replyToID: replyingTo?.id) {
        replyingTo = nil
      }
    }
    .sheet(isPresented: $showsWatchStart) {
      WatchInviteSheet(context: WatchStartContext(conversationID: thread.id))
    }
    .sheet(isPresented: $showsWatchHistory) {
      WatchHistorySheet(conversationID: thread.id)
    }
    .sheet(isPresented: $showsWatchScheduled) {
      WatchScheduledSheet(conversationID: thread.id)
    }
    // On-device translation, Apple's own sheet — nothing leaves the phone.
    .translationPresentation(isPresented: $showsTranslation, text: translationText)
    .alert("Microphone Access Needed", isPresented: $showsMicDeniedAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Allow microphone access for Max in Settings to record voice messages.")
    }
    .fileImporter(
      isPresented: $isImportingFile,
      allowedContentTypes: [.item],
      onCompletion: handlePickedFile
    )
    .maxScreenBackground()
    .task {
      // A locked chat demands the device owner before showing anything, even
      // when navigation arrived here without passing through the inbox row.
      if model.chatLockStore.needsUnlock(thread.id) {
        guard await model.chatLockStore.unlock(thread.id) else {
          dismiss()
          return
        }
      }
      store.selectedThreadID = thread.id
      store.startRealtime(for: thread.id)
      if store.messagesByChat[thread.id]?.value == nil {
        await store.loadMessages(for: thread.id)
      }
      await store.markRead(thread.id)
    }
    .onDisappear {
      audioPlayer.stop()
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
                audioPlayer: audioPlayer,
                onReply: {
                  editing = nil
                  replyingTo = message
                },
                onEdit: { startEditing(message) },
                onForward: { forwarding = message },
                onTranslate: {
                  translationText = message.content ?? ""
                  showsTranslation = true
                }
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

            Button {
              isImportingFile = true
            } label: {
              Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(MaxColor.accent)
            }
            .accessibilityIdentifier("ui_chatkit_attach_file")

            Button {
              showsStickers = true
            } label: {
              Image(systemName: "face.smiling")
                .font(.system(size: 26))
                .foregroundStyle(MaxColor.accent)
            }
            .accessibilityIdentifier("ui_chatkit_stickers")

            if model.watchPartiesEnabled {
              Button {
                showsWatchStart = true
              } label: {
                Image(systemName: "play.tv")
                  .font(.system(size: 24))
                  .foregroundStyle(MaxColor.accent)
              }
              .accessibilityLabel(Text("watch.start"))
              .accessibilityIdentifier("ui_chatkit_watch")
            }
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
            // Long-press for Send Later: the three plans people actually make.
            .contextMenu {
              if editing == nil, canSend {
                Section("Send Later") {
                  ForEach(schedulePresets) { preset in
                    Button {
                      scheduleDraft(at: preset.date)
                    } label: {
                      Label(preset.title, systemImage: "timer")
                    }
                  }
                }
              }
            }
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

  /// Stages a document picked from the Files browser and sends it through the
  /// same upload path the photo picker uses.
  private func handlePickedFile(_ result: Result<URL, Error>) {
    guard case .success(let url) = result, !isUploading else { return }
    isUploading = true
    Task {
      defer { isUploading = false }
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      do {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let byteCount = values.fileSize,
              byteCount > 0 else { return }
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("ChatKitFileSends", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.copyItem(at: url, to: staged)
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
          ?? "application/octet-stream"
        let file = MobileUploadFile(
          fileURL: staged,
          byteCount: byteCount,
          fileName: url.lastPathComponent,
          mimeType: mimeType
        )
        await sendUploadedFiles([file])
      } catch {
        // The picker hands back a URL it just vended, so a copy failure here is
        // rare; the send state banner already covers upload-side errors.
      }
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
    guard await AVAudioApplication.requestRecordPermission() else {
      showsMicDeniedAlert = true
      return
    }
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
      // The dedicated voice endpoint stores the audio and posts the message in
      // one round trip, so a 200 KB note skips the three-step presigned flow.
      if let data = try? Data(contentsOf: url), !data.isEmpty {
        let replyID = replyingTo?.id
        replyingTo = nil
        _ = await store.sendVoiceMessage(to: thread.id, audioData: data, replyToID: replyID)
      }
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

  // MARK: - Send Later

  private struct SchedulePreset: Identifiable {
    let id: String
    let title: String
    let date: Date
  }

  /// "In 1 hour", "Tonight 20:00", "Tomorrow 09:00" — Tonight disappears once
  /// it is less than five minutes away (or already past). Mirrors the desktop.
  private var schedulePresets: [SchedulePreset] {
    let now = Date()
    let calendar = Calendar.current
    var presets = [
      SchedulePreset(id: "1h", title: "In 1 hour", date: now.addingTimeInterval(3600)),
    ]
    if let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now),
       tonight.timeIntervalSince(now) > 5 * 60 {
      presets.append(SchedulePreset(id: "tonight", title: "Tonight 20:00", date: tonight))
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
      presets.append(SchedulePreset(id: "tomorrow", title: "Tomorrow 09:00", date: morning))
    }
    return presets
  }

  private func scheduleDraft(at date: Date) {
    let text = store.draft(for: thread.id).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    Task {
      if await store.scheduleMessage(in: thread.id, body: text, sendAt: date) {
        store.setDraft("", for: thread.id)
      }
    }
  }

  private func startEditing(_ message: ChatMessage) {
    replyingTo = nil
    editing = message
    store.setDraft(message.content ?? "", for: thread.id)
  }

  // MARK: - Send effects

  /// Bodies that celebrate — a message that is exactly one of these rains a
  /// short emoji burst over the thread, whichever side sent it.
  private static let celebrationEmoji: Set<String> = ["🎉", "🎊", "❤️"]

  private func triggerCelebrationIfNeeded() {
    guard let newest = messages.last,
          !newest.isDeleted, !newest.isHardDeleted,
          let body = newest.content?.trimmingCharacters(in: .whitespacesAndNewlines),
          Self.celebrationEmoji.contains(body) else { return }
    let burst = ChatKitCelebration(emoji: body)
    celebration = burst
    Task {
      try? await Task.sleep(for: .seconds(1.8))
      if celebration?.id == burst.id { celebration = nil }
    }
  }

  // MARK: - Toolbar

  private var toolbarTitle: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Button { showsInfo = true } label: {
        HStack(spacing: MaxSpace.sm) {
          ChatKitAvatar(url: thread.avatarUrl, title: thread.displayTitle, isGroup: thread.isGroup)
            .frame(width: 32, height: 32)
          VStack(alignment: .leading, spacing: 0) {
            Text(thread.displayTitle)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if isTyping {
              Text("typing…")
                .font(.caption2)
                .foregroundStyle(MaxColor.accent)
            } else if let subtitle = headerSubtitle {
              Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// The pushed `thread` is immutable, so timer changes made in the Details
  /// sheet would never reach the header without reading the live row.
  private var liveThread: ChatThread {
    store.threads.value?.first(where: { $0.id == thread.id }) ?? thread
  }

  /// "Group", "⏱ 1d", or "Group · ⏱ 1d" — the second header line, carrying the
  /// disappearing-messages setting when the conversation has one.
  private var headerSubtitle: String? {
    let base = thread.isGroup ? "Group" : nil
    guard let ttl = liveThread.messageTtlSeconds, ttl > 0 else { return base }
    let timer = "⏱ \(ChatKitTime.compactDuration(ttl))"
    guard let base else { return timer }
    return "\(base) · \(timer)"
  }

  // MARK: - Rows

  private var rows: [ChatKitRow] {
    var out: [ChatKitRow] = []
    var lastDay = ""
    var lastSender: String?
    let now = Date()
    for message in messages {
      // A disappearing message whose expiry has passed is gone; the next
      // refresh drops it server-side, this just stops showing it first.
      if let expiry = ChatKitTime.date(message.expiresAt), expiry <= now {
        continue
      }
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

// ChatKitBubble, ChatKitExpiryChip, DaySeparator and TypingBubble moved to
// ChatKitBubbleViews.swift so the watch-room overlay chat can reuse them.

/// One celebration in flight; a fresh id per burst restarts the animation.
private struct ChatKitCelebration: Identifiable {
  let id = UUID()
  let emoji: String
}

/// ~1.8 s of falling emoji over the thread — eighteen pieces, staggered and
/// spinning, never interactive. Piece geometry lives in @State so parent
/// re-renders cannot reshuffle a burst mid-fall.
private struct ChatKitEmojiBurstView: View {
  let emoji: String

  struct Piece: Identifiable {
    let id: Int
    let x: CGFloat
    let delay: Double
    let duration: Double
    let size: CGFloat
    let spin: Double
  }

  @State private var pieces: [Piece] = (0..<18).map { index in
    Piece(
      id: index,
      x: CGFloat.random(in: 0.04...0.96),
      delay: Double.random(in: 0...0.45),
      duration: Double.random(in: 0.9...1.3),
      size: CGFloat.random(in: 22...34),
      spin: Double.random(in: -200...200)
    )
  }

  var body: some View {
    GeometryReader { geo in
      ForEach(pieces) { piece in
        ChatKitFallingEmoji(emoji: emoji, piece: piece, fallHeight: geo.size.height + 80)
          .position(x: geo.size.width * piece.x, y: -40)
      }
    }
    .clipped()
  }
}

private struct ChatKitFallingEmoji: View {
  let emoji: String
  let piece: ChatKitEmojiBurstView.Piece
  let fallHeight: CGFloat

  @State private var falling = false

  var body: some View {
    Text(verbatim: emoji)
      .font(.system(size: piece.size))
      .rotationEffect(.degrees(falling ? piece.spin : 0))
      .offset(y: falling ? fallHeight : 0)
      .opacity(falling ? 0.85 : 1)
      .onAppear {
        withAnimation(.easeIn(duration: piece.duration).delay(piece.delay)) {
          falling = true
        }
      }
  }
}

