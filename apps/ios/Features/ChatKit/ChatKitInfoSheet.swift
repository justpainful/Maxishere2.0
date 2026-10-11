import SwiftUI
import UIKit

/// Conversation details: large identity header, mute control, and — for groups —
/// the member roster WITH the admin surface (rename, add/remove members, roles,
/// clear history). All of these existed on `ChatStore` and the server; none was
/// reachable from the chat the app shows, which is why a group could never be
/// renamed from the phone.
struct ChatKitInfoSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let thread: ChatThread

  @State private var showRename = false
  @State private var renameDraft = ""
  @State private var showAddMember = false
  @State private var showInviteLinks = false
  @State private var showClearConfirm = false
  @State private var pendingRemoval: ChatGroupMember?
  @State private var viewingProfile: ViewedUser?

  private struct ViewedUser: Identifiable {
    let id: String
  }

  private var store: ChatStore { model.chatStore }
  private var members: [ChatGroupMember] { store.membersByChat[thread.id]?.value ?? [] }

  /// The sheet captures an immutable `thread`, so after a rename it would keep
  /// showing the stale title until it was re-opened. Read the live row instead.
  private var liveThread: ChatThread {
    store.threads.value?.first(where: { $0.id == thread.id }) ?? thread
  }

  private var currentUserID: String? { model.sessionStore.user?.id }

  private var canManageGroup: Bool {
    guard thread.isGroup else { return false }
    if let role = members.first(where: { $0.userId == currentUserID })?.role.lowercased() {
      return role == "owner" || role == "admin"
    }
    // Members have not loaded yet; fall back to the conversation's own owner.
    guard let ownerId = thread.ownerId, let currentUserID else { return false }
    return ownerId == currentUserID
  }

  /// The current disappearing-messages setting, as the trailing row text.
  private var currentTimerTitle: String {
    guard let ttl = liveThread.messageTtlSeconds, ttl > 0 else { return "Off" }
    return ChatKitTimerOption.all.first(where: { $0.seconds == ttl })?.title
      ?? ChatKitTime.compactDuration(ttl)
  }

  private var lockBinding: Binding<Bool> {
    Binding(
      get: { model.chatLockStore.isLocked(thread.id) },
      set: { newValue in
        Task { await model.chatLockStore.setLocked(newValue, threadID: thread.id) }
      }
    )
  }

  private var muteBinding: Binding<Bool> {
    Binding(
      get: { liveThread.isMuted ?? false },
      set: { newValue in
        Task {
          await store.updatePreference(
            for: thread.id,
            isMuted: newValue,
            isArchived: liveThread.isArchived ?? false
          )
        }
      }
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MaxSpace.md) {
          header
          settingsCard
          if thread.isGroup { membersSection }
        }
        .padding(.bottom, MaxSpace.xl)
      }
      .navigationTitle("Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .task {
        if thread.isGroup, store.membersByChat[thread.id]?.value == nil {
          await store.loadMembers(for: thread.id)
        }
      }
      .alert("Rename Group", isPresented: $showRename) {
        TextField("Group name", text: $renameDraft)
        Button("Cancel", role: .cancel) {}
        Button("Save") {
          let name = renameDraft
          Task { await store.renameGroup(thread.id, name: name) }
        }
      } message: {
        Text("Everyone in the group sees the new name.")
      }
      .alert("Remove member?", isPresented: Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }
      )) {
        Button("Cancel", role: .cancel) { pendingRemoval = nil }
        Button("Remove", role: .destructive) {
          if let member = pendingRemoval {
            Task { await store.removeMember(member.userId, from: thread.id) }
          }
          pendingRemoval = nil
        }
      } message: {
        Text(pendingRemoval.map { "\($0.displayName) will no longer see this conversation." } ?? "")
      }
      .confirmationDialog("Clear chat history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
        Button("Clear History", role: .destructive) {
          Task { await store.clearMessages(in: thread.id) }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Messages are removed from this conversation for you.")
      }
      .sheet(isPresented: $showAddMember) {
        ChatKitAddMemberSheet(thread: thread)
          .environment(model)
      }
      .sheet(isPresented: $showInviteLinks) {
        ChatKitInviteLinksSheet(thread: thread)
          .environment(model)
      }
      .sheet(item: $viewingProfile) { viewed in
        PeerProfileView(userID: viewed.id)
          .environment(model)
      }
      .maxScreenBackground()
    }
  }

  private var header: some View {
    VStack(spacing: MaxSpace.sm) {
      ChatKitAvatar(url: liveThread.avatarUrl, title: liveThread.displayTitle, isGroup: thread.isGroup)
        .frame(width: 96, height: 96)
      Text(liveThread.displayTitle)
        .font(.title2.bold())
        .multilineTextAlignment(.center)
      Text(thread.isGroup ? "Group · \(members.count) members" : "Direct message")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, MaxSpace.lg)
  }

  private var settingsCard: some View {
    VStack(spacing: 0) {
      if !thread.isGroup, let partnerId = thread.partnerId {
        Button {
          viewingProfile = ViewedUser(id: partnerId)
        } label: {
          HStack {
            Label("View Profile", systemImage: "person.crop.circle")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(MaxSpace.md)
        .accessibilityIdentifier("ui_chat_view_profile")
        Divider().padding(.leading, MaxSpace.md)
      }

      Toggle(isOn: muteBinding) {
        Label("Mute notifications", systemImage: "bell.slash")
      }
      .padding(MaxSpace.md)

      Divider().padding(.leading, MaxSpace.md)
      Menu {
        ForEach(ChatKitTimerOption.all) { option in
          Button {
            Task { await store.setMessageTimer(threadID: thread.id, ttlSeconds: option.seconds) }
          } label: {
            if option.seconds == liveThread.messageTtlSeconds {
              Label(option.title, systemImage: "checkmark")
            } else {
              Text(option.title)
            }
          }
        }
      } label: {
        HStack {
          Label("Disappearing Messages", systemImage: "timer")
          Spacer()
          Text(currentTimerTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(MaxSpace.md)
      .accessibilityIdentifier("ui_chat_message_timer")

      Divider().padding(.leading, MaxSpace.md)
      Toggle(isOn: lockBinding) {
        Label("Lock Chat", systemImage: "lock")
      }
      .padding(MaxSpace.md)
      .accessibilityIdentifier("ui_chat_lock_toggle")

      if thread.isGroup {
        Divider().padding(.leading, MaxSpace.md)
        Button {
          showInviteLinks = true
        } label: {
          HStack {
            Label("Invite Links", systemImage: "link")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(MaxSpace.md)
        .accessibilityIdentifier("ui_chat_invite_links")
      }

      if canManageGroup {
        Divider().padding(.leading, MaxSpace.md)
        Button {
          renameDraft = liveThread.title
          showRename = true
        } label: {
          HStack {
            Label("Rename group", systemImage: "pencil")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(MaxSpace.md)
        .accessibilityIdentifier("ui_chat_rename_group")
      }

      Divider().padding(.leading, MaxSpace.md)
      Button(role: .destructive) {
        showClearConfirm = true
      } label: {
        HStack {
          Label("Clear history", systemImage: "eraser")
            .foregroundStyle(.red)
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(MaxSpace.md)
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(.horizontal, MaxSpace.md)
  }

  private var membersSection: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      HStack {
        Text("Members")
          .font(.headline)
        Spacer()
        if canManageGroup {
          Button {
            showAddMember = true
          } label: {
            Label("Add", systemImage: "person.badge.plus")
              .font(.subheadline.weight(.semibold))
          }
          .accessibilityIdentifier("ui_chat_add_member")
        }
      }
      .padding(.horizontal, MaxSpace.md)

      if store.membersByChat[thread.id]?.isLoading == true, members.isEmpty {
        ProgressView().frame(maxWidth: .infinity).padding()
      } else {
        LazyVStack(spacing: 0) {
          ForEach(members) { member in
            memberRow(member)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func memberRow(_ member: ChatGroupMember) -> some View {
    let role = member.role.lowercased()
    let manageable = canManageGroup && member.userId != currentUserID && role != "owner"
    HStack(spacing: MaxSpace.sm) {
      // The person, tappable: a member list where names lead nowhere is a
      // directory with no doors.
      Button {
        if member.userId != currentUserID { viewingProfile = ViewedUser(id: member.userId) }
      } label: {
        HStack(spacing: MaxSpace.sm) {
          ChatKitAvatar(url: member.avatarUrl, title: member.displayName)
            .frame(width: 40, height: 40)
          Text(member.displayName).foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Spacer()
      if role == "owner" || role == "admin" {
        Text(member.role.capitalized)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      if manageable {
        Menu {
          Button {
            let newRole = role == "admin" ? "member" : "admin"
            Task { await store.updateMemberRole(member.userId, in: thread.id, role: newRole) }
          } label: {
            Label(role == "admin" ? "Make member" : "Make admin", systemImage: "person.badge.shield.checkmark")
          }
          Button(role: .destructive) {
            pendingRemoval = member
          } label: {
            Label("Remove from group", systemImage: "person.badge.minus")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Manage \(member.displayName)")
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, 6)
  }
}

/// The disappearing-messages durations offered by the Details sheet. `nil`
/// seconds means the timer is off.
private struct ChatKitTimerOption: Identifiable {
  let seconds: Int?
  let title: String
  var id: String { title }

  static let all: [ChatKitTimerOption] = [
    ChatKitTimerOption(seconds: nil, title: "Off"),
    ChatKitTimerOption(seconds: 30, title: "30 seconds"),
    ChatKitTimerOption(seconds: 5 * 60, title: "5 minutes"),
    ChatKitTimerOption(seconds: 60 * 60, title: "1 hour"),
    ChatKitTimerOption(seconds: 24 * 60 * 60, title: "1 day"),
    ChatKitTimerOption(seconds: 7 * 24 * 60 * 60, title: "1 week"),
  ]
}

/// The group's invite links: create one (copied to the clipboard right away),
/// share it, watch its expiry and use count, revoke it. Anyone holding a live
/// link can join the group.
struct ChatKitInviteLinksSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let thread: ChatThread

  @State private var invites: [MaxGroupInvite]?
  @State private var isCreating = false
  @State private var copiedInviteID: String?
  @State private var errorText: String?

  /// Revoked rows stay server-side for the audit trail; the sheet shows only
  /// links that still open the door.
  private var activeInvites: [MaxGroupInvite] {
    (invites ?? []).filter { $0.revokedAt == nil }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MaxSpace.md) {
          Button {
            create()
          } label: {
            HStack(spacing: MaxSpace.sm) {
              if isCreating {
                ProgressView()
              } else {
                Image(systemName: "plus.circle.fill")
                  .font(.title3)
                  .foregroundStyle(MaxColor.accent)
              }
              VStack(alignment: .leading, spacing: 1) {
                Text("New Invite Link")
                  .font(.body.weight(.semibold))
                  .foregroundStyle(.primary)
                Text("Expires in 7 days · copied when created")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(MaxSpace.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(isCreating)
          .accessibilityIdentifier("ui_invite_create")

          if let errorText {
            Text(verbatim: errorText)
              .font(.caption)
              .foregroundStyle(.red)
          }

          if invites == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.top, MaxSpace.lg)
          } else if activeInvites.isEmpty {
            MaxEmptyState(
              title: "No invite links yet",
              subtitle: "Create one and anyone holding it can join this group.",
              symbol: "link"
            )
            .padding(.top, MaxSpace.lg)
          } else {
            VStack(spacing: 0) {
              ForEach(activeInvites) { invite in
                inviteRow(invite)
                if invite.id != activeInvites.last?.id {
                  Divider().padding(.leading, MaxSpace.md)
                }
              }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }
        .padding(MaxSpace.md)
      }
      .navigationTitle("Invite Links")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .task { await load() }
      .maxScreenBackground()
    }
    .accessibilityIdentifier("ui_invite_links_sheet")
  }

  private func inviteRow(_ invite: MaxGroupInvite) -> some View {
    HStack(spacing: MaxSpace.sm) {
      Image(systemName: "link")
        .foregroundStyle(MaxColor.accent)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: invite.link ?? invite.token)
          .font(.caption.monospaced())
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .environment(\.layoutDirection, .leftToRight)
        Text(verbatim: inviteSubtitle(invite))
          .font(.caption2)
          .foregroundStyle(copiedInviteID == invite.id ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
      }
      Spacer(minLength: 0)
      Menu {
        Button {
          copy(invite)
        } label: {
          Label("Copy Link", systemImage: "doc.on.doc")
        }
        if let link = invite.link, let url = URL(string: link) {
          ShareLink(item: url) {
            Label("Share…", systemImage: "square.and.arrow.up")
          }
        }
        Divider()
        Button(role: .destructive) {
          revoke(invite)
        } label: {
          Label("Revoke", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .foregroundStyle(.secondary)
      }
      .accessibilityLabel(Text("Invite link options"))
    }
    .padding(MaxSpace.md)
  }

  /// "Expires in 6d · 3 uses" (or "3/10 uses" against a cap).
  private func inviteSubtitle(_ invite: MaxGroupInvite) -> String {
    if copiedInviteID == invite.id { return "Copied to clipboard" }
    var parts: [String] = []
    if let expiry = ChatKitTime.date(invite.expiresAt) {
      let remaining = expiry.timeIntervalSinceNow
      parts.append(
        remaining > 0
          ? "Expires in \(ChatKitTime.compactDuration(Int(remaining)))"
          : "Expired"
      )
    }
    if let maxUses = invite.maxUses {
      parts.append("\(invite.useCount)/\(maxUses) uses")
    } else {
      parts.append(invite.useCount == 1 ? "1 use" : "\(invite.useCount) uses")
    }
    return parts.joined(separator: " · ")
  }

  private func load() async {
    invites = (try? await model.apiClient.groupInvites(chatID: thread.id)) ?? []
  }

  private func create() {
    guard !isCreating else { return }
    isCreating = true
    errorText = nil
    Task {
      defer { isCreating = false }
      do {
        let invite = try await model.apiClient.createGroupInvite(
          chatID: thread.id,
          expiresInSeconds: 7 * 24 * 60 * 60,
          maxUses: nil
        )
        invites = [invite] + (invites ?? [])
        copy(invite)
      } catch {
        errorText = error.localizedDescription
      }
    }
  }

  private func copy(_ invite: MaxGroupInvite) {
    guard let link = invite.link else { return }
    UIPasteboard.general.string = link
    copiedInviteID = invite.id
  }

  /// Optimistic: the row disappears immediately, truth restored on failure.
  private func revoke(_ invite: MaxGroupInvite) {
    invites = (invites ?? []).filter { $0.id != invite.id }
    Task {
      if (try? await model.apiClient.revokeGroupInvite(id: invite.id)) == nil {
        await load()
      }
    }
  }
}

/// Add-member picker: the same people search the New Conversation screen uses,
/// with everyone already in the group filtered out.
struct ChatKitAddMemberSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let thread: ChatThread

  @State private var searchText = ""
  @State private var searchTask: Task<Void, Never>?
  @State private var addingID: String?

  private var store: ChatStore { model.chatStore }
  private var memberIDs: Set<String> {
    Set((store.membersByChat[thread.id]?.value ?? []).map(\.userId))
  }
  private var candidates: [ChatPerson] {
    (store.peopleSearch.value ?? []).filter { !memberIDs.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      List {
        if store.peopleSearch.isLoading {
          HStack { Spacer(); ProgressView(); Spacer() }
        }
        ForEach(candidates) { person in
          Button {
            add(person)
          } label: {
            HStack(spacing: MaxSpace.sm) {
              ChatKitAvatar(url: person.avatarUrl, title: person.displayName)
                .frame(width: 40, height: 40)
              VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName).foregroundStyle(.primary)
                if let username = person.username {
                  Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              if addingID == person.id {
                ProgressView()
              } else {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
              }
            }
          }
          .disabled(addingID != nil)
        }
      }
      .listStyle(.plain)
      .searchable(text: $searchText, prompt: "Search people")
      .onChange(of: searchText) { _, _ in
        searchTask?.cancel()
        searchTask = Task {
          let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !query.isEmpty else { return }
          try? await Task.sleep(for: .milliseconds(300))
          if Task.isCancelled { return }
          await store.searchPeople(query: query)
        }
      }
      .navigationTitle("Add Member")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .maxScreenBackground()
    }
  }

  private func add(_ person: ChatPerson) {
    guard addingID == nil else { return }
    addingID = person.id
    Task {
      _ = await store.addMember(person.id, to: thread.id)
      addingID = nil
    }
  }
}
