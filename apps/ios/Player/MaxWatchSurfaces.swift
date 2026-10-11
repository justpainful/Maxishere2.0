import SwiftUI
import UIKit

// Watch Together — the feature surfaces around the player (spec §11): the
// invite/start sheet, settings, queue, vote, suggestions, history, scheduled
// sessions, the chat invite bubble, thread banners, and the terminal cards.
// The room protocol itself lives in WatchRoomStore; everything here is UI that
// turns taps into store intents and REST lookups.

// MARK: - Capability gate & invite message convention

extension MaxAppModel {
  /// One switch for every Watch Together entry point: the backend capability
  /// flag, and never in Demo Mode (realtime tickets do not exist there).
  var watchPartiesEnabled: Bool {
    !isDemoMode && (sessionStore.capabilities?.watchParties ?? false)
  }
}

/// The invite bubble travels as an ordinary chat message whose content is this
/// marker (the spec's `watch-invite` attachment, carried in content because
/// message attachments are media-only). The bubble resolves the LIVE room by
/// conversation (spec §10) — the marker deliberately carries no room id.
enum WatchInviteMessage {
  static let marker = "max://watch-invite"

  static func scheduledMarker(id: String) -> String {
    "\(marker)?scheduled=\(id)"
  }

  static func isInvite(_ content: String?) -> Bool {
    content?.hasPrefix(marker) == true
  }

  static func scheduledID(in content: String?) -> String? {
    guard let content, content.hasPrefix("\(marker)?scheduled=") else { return nil }
    let id = String(content.dropFirst("\(marker)?scheduled=".count))
    return id.isEmpty ? nil : id
  }
}

extension ChatMessage {
  var isWatchInvite: Bool { WatchInviteMessage.isInvite(content) }
  var watchInviteScheduledID: String? { WatchInviteMessage.scheduledID(in: content) }
}

/// RFC3339 in, Date out — the scheduled rows and guest links carry server
/// timestamps with or without fractional seconds.
func watchDate(_ iso: String?) -> Date? {
  guard let iso else { return nil }
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = fractional.date(from: iso) { return date }
  let plain = ISO8601DateFormatter()
  plain.formatOptions = [.withInternetDateTime]
  return plain.date(from: iso)
}

// MARK: - Start / invite context

/// What a Watch Together entry point wants: a specific media item (player,
/// context menus), a shuffle source (vertical feed), or a fixed conversation
/// (chat composer). The sheet fills in whatever is missing.
struct WatchStartContext: Identifiable, Hashable {
  let id = UUID()
  var mediaItem: MaxMediaItem? = nil
  var source: WatchSource? = nil
  var conversationID: String? = nil
}

// MARK: - Invite sheet (start a room, or invite into the live one)

