import SwiftUI
import PhotosUI
import UIKit

// MARK: - Dates

enum ChatsV3TimeFormatter {
  static func parse(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: trimmed) { return date }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let date = standard.date(from: trimmed) { return date }

    // SQLite CURRENT_TIMESTAMP uses `yyyy-MM-dd HH:mm:ss` without a zone.
    // The server stores these values in UTC, so normalize them before parsing.
    if trimmed.count >= 19 {
      let index = trimmed.index(trimmed.startIndex, offsetBy: 10)
      if trimmed[index] == " " {
        var normalized = trimmed
        normalized.replaceSubrange(index...index, with: "T")
        if !normalized.hasSuffix("Z") { normalized.append("Z") }
        return fractional.date(from: normalized) ?? standard.date(from: normalized)
      }
    }
    return nil
  }

  static func message(_ value: String) -> String {
    guard let date = parse(value) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
  }

  static func inbox(_ value: String) -> String {
    guard let date = parse(value) else { return "" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
      return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }

  static func day(_ value: String) -> String {
    guard let date = parse(value) else { return "" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
  }

  static func isSameDay(_ first: String?, _ second: String?) -> Bool {
    guard let first, let second, let lhs = parse(first), let rhs = parse(second) else {
      return false
    }
    return Calendar.current.isDate(lhs, inSameDayAs: rhs)
  }
}

// MARK: - Conversation

struct ChatsV3ConversationView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread

  @State private var replyTarget: ChatMessage?
  @State private var editTarget: ChatMessage?
  @State private var editText = ""
  @State private var selectedMentionIDs = [String]()
  @State private var selectedMessageIDs = Set<String>()
  @State private var isSelectMode = false
  @State private var showsInfo = false
  @State private var showsSearch = false
  @State private var showsDeleteChatConfirm = false
  @State private var showsBulkPermanentDelete = false
  @State private var pendingPermanentDelete: ChatMessage?
  @State private var forwardTarget: ChatMessage?
  @State private var pickerItems: [PhotosPickerItem] = []
  @State private var isViewOnceMode = false
  @State private var isRecording = false
  @State private var audioRecorder: AVAudioRecorder?
  @State private var recordingURL: URL?
  @State private var activeViewOnceMessage: ChatMessage? = nil
  @State private var recordDuration: Int = 0
  @State private var timerTask: Task<Void, Never>? = nil

  private var messages: [ChatMessage] {
    model.chatsV3Store.visibleMessages(for: thread.id)
  }

  private var members: [ChatGroupMember] {
    model.chatsV3Store.membersByChat[thread.id]?.value ?? []
  }

  var body: some View {
    VStack(spacing: 0) {
      messageTimeline
      if isSelectMode { selectionActionBar }
      if let target = replyTarget, !isSelectMode { replyBanner(target) }
      if !isSelectMode { composer }
    }
    .navigationTitle(thread.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar { toolbarItems }
    .sheet(isPresented: $showsInfo) { ChatsV3ChatInfoSheet(thread: thread) }
    .sheet(isPresented: $showsSearch) { ChatsV3MessageSearchSheet(thread: thread) }
    .sheet(item: $forwardTarget) { message in
      ChatsV3ForwardSheet(message: message, sourceChatID: thread.id)
    }
    .alert("Remove conversation?", isPresented: $showsDeleteChatConfirm) {
      Button("action.remove", role: .destructive) {
        Task {
          if await model.chatsV3Store.deleteChat(thread.id) { dismiss() }
        }
      }
      Button("action.cancel", role: .cancel) {}
    } message: {
      Text("chat.delete_chat.subtitle")
    }
    .confirmationDialog(
      "Delete message permanently?",
      isPresented: Binding(
        get: { pendingPermanentDelete != nil },
        set: { if !$0 { pendingPermanentDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("chat.delete_chat.both.confirm", role: .destructive) {
        guard let message = pendingPermanentDelete else { return }
        pendingPermanentDelete = nil
        Task { await model.chatsV3Store.deletePermanent(message) }
      }
      Button("action.cancel", role: .cancel) { pendingPermanentDelete = nil }
    } message: {
      Text("chat.delete_chat.both.subtitle")
    }
    .confirmationDialog(
      "Delete selected messages permanently?",
      isPresented: $showsBulkPermanentDelete,
      titleVisibility: .visible
    ) {
      Button("Delete \(selectedMessageIDs.count) Messages", role: .destructive) {
        Task { await deleteSelectedPermanently() }
      }
      Button("action.cancel", role: .cancel) {}
    }
    .task {
      if model.chatsV3Store.messagesByChat[thread.id]?.value == nil {
        await model.chatsV3Store.loadMessages(for: thread.id)
      }
      if thread.isGroup && model.chatsV3Store.membersByChat[thread.id]?.value == nil {
        await model.chatsV3Store.loadMembers(for: thread.id)
      }
      await model.chatsV3Store.loadPreference(for: thread.id)
    }
    .refreshable {
      await model.chatsV3Store.loadMessages(for: thread.id)
      await model.chatsV3Store.loadInbox()
    }
    .accessibilityIdentifier("ui_chats_v3_conversation")
    .fullScreenCover(item: $activeViewOnceMessage) { msg in
      ScreenshotPreventingView(content:
        ZStack {
          Color.black.ignoresSafeArea()
          if let mediaUrl = msg.mediaUrl, let url = URL(string: mediaUrl) {
            MaxAsyncImage(url: url) { phase in
              if case .success(let image) = phase {
                image
                  .resizable()
                  .scaledToFit()
                  .ignoresSafeArea()
              } else {
                ProgressView().tint(.white)
              }
            }
          }
          VStack {
            HStack {
              Spacer()
              Button {
                activeViewOnceMessage = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.title)
                  .foregroundStyle(.white)
                  .padding()
              }
            }
            Spacer()
          }
        }
      )
      .ignoresSafeArea()
      .onDisappear {
        Task {
          await model.chatsV3Store.readViewOnceMessage(chatID: thread.id, messageID: msg.id)
        }
      }
    }
    .onChange(of: pickerItems) { _, items in
      Task { await handlePickedPhotos(items) }
    }
    .onAppear {
      model.chatsV3Store.activeChatID = thread.id
    }
    .onDisappear {
      if model.chatsV3Store.activeChatID == thread.id {
        model.chatsV3Store.activeChatID = nil
      }
    }
  }

  private func startRecording() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playAndRecord, mode: .default)
    try? session.setActive(true)

    let path = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
    recordingURL = path

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 12000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    audioRecorder = try? AVAudioRecorder(url: path, settings: settings)
    audioRecorder?.record()
    isRecording = true
    recordDuration = 0
    timerTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        recordDuration += 1
      }
    }
  }

  private func stopRecording(send: Bool) async {
    timerTask?.cancel()
    timerTask = nil
    audioRecorder?.stop()
    isRecording = false
    
    if send, let path = recordingURL, let data = try? Data(contentsOf: path) {
      await model.chatsV3Store.sendVoiceMessage(
        in: thread.id,
        audioData: data,
        replyToID: replyTarget?.id
      )
      replyTarget = nil
    }
    recordingURL = nil
  }

  @ToolbarContentBuilder
  private var toolbarItems: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      if isSelectMode {
        Button("common.done") { leaveSelectionMode() }
      } else {
        Menu {
          Button("chats.search", systemImage: "magnifyingglass") { showsSearch = true }
          Button("chat.info", systemImage: thread.isGroup ? "person.3" : "info.circle") {
            showsInfo = true
          }
          Button("chat.select", systemImage: "checkmark.circle") {
            isSelectMode = true
          }
          Button("chat.clear_chat", systemImage: "clear", role: .destructive) {
            Task {
              _ = await model.chatsV3Store.clearChat(chatID: thread.id)
            }
          }
          Divider()
          Button("chat.delete_chat", systemImage: "trash", role: .destructive) {
            showsDeleteChatConfirm = true
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
  }

  @ViewBuilder
  private var messageTimeline: some View {
    let state = model.chatsV3Store.messagesByChat[thread.id] ?? .idle
    if state.isLoading && state.value == nil {
      Spacer()
      ProgressView("Loading messages…")
      Spacer()
    } else if let error = state.errorMessage {
      ContentUnavailableView(
        "Messages unavailable",
        systemImage: "exclamationmark.bubble",
        description: Text(error)
      )
    } else if messages.isEmpty {
      ContentUnavailableView(
        "No messages yet",
        systemImage: "bubble.left",
        description: Text("chat.thread.empty")
      )
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 3) {
            ForEach(messages.indices, id: \.self) { index in
              let message = messages[index]
              if shouldShowDaySeparator(at: index) {
                ChatsV3DaySeparator(title: ChatsV3TimeFormatter.day(message.createdAt ?? ""))
              }
              ChatsV3MessageBubble(
                message: message,
                isMine: message.senderId == model.sessionStore.user?.id,
                isSelected: selectedMessageIDs.contains(message.id),
                isSelectMode: isSelectMode,
                isSentHidden: model.chatsV3Store.hiddenSentMessageIDs.contains(message.id),
                react: { key in Task { await model.chatsV3Store.react(to: message, key: key) } },
                deleteForMe: { Task { await model.chatsV3Store.delete(message) } },
                deletePermanent: { pendingPermanentDelete = message },
                edit: {
                  editTarget = message
                  editText = message.content ?? ""
                },
                hideSent: { Task { await model.chatsV3Store.hideSent(message) } },
                pin: {
                  Task {
                    await model.chatsV3Store.setPinned(
                      message,
                      isPinned: message.isPinned != true
                    )
                  }
                },
                forward: { forwardTarget = message },
                copy: { UIPasteboard.general.string = message.content ?? "" },
                reply: { replyTarget = message },
                toggleSelect: { toggleSelection(message.id) },
                viewOnce: { activeViewOnceMessage = message }
              )
              .id(message.id)
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 10)
        }
        .defaultScrollAnchor(.bottom)
        .onChange(of: messages.last?.id) { _, id in
          guard let id else { return }
          withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
    }
  }

  private func shouldShowDaySeparator(at index: Int) -> Bool {
    guard messages.indices.contains(index) else { return false }
    if index == 0 { return true }
    return !ChatsV3TimeFormatter.isSameDay(
      messages[index - 1].createdAt,
      messages[index].createdAt
    )
  }

  private func replyBanner(_ message: ChatMessage) -> some View {
    HStack(spacing: 10) {
      Capsule().fill(MaxColor.accent).frame(width: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text("chat.replying_to")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(MaxColor.accent)
        Text(message.content ?? "Photo")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button { replyTarget = nil } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private var selectionActionBar: some View {
    HStack(spacing: 8) {
      // Interpolating into the key builds the lookup name "chats.selected_count %lld",
      // which is absent from the catalogue; the specifier lives in the value.
      Text(String(format: String(localized: "chats.selected_count"), selectedMessageIDs.count))
        .font(.subheadline.weight(.semibold))
      Spacer()
      Button("chat.copy", systemImage: "doc.on.doc") {
        UIPasteboard.general.string = messages
          .filter { selectedMessageIDs.contains($0.id) }
          .compactMap(\.content)
          .joined(separator: "\n")
        leaveSelectionMode()
      }
      .labelStyle(.iconOnly)
      .disabled(selectedMessageIDs.isEmpty)

      Button("memories.hide", systemImage: "eye.slash") {
        let selected = messages.filter { selectedMessageIDs.contains($0.id) }
        Task {
          for message in selected { await model.chatsV3Store.delete(message) }
          leaveSelectionMode()
        }
      }
      .labelStyle(.iconOnly)
      .disabled(selectedMessageIDs.isEmpty)

      Button("chat.delete_chat.both.confirm", systemImage: "trash.fill", role: .destructive) {
        showsBulkPermanentDelete = true
      }
      .labelStyle(.iconOnly)
      .disabled(selectedMessageIDs.isEmpty)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 50)
    .background(.bar)
  }

  private var composer: some View {
    VStack(spacing: 6) {
      if let target = editTarget { editBanner(target) }

      if thread.isGroup, !members.isEmpty, editTarget == nil {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(members) { member in
              Button {
                toggleMention(member)
              } label: {
                Text("@\(member.displayName)")
                  .font(.caption.weight(.medium))
                  .padding(.horizontal, 9)
                  .padding(.vertical, 5)
                  .background(
                    selectedMentionIDs.contains(member.userId)
                      ? MaxColor.accent.opacity(0.25)
                      : Color.secondary.opacity(0.10),
                    in: Capsule()
                  )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 12)
        }
      }

      Group {
        if isRecording {
          HStack(spacing: 12) {
            Image(systemName: "circle.fill")
              .foregroundStyle(.red)
              .opacity(isRecording ? 1.0 : 0.4)
            Text(String(format: String(localized: "chats.recording_voice"), recordDuration))
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Spacer()
            Button("action.cancel", role: .cancel) {
              Task { await stopRecording(send: false) }
            }
            .buttonStyle(.bordered)
            Button {
              Task { await stopRecording(send: true) }
            } label: {
              Image(systemName: "paperplane.fill")
                .foregroundStyle(MaxColor.accent)
                .font(.title3)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, 16)
          .frame(height: 44)
        } else {
          HStack(alignment: .bottom, spacing: 8) {
            if editTarget == nil {
              HStack(spacing: 4) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                  Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(MaxColor.accent)
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(model.chatsV3Store.isSending.contains(thread.id))

                Button {
                  isViewOnceMode.toggle()
                } label: {
                  Image(systemName: isViewOnceMode ? "eye.circle.fill" : "eye.circle")
                    .font(.title3)
                    .foregroundStyle(isViewOnceMode ? MaxColor.accent : Color.secondary)
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(model.chatsV3Store.isSending.contains(thread.id))
              }
            }

            if let target = editTarget {
              TextField("Edit message…", text: $editText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                  Task {
                    await model.chatsV3Store.editMessage(
                      id: target.id,
                      chatID: thread.id,
                      newContent: editText
                    )
                    editTarget = nil
                    editText = ""
                  }
                }

              Button("common.save", systemImage: "checkmark.circle.fill") {
                Task {
                  await model.chatsV3Store.editMessage(
                    id: target.id,
                    chatID: thread.id,
                    newContent: editText
                  )
                  editTarget = nil
                  editText = ""
                }
              }
              .labelStyle(.iconOnly)
              .font(.title2)
              .foregroundStyle(MaxColor.accent)
            } else {
              TextField(
                "Message",
                text: Binding(
                  get: { model.chatsV3Store.composerByChat[thread.id] ?? "" },
                  set: { model.chatsV3Store.composerByChat[thread.id] = $0 }
                )
              )
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
              .onSubmit {
                let text = model.chatsV3Store.composerByChat[thread.id] ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task {
                  await model.chatsV3Store.send(
                    in: thread.id,
                    replyToID: replyTarget?.id,
                    mentionUserIDs: selectedMentionIDs
                  )
                  replyTarget = nil
                  selectedMentionIDs = []
                }
              }

              if (model.chatsV3Store.composerByChat[thread.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                  startRecording()
                } label: {
                  Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(MaxColor.accent)
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
              } else {
                Button("chat.send", systemImage: "arrow.up.circle.fill") {
                  Task {
                    await model.chatsV3Store.send(
                      in: thread.id,
                      replyToID: replyTarget?.id,
                      mentionUserIDs: selectedMentionIDs
                    )
                    replyTarget = nil
                    selectedMentionIDs = []
                  }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(MaxColor.accent)
                .disabled(model.chatsV3Store.isSending.contains(thread.id))
                .accessibilityIdentifier("ui_chats_v3_send")
              }
            }
          }
        }
      }
      .padding(.horizontal, 12)

      if let error = model.chatsV3Store.sendErrorByChat[thread.id] {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal)
      }
    }
    .padding(.vertical, 10)
    .background(.bar)
  }

  private func editBanner(_ message: ChatMessage) -> some View {
    HStack(spacing: 10) {
      Capsule().fill(MaxColor.accent).frame(width: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text("chat.edit.title")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(MaxColor.accent)
        Text(message.content ?? "")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button {
        editTarget = nil
        editText = ""
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.top, 6)
  }

  private func toggleMention(_ member: ChatGroupMember) {
    if selectedMentionIDs.contains(member.userId) {
      selectedMentionIDs.removeAll { $0 == member.userId }
    } else {
      selectedMentionIDs.append(member.userId)
      let name = member.displayName.split(separator: " ").first.map(String.init)
        ?? member.displayName
      model.chatsV3Store.composerByChat[thread.id, default: ""] += " @\(name)"
    }
  }

  private func toggleSelection(_ messageID: String) {
    isSelectMode = true
    if selectedMessageIDs.contains(messageID) {
      selectedMessageIDs.remove(messageID)
    } else {
      selectedMessageIDs.insert(messageID)
    }
  }

  private func leaveSelectionMode() {
    isSelectMode = false
    selectedMessageIDs.removeAll()
  }

  private func deleteSelectedPermanently() async {
    let selected = messages.filter { selectedMessageIDs.contains($0.id) }
    for message in selected where message.senderId == model.sessionStore.user?.id {
      await model.chatsV3Store.deletePermanent(message)
    }
    leaveSelectionMode()
  }

  private func handlePickedPhotos(_ items: [PhotosPickerItem]) async {
    for item in items {
      guard let source = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: source),
            let jpeg = image.jpegData(compressionQuality: 0.88) else { continue }
      await model.chatsV3Store.sendImage(
        in: thread.id,
        imageData: jpeg,
        replyToID: replyTarget?.id,
        isViewOnce: isViewOnceMode
      )
    }
    isViewOnceMode = false
    replyTarget = nil
    pickerItems = []
  }
}

// MARK: - Bubble

private struct ChatsV3DaySeparator: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(.thinMaterial, in: Capsule())
      .padding(.vertical, 8)
  }
}

private struct ChatsV3MessageBubble: View {
  let message: ChatMessage
  let isMine: Bool
  let isSelected: Bool
  let isSelectMode: Bool
  let isSentHidden: Bool
  let react: (String?) -> Void
  let deleteForMe: () -> Void
  let deletePermanent: () -> Void
  let edit: () -> Void
  let hideSent: () -> Void
  let pin: () -> Void
  let forward: () -> Void
  let copy: () -> Void
  let reply: () -> Void
  let toggleSelect: () -> Void
  let viewOnce: () -> Void

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if isSelectMode {
        Button { toggleSelect() } label: {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? MaxColor.accent : .secondary)
        }
        .buttonStyle(.plain)
      }

      if isMine && !isSelectMode { Spacer(minLength: 42) }

      VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
        if !isMine {
          Text(verbatim: message.sender?.displayName ?? message.senderId)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MaxColor.accent)
            .padding(.horizontal, 4)
        }

        if let reply = message.replyPreview {
          HStack(spacing: 6) {
            Capsule().fill(MaxColor.accent.opacity(0.65)).frame(width: 3)
            Text(reply.content ?? "Photo")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal, 4)
        }

        if message.isViewOnce == true {
          if message.isViewOnceConsumed {
            HStack(spacing: 8) {
              Image(systemName: "eye.slash.fill")
                .foregroundStyle(.secondary)
              Text("chats.opened_photo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
          } else {
            Button {
              viewOnce()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "viewfinder.circle.fill")
                  .foregroundStyle(MaxColor.accent)
                Text("chats.view_photo_once")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(MaxColor.accent)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(MaxColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
          }
        } else if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
          if message.mediaType == "voice" || mediaUrl.contains("voice") || message.mediaName?.hasSuffix(".m4a") == true {
            VoiceMessagePlayerView(url: url)
          } else {
            MaxAsyncImage(url: url) { phase in
              switch phase {
              case .success(let image):
                image
                  .resizable()
                  .scaledToFit()
                  .frame(width: 250, height: 280)
                  .background(Color.black.opacity(0.06))
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              case .failure:
                ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark")
                  .frame(width: 230, height: 150)
              default:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .fill(Color.secondary.opacity(0.10))
                  .frame(width: 230, height: 170)
                  .overlay(ProgressView())
              }
            }
          }
        }

        if !message.isDeleted, let text = message.content, !text.isEmpty {
          Text(text)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        } else if message.isDeleted {
          Label("chat.message.deleted", systemImage: "trash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .italic()
        }

        if let reactions = message.reactions, !reactions.isEmpty {
          // The stored key is a symbolic name such as `thumbs_up`; rendering it
          // raw printed "thumbs_up 2" next to the bubble.
          MaxS6ReactionBar(reactions: reactions) { reaction in
            react(reaction.reactedByMe ? nil : reaction.key)
          }
        }

        HStack(spacing: 4) {
          if message.isPinned == true {
            Image(systemName: "pin.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          if message.isEdited {
            Text("chat.message.edited")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Text(ChatsV3TimeFormatter.message(message.createdAt ?? ""))
            .font(.caption2)
            .foregroundStyle(.secondary)
          if isMine && !message.isDeleted && !isSentHidden {
            Image(systemName: "checkmark.circle.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 2)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .frame(maxWidth: 320, alignment: isMine ? .trailing : .leading)
      .background(
        isMine ? MaxColor.accent.opacity(0.18) : Color.secondary.opacity(0.10),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(MaxColor.accent, lineWidth: 2)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { if isSelectMode { toggleSelect() } }
      .contextMenu { messageMenu }

      if !isMine && !isSelectMode { Spacer(minLength: 42) }
    }
    .padding(.vertical, 2)
    .animation(.spring(duration: 0.2), value: isSelectMode)
  }

  @ViewBuilder
  private var messageMenu: some View {
    if !message.isDeleted {
      Button("chat.reply", systemImage: "arrowshape.turn.up.left") { reply() }
      Button("chat.copy", systemImage: "doc.on.doc") { copy() }
      Button("chat.forward", systemImage: "arrowshape.turn.up.right") { forward() }
      Button(message.isPinned == true ? "chat.unpin" : "chat.pin", systemImage: "pin") { pin() }
      if isMine { Button("chat.edit", systemImage: "pencil") { edit() } }
      Button("chat.select", systemImage: "checkmark.circle") { toggleSelect() }
      Menu("React", systemImage: "face.smiling") {
        Button { react("thumbs_up") } label: { Text(verbatim: "👍") }
        Button { react("heart") } label: { Text(verbatim: "❤️") }
        Button { react("laugh") } label: { Text(verbatim: "😂") }
        Button { react("thumbs_down") } label: { Text(verbatim: "👎") }
        Button { react("emphasis") } label: { Text(verbatim: "‼️") }
        Button { react("question") } label: { Text(verbatim: "❓") }
      }
      Divider()
      if isMine {
        Button("chat.delivery.sent", systemImage: "checkmark.circle.badge.xmark") { hideSent() }
      }
      Button("chat.delete_chat.both.confirm", systemImage: "eye.slash", role: .destructive) { deleteForMe() }
      if isMine {
        Button("chat.delete_chat.both.confirm", systemImage: "trash.fill", role: .destructive) {
          deletePermanent()
        }
      }
    }
  }
}

// MARK: - Forward

private struct ChatsV3ForwardSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let message: ChatMessage
  let sourceChatID: String
  @State private var searchText = ""
  @State private var isForwarding = false

  private var threads: [ChatThread] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return (model.chatsV3Store.inbox.value ?? []).filter {
      $0.id != sourceChatID
        && $0.isArchived != true
        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
    }
  }

  var body: some View {
    NavigationStack {
      List(threads) { thread in
        Button {
          isForwarding = true
          Task {
            if await model.chatsV3Store.forward(message, to: thread.id) { dismiss() }
            isForwarding = false
          }
        } label: {
          HStack(spacing: 12) {
            ChatsV3Avatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
            Text(thread.title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrowshape.turn.up.right")
              .foregroundStyle(MaxColor.accent)
          }
        }
        .disabled(isForwarding)
      }
      .overlay {
        if threads.isEmpty {
          ContentUnavailableView("No chats", systemImage: "bubble.left.and.bubble.right")
        }
      }
      .navigationTitle("chat.forward")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $searchText, prompt: "Choose a chat")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("action.cancel") { dismiss() }
        }
      }
    }
  }
}

// MARK: - Search

private struct ChatsV3MessageSearchSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread
  @State private var query = ""
  @State private var results = [ChatMessage]()

  var body: some View {
    NavigationStack {
      List(results) { message in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(message.sender?.displayName ?? "Member")
              .font(.caption.weight(.bold))
            Spacer()
            Text(ChatsV3TimeFormatter.inbox(message.createdAt ?? ""))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Text(message.content ?? "Photo")
        }
      }
      .overlay {
        if query.isEmpty {
          ContentUnavailableView("Search messages", systemImage: "magnifyingglass")
        } else if results.isEmpty {
          ContentUnavailableView(
            "No results",
            systemImage: "magnifyingglass",
            description: Text("home.empty.subtitle")
          )
        }
      }
      .navigationTitle("chats.search")
      .searchable(text: $query, prompt: "Find a message")
      .onChange(of: query) { _, text in
        Task {
          guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
          }
          results = (try? await model.apiClient.searchMessages(
            chatID: thread.id,
            query: text,
            limit: 100
          ).messages) ?? []
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("common.done") { dismiss() } }
      }
    }
  }
}

struct VoiceMessagePlayerView: View {
  let url: URL
  @State private var avPlayer: AVPlayer?
  @State private var isPlaying = false
  @State private var observer: Any? = nil

  var body: some View {
    HStack(spacing: 12) {
      Button {
        if isPlaying {
          avPlayer?.pause()
          isPlaying = false
        } else {
          if avPlayer == nil {
            avPlayer = AVPlayer(url: url)
            NotificationCenter.default.addObserver(
              forName: .AVPlayerItemDidPlayToEndTime,
              object: avPlayer?.currentItem,
              queue: .main
            ) { _ in
              isPlaying = false
              avPlayer?.seek(to: .zero)
            }
          }
          avPlayer?.play()
          isPlaying = true
        }
      } label: {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.headline)
          .foregroundStyle(MaxColor.accent)
          .frame(width: 36, height: 36)
          .background(Color.secondary.opacity(0.15), in: Circle())
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text("chats.voice_message")
          .font(.caption.weight(.medium))
          .foregroundStyle(.primary)
        HStack(spacing: 2) {
          ForEach(0..<18, id: \.self) { i in
            RoundedRectangle(cornerRadius: 1)
              .fill(isPlaying ? MaxColor.accent : Color.secondary.opacity(0.5))
              .frame(width: 3, height: CGFloat(10 + (i % 3 == 0 ? 8 : (i % 2 == 0 ? 4 : -4))))
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    .onDisappear {
      avPlayer?.pause()
    }
  }
}

struct ScreenshotPreventingView<Content: View>: UIViewControllerRepresentable {
  let content: Content

  func makeUIViewController(context: Context) -> UIViewController {
    let controller = UIViewController()
    let textField = UITextField()
    textField.isSecureTextEntry = true
    textField.isUserInteractionEnabled = true
    
    let secureContainer = textField.subviews.first { String(describing: type(of: $0)).contains("Canvas") || String(describing: type(of: $0)).contains("Container") }
    let targetView = secureContainer ?? textField
    
    let hosting = UIHostingController(rootView: content)
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    hosting.view.backgroundColor = .clear
    targetView.addSubview(hosting.view)
    
    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: targetView.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: targetView.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: targetView.topAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: targetView.bottomAnchor)
    ])
    
    controller.view.addSubview(textField)
    textField.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      textField.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      textField.topAnchor.constraint(equalTo: controller.view.topAnchor),
      textField.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
    ])
    
    return controller
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