/// Two modes in one surface. Outside a room: a conversation picker (the
/// PlayerSendToChatSheet pattern) that creates the room, drops the invite
/// bubble into the chat, and opens the player. Inside a room: seats, the
/// invite bubble resend, a nudge, and the host's guest links.
struct WatchInviteSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let context: WatchStartContext

  @State private var busyConversationID: String?
  @State private var didSendInvite = false

  private var store: WatchRoomStore { model.watchRoomStore }

  /// In-room mode: the sheet manages the live room's invitations instead of
  /// starting a new one.
  private var liveRoomConversationID: String? {
    guard store.isInRoom, let conversationID = store.room?.conversationId else { return nil }
    guard context.conversationID == nil || context.conversationID == conversationID else {
      return nil
    }
    return conversationID
  }

  var body: some View {
    NavigationStack {
      Group {
        if let conversationID = liveRoomConversationID {
          inRoomContent(conversationID: conversationID)
        } else {
          startContent
        }
      }
      .navigationTitle(liveRoomConversationID == nil ? "watch.start" : "watch.invite.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .accessibilityIdentifier("ui_watch_invite_sheet")
  }

  // MARK: Start mode

  @ViewBuilder
  private var startContent: some View {
    if let conversationID = context.conversationID {
      // Composer entry: the conversation is fixed, the media is what's missing.
      WatchMediaPickerList(
        onPick: { media in start(conversationID: conversationID, media: media) }
      )
      .overlay(alignment: .bottom) {
        if busyConversationID != nil { ProgressView().padding(MaxSpace.md) }
      }
    } else {
      conversationPicker
    }
  }

  private var conversationPicker: some View {
    ScrollView {
      LazyVStack(spacing: MaxSpace.sm) {
        if let errorMessage = store.errorMessage, busyConversationID == nil {
          Text(verbatim: errorMessage)
            .font(.caption)
            .foregroundStyle(MaxColor.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Text("watch.invite.pick_conversation")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if threads.isEmpty {
          if model.chatStore.threads.isLoading {
            HStack(spacing: MaxSpace.sm) {
              ProgressView()
              Text("chats.loading")
            }
            .frame(maxWidth: .infinity, minHeight: 100)
          } else {
            ContentUnavailableView(
              "chats.empty.title",
              systemImage: "bubble.left.and.bubble.right",
              description: Text("chats.empty.subtitle")
            )
          }
        } else {
          ForEach(threads) { thread in
            Button { start(conversationID: thread.id, media: context.mediaItem) } label: {
              HStack(spacing: MaxSpace.md) {
                MaxAvatar(name: thread.title, imageURL: thread.avatarUrl)
                VStack(alignment: .leading, spacing: MaxSpace.xxs) {
                  Text(verbatim: thread.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MaxColor.textPrimary)
                  Text("watch.start")
                    .font(.caption)
                    .foregroundStyle(MaxColor.textSecondary)
                }
                Spacer(minLength: 0)
                if busyConversationID == thread.id {
                  ProgressView()
                } else {
                  Image(systemName: "play.tv")
                    .foregroundStyle(MaxColor.accent)
                }
              }
              .padding(MaxSpace.md)
              .background(
                MaxColor.surface,
                in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
              )
            }
            .buttonStyle(.plain)
            .disabled(busyConversationID != nil)
            .accessibilityIdentifier("ui_watch_start_chat_\(thread.id.maxAccessibilityToken)")
          }
        }
      }
      .padding(MaxSpace.md)
    }
    .task {
      guard model.chatStore.threads.value == nil else { return }
      await model.chatStore.loadThreads(loadSelectedMessages: false)
    }
  }

  private var threads: [ChatThread] {
    model.chatStore.threads.value ?? []
  }

  /// The whole joining flow: lock gate → create (or join the existing room) →
  /// invite bubble into the chat → player in room mode.
  private func start(conversationID: String, media: MaxMediaItem?) {
    guard busyConversationID == nil else { return }
    busyConversationID = conversationID
    Task {
      defer { busyConversationID = nil }
      // Locked chats go through the existing chat-lock gate first (spec §11).
      if model.chatLockStore.needsUnlock(conversationID) {
        guard await model.chatLockStore.unlock(conversationID) else { return }
      }
      var room = await store.create(
        conversationID: conversationID,
        mediaID: media?.id,
        source: context.source
      )
      if room == nil {
        // WATCH_ROOM_EXISTS: one active room per conversation — join it instead.
        guard await store.joinActiveRoom(conversationID: conversationID) else { return }
        room = store.room
      }
      guard room != nil else { return }
      _ = await model.chatStore.sendMessage(
        to: conversationID,
        content: WatchInviteMessage.marker
      )
      dismiss()
      if let media = media ?? store.currentMediaItem {
        model.openPlayer(for: media)
      }
    }
  }

  // MARK: In-room mode

  private func inRoomContent(conversationID: String) -> some View {
    List {
      Section {
        HStack {
          Label("watch.invite.seats", systemImage: "person.2.fill")
          Spacer(minLength: 0)
          Text(verbatim: "\(store.participants.count)/\(store.settings.maxParticipants)")
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(MaxColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ui_watch_invite_seats")

        Button {
          guard !didSendInvite else { return }
          Task {
            let sent = await model.chatStore.sendMessage(
              to: conversationID,
              content: WatchInviteMessage.marker
            )
            didSendInvite = sent != nil
          }
        } label: {
          Label(
            didSendInvite ? "watch.invite.sent" : "watch.invite.send",
            systemImage: didSendInvite ? "checkmark.circle.fill" : "paperplane.fill"
          )
        }
        .disabled(didSendInvite)
        .accessibilityIdentifier("ui_watch_invite_send")

        Button {
          Task { await store.sendNudge() }
        } label: {
          Label("watch.nudge.send", systemImage: "hand.wave.fill")
        }
        .accessibilityIdentifier("ui_watch_invite_nudge")
      }

      if store.isHost {
        WatchGuestLinksSection()
      }
    }
    .scrollContentBackground(.hidden)
  }
}

// MARK: - Guest links (shared by invite + settings sheets, host only)

/// Create / copy / revoke external guest links — spec §8's `/w/{token}` pages.
struct WatchGuestLinksSection: View {
  @Environment(MaxAppModel.self) private var model

  @State private var isCreating = false
  @State private var copiedLinkID: String?

  private var store: WatchRoomStore { model.watchRoomStore }

  var body: some View {
    Section("watch.guest_links.title") {
      if store.guestLinks.isEmpty {
        Text("watch.guest_links.empty")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      ForEach(store.guestLinks) { link in
        HStack(spacing: MaxSpace.sm) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: displayURL(for: link))
              .font(.caption.monospaced())
              .lineLimit(1)
              .truncationMode(.middle)
            HStack(spacing: MaxSpace.xs) {
              if let expires = watchDate(link.expiresAt) {
                Text(
                  verbatim: String(
                    format: String(localized: "watch.guest_links.expires"),
                    expires.formatted(date: .abbreviated, time: .shortened)
                  )
                )
              }
              if let maxUses = link.maxUses {
                Text(verbatim: "\(link.useCount ?? 0)/\(maxUses)")
              }
            }
            .font(.caption2)
            .foregroundStyle(MaxColor.textSecondary)
          }
          Spacer(minLength: 0)
          Button {
            UIPasteboard.general.string = displayURL(for: link)
            copiedLinkID = link.id
          } label: {
            Label(
              copiedLinkID == link.id ? "watch.guest_links.copied" : "watch.guest_links.copy",
              systemImage: copiedLinkID == link.id ? "checkmark" : "doc.on.doc"
            )
            .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("ui_watch_guest_link_copy")
          Button(role: .destructive) {
            Task { await store.revokeGuestLink(linkID: link.id) }
          } label: {
            Label("watch.guest_links.revoke", systemImage: "trash")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("ui_watch_guest_link_revoke")
        }
      }
      Button {
        guard !isCreating else { return }
        isCreating = true
        Task {
          if let link = await store.createGuestLink() {
            UIPasteboard.general.string = displayURL(for: link)
            copiedLinkID = link.id
          }
          isCreating = false
        }
      } label: {
        if isCreating {
          ProgressView()
        } else {
          Label("watch.guest_links.create", systemImage: "link.badge.plus")
        }
      }
      .accessibilityIdentifier("ui_watch_guest_link_create")
    }
    .task { await store.loadGuestLinks() }
  }

  /// The server may answer a relative `/w/{token}` path; prefix the configured
  /// origin so the copied link works outside the app.
  private func displayURL(for link: WatchGuestLink) -> String {
    guard let url = link.url else { return "" }
    if url.hasPrefix("http") { return url }
    return model.serverURLString + url
  }
}

// MARK: - Media picker (queue add, vote options, composer start)

/// A lean searchable list over the loaded catalog — enough to hand one media
/// item back to whichever watch surface asked for it.
struct WatchMediaPickerList: View {
  @Environment(MaxAppModel.self) private var model

  let onPick: (MaxMediaItem) -> Void

  @State private var searchText = ""

  var body: some View {
    ScrollView {
      LazyVStack(spacing: MaxSpace.sm) {
        TextField("vault.search", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("ui_watch_media_search")

        if items.isEmpty {
          MaxEmptyState(
            title: "search.empty.title",
            subtitle: "search.empty.subtitle",
            symbol: "magnifyingglass"
          )
        }
        ForEach(items) { item in
          Button { onPick(item) } label: {
            HStack(spacing: MaxSpace.sm) {
              WatchMediaThumb(item: item, size: 44)
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(MaxColor.textPrimary)
                  .lineLimit(1)
                Text(verbatim: item.kind)
                  .font(.caption2)
                  .foregroundStyle(MaxColor.textSecondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "plus.circle.fill")
                .foregroundStyle(MaxColor.accent)
            }
            .padding(MaxSpace.sm)
            .background(
              MaxColor.surface,
              in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ui_watch_media_pick_\(item.id.maxAccessibilityToken)")
        }
      }
      .padding(MaxSpace.md)
    }
    .task {
      guard model.libraryStore.catalogPhase.value == nil else { return }
      await model.libraryStore.load(currentUserID: model.sessionStore.user?.id)
    }
  }

  private var items: [MaxMediaItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidates = model.libraryStore.catalogItems.filter { item in
      let mediaKind = item.kind.lowercased()
      return mediaKind == "video" || mediaKind == "image" || mediaKind == "audio"
    }
    guard !query.isEmpty else { return candidates }
    return candidates.filter { $0.title.localizedCaseInsensitiveContains(query) }
  }
}

/// A small poster thumbnail used across the watch sheets.
struct WatchMediaThumb: View {
  let item: MaxMediaItem?
  var size: CGFloat = 44

  var body: some View {
    MaxAsyncImage(url: item?.posterURL) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFill()
      } else {
        ZStack {
          Rectangle().fill(.quaternary)
          Image(systemName: "film")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(width: size * 1.55, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// Wraps the picker list in the house sheet chrome for standalone presentation.
struct WatchMediaPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  let onPick: (MaxMediaItem) -> Void

  var body: some View {
    NavigationStack {
      WatchMediaPickerList { media in
        dismiss()
        onPick(media)
      }
      .navigationTitle("watch.media.pick")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .accessibilityIdentifier("ui_watch_media_picker")
  }
}

// MARK: - Settings sheet

/// Every §4 row plus title/emoji, guest links and the danger zone. Rows write
/// straight through `PATCH settings` (one key per change); non-hosts see the
/// same rows disabled with the host-only footer, and the host's changes land
/// live through `watch.settings.updated` with a toast.
struct WatchSettingsSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var roomTitle = ""
  @State private var roomEmoji = ""
  @State private var showsEndConfirm = false
  @State private var toastText: String?

  private var store: WatchRoomStore { model.watchRoomStore }
  private var isHost: Bool { store.isHost }

  var body: some View {
    NavigationStack {
      List {
        metaSection
        controlSection
        playbackSection
        roomSection
        if isHost {
          WatchGuestLinksSection()
        }
        dangerSection
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("watch.settings.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .overlay(alignment: .bottom) {
      if let toastText {
        Text(verbatim: toastText)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, MaxSpace.md)
          .padding(.vertical, MaxSpace.xs)
          .background(.regularMaterial, in: Capsule())
          .padding(.bottom, MaxSpace.lg)
          .transition(.opacity)
          .accessibilityIdentifier("ui_watch_settings_toast")
      }
    }
    .onAppear {
      roomTitle = store.room?.title ?? ""
      roomEmoji = store.room?.emoji ?? ""
    }
    // Live updates: another host change re-renders the rows (they read the
    // store directly); non-hosts additionally get the toast.
    .onChange(of: store.settings) { _, _ in
      guard !isHost else { return }
      showToast(String(localized: "watch.settings.changed_toast"))
    }
    .onChange(of: store.room?.title) { _, fresh in
      if let fresh { roomTitle = fresh }
    }
    .onChange(of: store.room?.emoji) { _, fresh in
      if let fresh { roomEmoji = fresh }
    }
    .accessibilityIdentifier("ui_watch_settings_sheet")
  }

  private func showToast(_ text: String) {
    withAnimation { toastText = text }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation { toastText = nil }
    }
  }

  // MARK: Sections

  private var metaSection: some View {
    Section {
      TextField("watch.settings.room_title", text: $roomTitle)
        .disabled(!isHost)
        .accessibilityIdentifier("ui_watch_settings_title_field")
      TextField("watch.settings.room_emoji", text: $roomEmoji)
        .disabled(!isHost)
        .accessibilityIdentifier("ui_watch_settings_emoji_field")
      if isHost, metaChanged {
        Button("common.save") {
          Task {
            await store.updateMeta(
              title: roomTitle,
              emoji: String(roomEmoji.prefix(4))
            )
          }
        }
        .accessibilityIdentifier("ui_watch_settings_meta_save")
      }
    } footer: {
      if !isHost {
        Text("watch.settings.host_only")
      }
    }
  }

  private var metaChanged: Bool {
    roomTitle != (store.room?.title ?? "") || roomEmoji != (store.room?.emoji ?? "")
  }

  private var controlSection: some View {
    Section {
      Picker("watch.settings.who_can_control", selection: whoCanControlBinding) {
        Text("watch.settings.who_can_control.host").tag("host")
        Text("watch.settings.who_can_control.everyone").tag("everyone")
      }
      .accessibilityIdentifier("ui_watch_settings_who_can_control")
      Toggle(
        "watch.settings.queue_collaborative",
        isOn: boolBinding(\.queueCollaborative) { WatchSettingsPatch(queueCollaborative: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_queue_collaborative")
    }
    .disabled(!isHost)
  }

  private var playbackSection: some View {
    Section {
      Toggle(
        "watch.settings.wait_for_buffering",
        isOn: boolBinding(\.waitForBuffering) { WatchSettingsPatch(waitForBuffering: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_wait_for_buffering")
      Toggle(
        "watch.settings.auto_play_next",
        isOn: boolBinding(\.autoPlayNext) { WatchSettingsPatch(autoPlayNext: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_auto_play_next")
      Toggle(
        "watch.settings.loop",
        isOn: boolBinding(\.loop) { WatchSettingsPatch(loop: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_loop")
      Toggle(
        "watch.settings.countdown",
        isOn: boolBinding(\.countdownEnabled) { WatchSettingsPatch(countdownEnabled: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_countdown")
      Stepper(value: slideSecondsBinding, in: 2...30) {
        HStack {
          Text("watch.settings.slide_seconds")
          Spacer(minLength: 0)
          Text(verbatim: "\(store.settings.slideSeconds)s")
            .foregroundStyle(MaxColor.textSecondary)
            .monospacedDigit()
        }
      }
      .accessibilityIdentifier("ui_watch_settings_slide_seconds")
    }
    .disabled(!isHost)
  }

  private var roomSection: some View {
    Section {
      Toggle(
        "watch.settings.allow_mid_roll_join",
        isOn: boolBinding(\.allowMidRollJoin) { WatchSettingsPatch(allowMidRollJoin: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_mid_roll")
      Toggle(
        "watch.settings.chat_enabled",
        isOn: boolBinding(\.chatEnabled) { WatchSettingsPatch(chatEnabled: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_chat")
      Toggle(
        "watch.settings.reactions_enabled",
        isOn: boolBinding(\.reactionsEnabled) { WatchSettingsPatch(reactionsEnabled: $0) }
      )
      .accessibilityIdentifier("ui_watch_settings_reactions")
      Stepper(value: maxParticipantsBinding, in: 2...10) {
        HStack {
          Text("watch.settings.max_participants")
          Spacer(minLength: 0)
          Text(verbatim: "\(store.settings.maxParticipants)")
            .foregroundStyle(MaxColor.textSecondary)
            .monospacedDigit()
        }
      }
      .accessibilityIdentifier("ui_watch_settings_max_participants")
    }
    .disabled(!isHost)
  }

  private var dangerSection: some View {
    Section("watch.settings.danger") {
      if isHost {
        Button(role: .destructive) {
          showsEndConfirm = true
        } label: {
          Label("watch.end", systemImage: "xmark.octagon.fill")
        }
        .confirmationDialog(
          "watch.end.confirm",
          isPresented: $showsEndConfirm,
          titleVisibility: .visible
        ) {
          Button("watch.end", role: .destructive) {
            Task {
              await store.end()
              dismiss()
            }
          }
          Button("common.cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("ui_watch_settings_end")
      } else {
        Button(role: .destructive) {
          Task {
            await store.leave()
            dismiss()
          }
        } label: {
          Label("watch.leave", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("ui_watch_settings_leave")
      }
    }
  }

  // MARK: Write-through bindings

  private func boolBinding(
    _ keyPath: KeyPath<WatchSettings, Bool>,
    patch: @escaping (Bool) -> WatchSettingsPatch
  ) -> Binding<Bool> {
    Binding(
      get: { store.settings[keyPath: keyPath] },
      set: { value in Task { await store.updateSettings(patch(value)) } }
    )
  }

  private var whoCanControlBinding: Binding<String> {
    Binding(
      get: { store.settings.whoCanControl },
      set: { value in
        Task { await store.updateSettings(WatchSettingsPatch(whoCanControl: value)) }
      }
    )
  }

  private var slideSecondsBinding: Binding<Int> {
    Binding(
      get: { store.settings.slideSeconds },
      set: { value in
        Task { await store.updateSettings(WatchSettingsPatch(slideSeconds: value)) }
      }
    )
  }

  private var maxParticipantsBinding: Binding<Int> {
    Binding(
      get: { store.settings.maxParticipants },
      set: { value in
        Task { await store.updateSettings(WatchSettingsPatch(maxParticipants: value)) }
      }
    )
  }
}

// MARK: - Queue sheet (+ suggestions)

/// The room's collaborative queue: anyone may add when `queueCollaborative`,
/// controllers manage (remove, reorder via replace); viewers' suggestions land
/// here for controllers to play or enqueue.
struct WatchQueueSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var showsMediaPicker = false
  @State private var resolvedTitles: [String: MaxMediaItem] = [:]

  private var store: WatchRoomStore { model.watchRoomStore }
  private var canManage: Bool { store.canControl }
  private var canAdd: Bool { store.canControl || store.settings.queueCollaborative }

  private var orderedQueue: [WatchQueueItem] {
    store.queue.sorted { $0.position < $1.position }
  }

  // Extracted with an explicit ToolbarContent type: inline, the closure kept
  // tripping "ambiguous use of toolbar(content:)" on the CI toolchain, and the
  // explicit builder pins the overload (and localizes any future type error).
  @ToolbarContentBuilder
  private var queueToolbar: some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
      Button("common.done") { dismiss() }
    }
    ToolbarItem(placement: .topBarLeading) {
      if canManage, !orderedQueue.isEmpty { EditButton() }
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if orderedQueue.isEmpty {
            Text("watch.queue.empty")
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
          }
          ForEach(orderedQueue) { entry in
            queueRow(entry)
          }
          // Always-attached with an internal guard: the conditional
          // `canManage ? method : nil` passes an unapplied MainActor method
          // reference, which Swift 6 strict concurrency rejects — and the
          // rejection surfaces as a bogus toolbar-overload ambiguity.
          .onDelete { offsets in
            if canManage { deleteItems(at: offsets) }
          }
          .onMove { source, destination in
            if canManage { moveItems(from: source, to: destination) }
          }

          if canAdd {
            Button {
              showsMediaPicker = true
            } label: {
              Label("watch.queue.add", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("ui_watch_queue_add")
          }
        }

        suggestionsSection
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("watch.queue.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { queueToolbar }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .sheet(isPresented: $showsMediaPicker) {
      WatchMediaPickerSheet { media in
        Task { await store.addToQueue(mediaID: media.id) }
      }
    }
    .task(id: store.queue.map(\.mediaId) + store.suggestions.map(\.mediaId)) {
      await resolveTitles()
    }
    .accessibilityIdentifier("ui_watch_queue_sheet")
  }

  private func queueRow(_ entry: WatchQueueItem) -> some View {
    let media = resolvedTitles[entry.mediaId]
    return HStack(spacing: MaxSpace.sm) {
      WatchMediaThumb(item: media, size: 40)
      Text(verbatim: media?.displayTitle ?? entry.mediaId)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 0)
      if canManage {
        Button {
          Task {
            await store.changeMedia(mediaID: entry.mediaId, source: store.room?.source)
            await store.removeQueueItem(index: entry.position)
            await store.play(atPosition: 0)
          }
        } label: {
          Image(systemName: "play.circle.fill")
            .foregroundStyle(MaxColor.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("action.play"))
      }
    }
    .accessibilityIdentifier("ui_watch_queue_row_\(entry.position)")
  }

  private func deleteItems(at offsets: IndexSet) {
    let doomed = offsets.map { orderedQueue[$0].position }
    Task {
      // Highest index first so earlier removals don't shift later ones.
      for position in doomed.sorted(by: >) {
        await store.removeQueueItem(index: position)
      }
    }
  }

  private func moveItems(from source: IndexSet, to destination: Int) {
    var ids = orderedQueue.map(\.mediaId)
    ids.move(fromOffsets: source, toOffset: destination)
    Task { await store.replaceQueue(mediaIDs: ids) }
  }

  @ViewBuilder
  private var suggestionsSection: some View {
    Section("watch.suggest.title") {
      if store.suggestions.isEmpty {
        Text("watch.suggest.empty")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      ForEach(Array(store.suggestions.enumerated()), id: \.offset) { _, suggestion in
        let media = resolvedTitles[suggestion.mediaId]
        HStack(spacing: MaxSpace.sm) {
          WatchMediaThumb(item: media, size: 40)
          Text(verbatim: media?.displayTitle ?? suggestion.mediaId)
            .font(.subheadline)
            .lineLimit(1)
          Spacer(minLength: 0)
          if canManage {
            Button {
              Task {
                await store.changeMedia(mediaID: suggestion.mediaId)
                await store.play(atPosition: 0)
              }
            } label: {
              Text("watch.suggest.play")
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
              Task { await store.addToQueue(mediaID: suggestion.mediaId) }
            } label: {
              Image(systemName: "text.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text("watch.queue.add"))
          }
        }
      }
    }
  }

  private func resolveTitles() async {
    let ids = Set(store.queue.map(\.mediaId) + store.suggestions.map(\.mediaId))
    for id in ids where resolvedTitles[id] == nil {
      resolvedTitles[id] = await model.resolveMediaItem(id: id)
    }
  }
}

// MARK: - Vote sheet

/// "What do we watch": controllers start a 2–6 option vote, everyone casts,
/// the tally and countdown ride `watch.vote.updated`, and the host client
/// plays the winner when it closes (already a store duty).
struct WatchVoteSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  @State private var draftOptions: [MaxMediaItem] = []
  @State private var draftSeconds = 30
  @State private var showsMediaPicker = false
  @State private var resolvedTitles: [String: MaxMediaItem] = [:]
  @State private var myVoteIndex: Int?

  private var store: WatchRoomStore { model.watchRoomStore }

  private static let durationChoices = [15, 30, 60, 120]

  var body: some View {
    NavigationStack {
      Group {
        if let vote = store.activeVote {
          tallyList(vote)
        } else if store.canControl {
          startForm
        } else {
          ContentUnavailableView(
            "watch.vote.none",
            systemImage: "checklist",
            description: Text("watch.vote.title")
          )
        }
      }
      .navigationTitle("watch.vote.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .sheet(isPresented: $showsMediaPicker) {
      WatchMediaPickerSheet { media in
        guard draftOptions.count < 6,
              !draftOptions.contains(where: { $0.id == media.id }) else { return }
        draftOptions.append(media)
      }
    }
    .task(id: store.activeVote?.options) {
      guard let options = store.activeVote?.options else { return }
      for id in options where resolvedTitles[id] == nil {
        resolvedTitles[id] = await model.resolveMediaItem(id: id)
      }
    }
    .accessibilityIdentifier("ui_watch_vote_sheet")
  }

  // MARK: Live tally

  private func tallyList(_ vote: WatchVote) -> some View {
    List {
      Section {
        if vote.closed {
          Label("watch.vote.closed", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
        } else if let endsAt = vote.endsAt {
          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let remaining = max((endsAt - store.serverNowMs()) / 1000, 0)
            Label(
              String(
                format: String(localized: "watch.vote.closes_in"),
                remaining.watchClockString
              ),
              systemImage: "timer"
            )
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
          }
        }
      }

      Section {
        ForEach(Array(vote.options.enumerated()), id: \.offset) { index, mediaID in
          voteRow(vote: vote, index: index, mediaID: mediaID)
        }
      }

      if store.canControl, !vote.closed {
        Section {
          Button(role: .destructive) {
            Task { await store.endVote() }
          } label: {
            Label("watch.vote.end", systemImage: "flag.checkered")
          }
          .accessibilityIdentifier("ui_watch_vote_end")
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func voteRow(vote: WatchVote, index: Int, mediaID: String) -> some View {
    let media = resolvedTitles[mediaID]
    let count = vote.counts.indices.contains(index) ? vote.counts[index] : 0
    let isWinner = vote.closed && vote.winnerIndex == index
    return HStack(spacing: MaxSpace.sm) {
      WatchMediaThumb(item: media, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: media?.displayTitle ?? mediaID)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        if isWinner {
          Label("watch.vote.winner", systemImage: "crown.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MaxColor.accent)
        }
      }
      Spacer(minLength: 0)
      Text(verbatim: "\(count)")
        .font(.body.monospacedDigit().weight(.bold))
        .contentTransition(.numericText())
      if !vote.closed {
        Button {
          myVoteIndex = index
          Task { await store.castVote(optionIndex: index) }
        } label: {
          Image(systemName: myVoteIndex == index ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(MaxColor.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("watch.vote.cast"))
        .accessibilityIdentifier("ui_watch_vote_cast_\(index)")
      }
    }
  }

  // MARK: Start form (controller*)

  private var startForm: some View {
    List {
      Section {
        Text("watch.vote.options_hint")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
        ForEach(draftOptions) { option in
          HStack(spacing: MaxSpace.sm) {
            WatchMediaThumb(item: option, size: 40)
            Text(verbatim: option.displayTitle)
              .font(.subheadline)
              .lineLimit(1)
            Spacer(minLength: 0)
            Button {
              draftOptions.removeAll { $0.id == option.id }
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
          }
        }
        if draftOptions.count < 6 {
          Button {
            showsMediaPicker = true
          } label: {
            Label("watch.media.pick", systemImage: "plus.circle.fill")
          }
          .accessibilityIdentifier("ui_watch_vote_add_option")
        }
      }

      Section {
        Picker("watch.vote.duration", selection: $draftSeconds) {
          ForEach(Self.durationChoices, id: \.self) { seconds in
            Text(verbatim: "\(seconds)s").tag(seconds)
          }
        }
        .accessibilityIdentifier("ui_watch_vote_duration")

        Button {
          let ids = draftOptions.map(\.id)
          Task {
            await store.startVote(mediaIDs: ids, seconds: draftSeconds)
          }
        } label: {
          Label("watch.vote.start", systemImage: "checklist")
        }
        .disabled(draftOptions.count < 2)
        .accessibilityIdentifier("ui_watch_vote_start")
      }
    }
    .scrollContentBackground(.hidden)
  }
}

// MARK: - History sheet

/// Ended sessions for a conversation, newest first: the aggregate stats card,
/// the reaction-timeline sparkline, and "resume" which reopens a room from the
/// ended session's final position (`resumeFromRoomId`).
struct WatchHistorySheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let conversationID: String

  @State private var resumingID: String?
  @State private var resolvedTitles: [String: MaxMediaItem] = [:]

  private var store: WatchRoomStore { model.watchRoomStore }
  private var entries: [WatchHistoryEntry] {
    store.historyByConversation[conversationID] ?? []
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: MaxSpace.md) {
          if entries.isEmpty {
            MaxEmptyState(
              title: "watch.history.empty",
              subtitle: "watch.history.title",
              symbol: "play.tv"
            )
          }
          ForEach(entries) { entry in
            historyCard(entry)
          }
        }
        .padding(MaxSpace.md)
      }
      .navigationTitle("watch.history.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .task {
      await store.loadHistory(conversationID: conversationID)
      for entry in entries {
        guard let mediaID = entry.mediaId, resolvedTitles[mediaID] == nil else { continue }
        resolvedTitles[mediaID] = await model.resolveMediaItem(id: mediaID)
      }
    }
    .accessibilityIdentifier("ui_watch_history_sheet")
  }

  private func historyCard(_ entry: WatchHistoryEntry) -> some View {
    MaxContentSurface(padding: MaxSpace.md) {
      VStack(alignment: .leading, spacing: MaxSpace.sm) {
        HStack(spacing: MaxSpace.sm) {
          WatchMediaThumb(item: entry.mediaId.flatMap { resolvedTitles[$0] }, size: 40)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: displayTitle(for: entry))
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            if let ended = watchDate(entry.endedAt) {
              Text(verbatim: ended.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(MaxColor.textSecondary)
            }
          }
          Spacer(minLength: 0)
        }

        if let stats = entry.stats {
          WatchStatsSummaryRow(stats: stats)
          if let bins = stats.reactionBins, bins.contains(where: { $0 > 0 }) {
            WatchReactionBinsSparkline(bins: bins)
              .fill(MaxColor.accent.opacity(0.45))
              .frame(height: 26)
              .accessibilityHidden(true)
          }
        }

        Button {
          resume(entry)
        } label: {
          if resumingID == entry.id {
            ProgressView()
          } else {
            Label("watch.history.resume", systemImage: "play.fill")
              .font(.subheadline.weight(.semibold))
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(resumingID != nil)
        .accessibilityIdentifier("ui_watch_history_resume")
      }
    }
  }

  private func displayTitle(for entry: WatchHistoryEntry) -> String {
    let title = entry.title.isEmpty
      ? (entry.mediaId.flatMap { resolvedTitles[$0]?.displayTitle }
         ?? String(localized: "watch.history.title"))
      : entry.title
    return entry.emoji.isEmpty ? title : "\(entry.emoji) \(title)"
  }

  private func resume(_ entry: WatchHistoryEntry) {
    guard resumingID == nil else { return }
    resumingID = entry.id
    Task {
      defer { resumingID = nil }
      guard let room = await store.create(
        conversationID: conversationID,
        resumeFromRoomID: entry.id
      ) else { return }
      _ = await model.chatStore.sendMessage(
        to: conversationID,
        content: WatchInviteMessage.marker
      )
      dismiss()
      if let mediaID = room.mediaId, let media = await model.resolveMediaItem(id: mediaID) {
        model.openPlayer(for: media)
      }
    }
  }
}

/// The aggregate numbers of an ended session (spec: aggregate-only, never
/// per-user), shared by the history card and the ended terminal card.
struct WatchStatsSummaryRow: View {
  let stats: WatchRoomStats

  var body: some View {
    HStack(spacing: MaxSpace.md) {
      statChip(
        label: "watch.ended.stats.duration",
        value: (stats.durationSeconds ?? 0).watchClockString,
        symbol: "clock"
      )
      statChip(
        label: "watch.ended.stats.participants",
        value: "\(stats.participantCount ?? 0)",
        symbol: "person.2"
      )
      statChip(
        label: "watch.ended.stats.reactions",
        value: "\(stats.reactionCount ?? 0)",
        symbol: "heart"
      )
      statChip(
        label: "watch.ended.stats.messages",
        value: "\(stats.messageCount ?? 0)",
        symbol: "bubble.left"
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func statChip(
    label: LocalizedStringKey,
    value: String,
    symbol: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 3) {
        Image(systemName: symbol)
          .font(.caption2)
          .accessibilityHidden(true)
        Text(verbatim: value)
          .font(.caption.monospacedDigit().weight(.bold))
      }
      Text(label)
        .font(.caption2)
        .foregroundStyle(MaxColor.textSecondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The reaction-position histogram as a filled area — one point per bin,
/// closed along the baseline, exactly the PlayerHeatArea construction.
struct WatchReactionBinsSparkline: Shape {
  let bins: [Int]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard !bins.isEmpty, rect.width > 0, rect.height > 0 else { return path }
    let peak = max(bins.max() ?? 1, 1)
    let count = CGFloat(bins.count)
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    for (index, value) in bins.enumerated() {
      let x = rect.minX + rect.width * (CGFloat(index) + 0.5) / count
      let clamped = CGFloat(min(max(Double(value) / Double(peak), 0), 1))
      path.addLine(to: CGPoint(x: x, y: rect.maxY - clamped * rect.height))
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

// MARK: - Scheduled sheet

/// "فيلم الجمعة 9م": create, list and cancel scheduled watch parties. The
/// worker reminds at T-10 and auto-starts the room; the reminder banner in the
/// thread comes from `watch.scheduled.reminder` via the store.
struct WatchScheduledSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let conversationID: String

  @State private var draftDate = Date().addingTimeInterval(3600)
  @State private var draftTitle = ""
  @State private var draftEmoji = ""
  @State private var draftMedia: MaxMediaItem?
  @State private var showsMediaPicker = false
  @State private var isCreating = false

  private var store: WatchRoomStore { model.watchRoomStore }
  private var entries: [WatchScheduledEntry] {
    (store.scheduledByConversation[conversationID] ?? [])
      .filter { $0.canceledAt == nil && $0.startedRoomId == nil }
  }

  var body: some View {
    NavigationStack {
      List {
        upcomingSection
        createSection
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("watch.scheduled.title")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("common.done", action: dismiss.callAsFunction)
        }
      }
      .maxScreenBackground()
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .sheet(isPresented: $showsMediaPicker) {
      WatchMediaPickerSheet { media in draftMedia = media }
    }
    .task { await store.loadScheduled(conversationID: conversationID) }
    .accessibilityIdentifier("ui_watch_scheduled_sheet")
  }

  private var upcomingSection: some View {
    Section {
      if entries.isEmpty {
        Text("watch.scheduled.empty")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      ForEach(entries) { entry in
        HStack(spacing: MaxSpace.sm) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entryTitle(entry))
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            if let date = watchDate(entry.scheduledAt) {
              Text(verbatim: date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(MaxColor.textSecondary)
            }
          }
          Spacer(minLength: 0)
          if entry.createdBy == nil || entry.createdBy == store.myUserID
              || entry.createdBy == model.sessionStore.user?.id {
            Button(role: .destructive) {
              Task {
                await store.cancelScheduled(id: entry.id, conversationID: conversationID)
              }
            } label: {
              Text("watch.scheduled.cancel")
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("ui_watch_scheduled_cancel")
          }
        }
      }
    }
  }

  private func entryTitle(_ entry: WatchScheduledEntry) -> String {
    let title = entry.title.isEmpty
      ? String(localized: "watch.invite.scheduled")
      : entry.title
    return entry.emoji.isEmpty ? title : "\(entry.emoji) \(title)"
  }

  private var createSection: some View {
    Section("watch.scheduled.create") {
      DatePicker(
        "watch.scheduled.when",
        selection: $draftDate,
        in: Date()...,
        displayedComponents: [.date, .hourAndMinute]
      )
      .accessibilityIdentifier("ui_watch_scheduled_date")
      TextField("watch.settings.room_title", text: $draftTitle)
      TextField("watch.settings.room_emoji", text: $draftEmoji)
      Button {
        showsMediaPicker = true
      } label: {
        HStack {
          Label("watch.media.pick", systemImage: "film")
          Spacer(minLength: 0)
          if let draftMedia {
            Text(verbatim: draftMedia.displayTitle)
              .font(.caption)
              .foregroundStyle(MaxColor.textSecondary)
              .lineLimit(1)
          }
        }
      }
      .accessibilityIdentifier("ui_watch_scheduled_media")
      Button {
        create()
      } label: {
        if isCreating {
          ProgressView()
        } else {
          Label("watch.scheduled.create", systemImage: "calendar.badge.plus")
        }
      }
      .disabled(isCreating || draftDate <= Date())
      .accessibilityIdentifier("ui_watch_scheduled_submit")
    }
  }

  private func create() {
    guard !isCreating else { return }
    isCreating = true
    Task {
      defer { isCreating = false }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      let entry = await store.schedule(
        conversationID: conversationID,
        scheduledAt: formatter.string(from: draftDate),
        title: draftTitle.isEmpty ? nil : draftTitle,
        emoji: draftEmoji.isEmpty ? nil : String(draftEmoji.prefix(4)),
        mediaID: draftMedia?.id
      )
      guard let entry else { return }
      // The worker never posts a chat message (spec §10); the scheduled invite
      // bubble is the client's to drop.
      _ = await model.chatStore.sendMessage(
        to: conversationID,
        content: WatchInviteMessage.scheduledMarker(id: entry.id)
      )
      draftTitle = ""
      draftEmoji = ""
      draftMedia = nil
    }
  }
}

// MARK: - Invite bubble (rendered inside ChatKitBubble)

/// The `watch-invite` card: poster + title + live occupancy, with the state
/// machine the spec asks for — live / full / ended (+stats & resume) /
/// unavailable / scheduled — resolved by conversation, never by a baked-in
/// room id.
struct WatchInviteBubbleView: View {
  @Environment(MaxAppModel.self) private var model

  let conversationID: String
  let scheduledID: String?

  private enum Phase: Equatable {
    case loading
    case live(WatchRoom)
    case full(WatchRoom)
    case ended(WatchHistoryEntry?)
    case unavailable
    case scheduled(WatchScheduledEntry?)
  }

  @State private var phase: Phase = .loading
  @State private var media: MaxMediaItem?
  @State private var isJoining = false
  @State private var joinError: String?

  private var store: WatchRoomStore { model.watchRoomStore }

  /// Re-runs the lookup whenever the room world moves for this conversation.
  private var refreshKey: String {
    [
      conversationID,
      scheduledID ?? "",
      store.lastRoomCreated?.roomId ?? "",
      store.endedEvent?.roomId ?? "",
      store.room?.id ?? "",
    ].joined(separator: "|")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MaxSpace.xs) {
      HStack(spacing: MaxSpace.sm) {
        WatchMediaThumb(item: media, size: 44)
        VStack(alignment: .leading, spacing: 2) {
          Label(titleText, systemImage: "play.tv.fill")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
          if let subtitle = subtitleText {
            Text(verbatim: subtitle)
              .font(.caption)
              .opacity(0.85)
          }
        }
      }

      if case .ended(let entry) = phase, let stats = entry?.stats {
        WatchStatsSummaryRow(stats: stats)
      }

      actionRow

      if let joinError {
        Text(verbatim: joinError)
          .font(.caption2)
          .foregroundStyle(MaxColor.warning)
      }
    }
    .frame(maxWidth: 250, alignment: .leading)
    .task(id: refreshKey) { await refresh() }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("ui_watch_invite_bubble")
  }

  private var titleText: LocalizedStringKey {
    switch phase {
    case .loading: "watch.invite.title"
    case .live: "watch.invite.live"
    case .full: "watch.invite.full"
    case .ended: "watch.invite.ended"
    case .unavailable: "watch.invite.unavailable"
    case .scheduled: "watch.invite.scheduled"
    }
  }

  private var subtitleText: String? {
    switch phase {
    case .live(let room), .full(let room):
      let count = room.participants?.count ?? 0
      var line = String(
        format: String(localized: "watch.invite.watching"),
        "\(count)"
      )
      if !room.title.isEmpty {
        line = "\(room.emoji.isEmpty ? "" : room.emoji + " ")\(room.title) · \(line)"
      }
      return line
    case .scheduled(let entry):
      guard let date = watchDate(entry?.scheduledAt) else { return nil }
      return date.formatted(date: .abbreviated, time: .shortened)
    case .loading, .ended, .unavailable:
      return media?.displayTitle
    }
  }

  @ViewBuilder
  private var actionRow: some View {
    switch phase {
    case .live(let room):
      if store.isInRoom, store.room?.id == room.id {
        Button {
          if let media = store.currentMediaItem { model.openPlayer(for: media) }
        } label: {
          Label("watch.invite.return", systemImage: "arrow.uturn.forward")
            .font(.caption.weight(.bold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityIdentifier("ui_watch_invite_return")
      } else {
        Button {
          join(room)
        } label: {
          if isJoining {
            ProgressView()
          } else {
            Label("watch.join", systemImage: "play.fill")
              .font(.caption.weight(.bold))
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isJoining)
        .accessibilityIdentifier("ui_watch_invite_join")
      }
    case .full:
      Label("watch.error.room_full", systemImage: "person.2.slash")
        .font(.caption2)
        .opacity(0.8)
    case .unavailable:
      // Media-unavailable keeps the person in the conversation — no dead join
      // button, just the stay-in-chat line.
      Label("watch.invite.stay", systemImage: "bubble.left.fill")
        .font(.caption2)
        .opacity(0.8)
    case .loading, .ended, .scheduled:
      EmptyView()
    }
  }

  private func refresh() async {
    if let scheduledID {
      await store.loadScheduled(conversationID: conversationID)
      let entry = store.scheduledByConversation[conversationID]?
        .first { $0.id == scheduledID }
      if let entry, entry.startedRoomId == nil, entry.canceledAt == nil {
        phase = .scheduled(entry)
        if let mediaID = entry.mediaId {
          media = await model.resolveMediaItem(id: mediaID)
        }
        return
      }
      // A started (or canceled) plan falls through to the live-room lookup.
    }
    do {
      let room = try await model.apiClient.activeWatchRoom(conversationID: conversationID)
      let seats = room.settings?.maxParticipants ?? WatchSettings.defaults.maxParticipants
      let occupied = room.participants?.count ?? 0
      let mine = store.isInRoom && store.room?.id == room.id
      phase = (occupied >= seats && !mine) ? .full(room) : .live(room)
      if let mediaID = room.mediaId {
        media = await model.resolveMediaItem(id: mediaID)
      }
    } catch MaxAPIError.server(let status, _) where status == 404 {
      // No live room: the invite points at an ended session — surface its
      // closing stats and let history power "resume" from the thread menu.
      await store.loadHistory(conversationID: conversationID, limit: 1)
      phase = .ended(store.historyByConversation[conversationID]?.first)
      if let mediaID = store.historyByConversation[conversationID]?.first?.mediaId {
        media = await model.resolveMediaItem(id: mediaID)
      }
    } catch {
      phase = .unavailable
    }
  }

  private func join(_ room: WatchRoom) {
    guard !isJoining else { return }
    isJoining = true
    joinError = nil
    Task {
      defer { isJoining = false }
      // The thread already passed the chat-lock gate; double-locked chats never
      // rendered this bubble in the first place.
      guard await store.join(roomID: room.id) else {
        joinError = store.errorMessage
        await refresh()
        return
      }
      var media = store.currentMediaItem
      if media == nil, let mediaID = room.mediaId {
        media = await model.resolveMediaItem(id: mediaID)
      }
      if let media { model.openPlayer(for: media) }
    }
  }
}

// MARK: - Thread banners (live room + scheduled reminder)

/// Sits above the thread's message list: a "watch party live · join" strip
/// when the conversation has an active room, and the T-10 reminder banner fed
/// by `watch.scheduled.reminder`.
struct WatchThreadBanner: View {
  @Environment(MaxAppModel.self) private var model

  let conversationID: String

  @State private var liveRoom: WatchRoom?
  @State private var isJoining = false

  private var store: WatchRoomStore { model.watchRoomStore }

  private var reminder: WatchScheduledReminderEvent? {
    guard let event = store.lastScheduledReminder,
          event.conversationId == conversationID else { return nil }
    return event
  }

  /// The room store's socket only runs while inside a room, so the T-10 event
  /// can be missed; a plan due inside 10 minutes banners from the list too.
  private var dueSoonEntry: WatchScheduledEntry? {
    let rows = store.scheduledByConversation[conversationID] ?? []
    return rows.first { entry in
      guard entry.canceledAt == nil, entry.startedRoomId == nil,
            let date = watchDate(entry.scheduledAt) else { return false }
      let remaining = date.timeIntervalSinceNow
      return remaining > 0 && remaining <= 600
    }
  }

  private var refreshKey: String {
    [
      conversationID,
      store.lastRoomCreated?.roomId ?? "",
      store.endedEvent?.roomId ?? "",
      store.room?.id ?? "",
    ].joined(separator: "|")
  }

  var body: some View {
    // The VStack itself always mounts (zero-size when empty) so the lookup
    // task keeps running; padding lives on the rows to avoid a phantom strip.
    VStack(spacing: MaxSpace.xs) {
      if let reminder {
        reminderBanner(reminder)
      } else if let entry = dueSoonEntry {
        scheduledBanner(entry)
      }
      if let liveRoom {
        liveBanner(liveRoom)
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(
      .top,
      (reminder != nil || dueSoonEntry != nil || liveRoom != nil) ? MaxSpace.xs : 0
    )
    .task(id: refreshKey) {
      await store.loadScheduled(conversationID: conversationID)
      liveRoom = try? await model.apiClient.activeWatchRoom(conversationID: conversationID)
    }
  }

  private func scheduledBanner(_ entry: WatchScheduledEntry) -> some View {
    let minutes = watchDate(entry.scheduledAt)
      .map { max(Int(($0.timeIntervalSinceNow / 60).rounded(.up)), 1) } ?? 10
    return HStack(spacing: MaxSpace.sm) {
      Image(systemName: "calendar.badge.clock")
        .foregroundStyle(MaxColor.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: entry.title.isEmpty
          ? String(localized: "watch.invite.scheduled")
          : "\(entry.emoji.isEmpty ? "" : entry.emoji + " ")\(entry.title)")
          .font(.caption.weight(.semibold))
        Text(
          verbatim: String(
            format: String(localized: "watch.scheduled.reminder"),
            "\(minutes)"
          )
        )
        .font(.caption2)
        .foregroundStyle(MaxColor.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("ui_watch_scheduled_banner")
  }

  private func reminderBanner(_ event: WatchScheduledReminderEvent) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "calendar.badge.clock")
        .foregroundStyle(MaxColor.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: event.title.isEmpty
          ? String(localized: "watch.invite.scheduled")
          : "\(event.emoji.isEmpty ? "" : event.emoji + " ")\(event.title)")
          .font(.caption.weight(.semibold))
        Text(
          verbatim: String(
            format: String(localized: "watch.scheduled.reminder"),
            "\(event.minutesLeft ?? 10)"
          )
        )
        .font(.caption2)
        .foregroundStyle(MaxColor.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("ui_watch_reminder_banner")
  }

  private func liveBanner(_ room: WatchRoom) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "play.tv.fill")
        .foregroundStyle(MaxColor.accent)
        .accessibilityHidden(true)
      Text("watch.invite.live")
        .font(.caption.weight(.semibold))
      Text(verbatim: "\(room.participants?.count ?? 0)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(MaxColor.textSecondary)
      Spacer(minLength: 0)
      Button {
        joinLive(room)
      } label: {
        if isJoining {
          ProgressView()
        } else {
          Text(store.isInRoom && store.room?.id == room.id
            ? "watch.invite.return"
            : "watch.join")
            .font(.caption.weight(.bold))
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(isJoining)
      .accessibilityIdentifier("ui_watch_live_banner_join")
    }
    .padding(MaxSpace.sm)
    .background(
      MaxColor.surface,
      in: RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
    )
    .accessibilityIdentifier("ui_watch_live_banner")
  }

  private func joinLive(_ room: WatchRoom) {
    guard !isJoining else { return }
    if store.isInRoom, store.room?.id == room.id {
      if let media = store.currentMediaItem { model.openPlayer(for: media) }
      return
    }
    isJoining = true
    Task {
      defer { isJoining = false }
      guard await store.join(roomID: room.id) else { return }
      if let media = store.currentMediaItem { model.openPlayer(for: media) }
    }
  }
}

// MARK: - Terminal cards (ended / kicked)

/// The opaque full-card states the room can end in while the player is up.
/// Ended: stats + resume + keep-watching-solo. Kicked: keep-solo only (the
/// kick is soft — the invite bubble can readmit).
struct WatchTerminalCard: View {
  @Environment(MaxAppModel.self) private var model

  /// nil = kicked; non-nil = the room-ended event with its stats.
  let endedEvent: WatchRoomEndedEvent?
  let onDismiss: () -> Void
  let onClose: () -> Void

  @State private var isResuming = false

  private var store: WatchRoomStore { model.watchRoomStore }

  var body: some View {
    VStack(spacing: MaxSpace.md) {
      Image(systemName: endedEvent == nil ? "person.fill.xmark" : "flag.checkered")
        .font(.largeTitle)
        .foregroundStyle(.white)
        .accessibilityHidden(true)

      Text(endedEvent == nil ? "watch.kicked.title" : "watch.ended.title")
        .font(.headline)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)

      if endedEvent == nil {
        Text("watch.kicked.subtitle")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.75))
          .multilineTextAlignment(.center)
      }

      if let stats = endedEvent?.stats {
        WatchStatsSummaryRow(stats: stats)
          .foregroundStyle(.white)
        if let bins = stats.reactionBins, bins.contains(where: { $0 > 0 }) {
          WatchReactionBinsSparkline(bins: bins)
            .fill(MaxColor.accent.opacity(0.55))
            .frame(height: 26)
            .accessibilityHidden(true)
        }
      }

      VStack(spacing: MaxSpace.sm) {
        if let endedEvent, let conversationID = store.room?.conversationId {
          Button {
            resume(roomID: endedEvent.roomId, conversationID: conversationID)
          } label: {
            if isResuming {
              ProgressView()
            } else {
              Label("watch.history.resume", systemImage: "play.fill")
            }
          }
          .buttonStyle(.glassProminent)
          .disabled(isResuming)
          .accessibilityIdentifier("ui_watch_ended_resume")
        }
        Button("watch.ended.keep_watching", action: onDismiss)
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_watch_ended_solo")
        Button("action.close", action: onClose)
          .buttonStyle(.glass)
          .accessibilityIdentifier("ui_watch_ended_close")
      }
    }
    .padding(MaxSpace.lg)
    .frame(maxWidth: 360)
    // Opaque by design (spec §11): the terminal state must read over any frame.
    .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: MaxRadius.large))
    .accessibilityIdentifier(endedEvent == nil ? "ui_watch_kicked_card" : "ui_watch_ended_card")
  }

  private func resume(roomID: String, conversationID: String) {
    guard !isResuming else { return }
    isResuming = true
    Task {
      defer { isResuming = false }
      guard let room = await store.create(
        conversationID: conversationID,
        resumeFromRoomID: roomID
      ) else { return }
      if let mediaID = room.mediaId, let media = await model.resolveMediaItem(id: mediaID) {
        model.openPlayer(for: media)
      }
    }
  }
}
