import SwiftUI

struct ChatsV3NewChatSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var people = [ChatPerson]()
  @State private var selected = Set<String>()
  @State private var groupName = ""
  @State private var isCreating = false

  private var creatingGroup: Bool { selected.count > 1 || !groupName.isEmpty }

  var body: some View {
    NavigationStack {
      List {
        Section("People") {
          ForEach(people) { person in
            Button {
              if selected.contains(person.id) { selected.remove(person.id) }
              else { selected.insert(person.id) }
            } label: {
              HStack {
                ChatsV3PersonRow(person: person)
                Spacer()
                if selected.contains(person.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(MaxColor.accent) }
              }
            }
            .buttonStyle(.plain)
          }
        }
        if selected.count > 1 {
          Section("Group") {
            TextField("Group name", text: $groupName)
          }
        }
      }
      .overlay {
        if people.isEmpty && !query.isEmpty { ContentUnavailableView("No people found", systemImage: "person.crop.circle.badge.questionmark") }
      }
      .navigationTitle("chat.new.title")
      .searchable(text: $query, prompt: "Search people")
      .onChange(of: query) { _, value in
        Task { people = await model.chatsV3Store.searchPeople(value) }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(creatingGroup ? "Create group" : "Chat") {
            Task { await create() }
          }
          .disabled(selected.isEmpty || (creatingGroup && groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isCreating)
        }
      }
      .task { people = await model.chatsV3Store.searchPeople("") }
    }
  }

  private func create() async {
    isCreating = true
    defer { isCreating = false }
    if creatingGroup {
      _ = await model.chatsV3Store.createGroupChat(
        name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
        memberIDs: Array(selected)
      )
    } else if let id = selected.first {
      _ = await model.chatsV3Store.createDirectChat(with: id)
    }
    dismiss()
  }
}

private struct ChatsV3PersonRow: View {
  let person: ChatPerson

  var body: some View {
    HStack(spacing: 10) {
      ChatsV3Avatar(url: person.avatarUrl, title: person.displayName, isGroup: false)
      VStack(alignment: .leading) {
        Text(person.displayName)
        if let username = person.username { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
      }
    }
  }
}

struct ChatsV3ChatInfoSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread
  @State private var name = ""
  @State private var showsRename = false
  @State private var showsAddMember = false

  private var preference: ChatThreadPreference? {
    model.chatsV3Store.preferencesByChat[thread.id]?.value
  }
  private var members: [ChatGroupMember] {
    model.chatsV3Store.membersByChat[thread.id]?.value ?? []
  }
  private var currentUserID: String? { model.sessionStore.user?.id }
  private var currentRole: String? { members.first(where: { $0.userId == currentUserID })?.role }
  private var canManage: Bool { currentRole == "owner" || currentRole == "admin" }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 12) {
            ChatsV3Avatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
            VStack(alignment: .leading) {
              Text(thread.title).font(.title3.weight(.semibold))
              Text(thread.isGroup ? "Group conversation" : "Private conversation").font(.subheadline).foregroundStyle(.secondary)
            }
          }
        }
        Section("Conversation") {
          Toggle("Mute notifications", isOn: Binding(
            get: { preference?.isMuted ?? thread.isMuted ?? false },
            set: { value in
              Task {
                await model.chatsV3Store.updatePreference(
                  chatID: thread.id,
                  isMuted: value,
                  isArchived: preference?.isArchived ?? thread.isArchived ?? false
                )
              }
            }
          ))
          Button(preference?.isArchived == true || thread.isArchived == true ? "Restore from archive" : "Archive conversation") {
            Task {
              await model.chatsV3Store.updatePreference(
                chatID: thread.id,
                isMuted: preference?.isMuted ?? thread.isMuted ?? false,
                isArchived: !(preference?.isArchived ?? thread.isArchived ?? false)
              )
            }
          }
        }
        if thread.isGroup {
          Section("Group") {
            if canManage { Button("chat.action.nickname", systemImage: "pencil") { name = thread.title; showsRename = true } }
            if canManage { Button("chat.new.group", systemImage: "person.badge.plus") { showsAddMember = true } }
            ForEach(members) { member in
              ChatsV3MemberRow(member: member, canManage: canManage && member.userId != currentUserID) { role in
                Task { _ = await model.chatsV3Store.updateMemberRole(chatID: thread.id, userID: member.userId, role: role) }
              } remove: {
                Task { _ = await model.chatsV3Store.removeMember(chatID: thread.id, userID: member.userId) }
              }
            }
          }
        }
      }
      .navigationTitle("chat.info")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("common.done") { dismiss() } } }
      .alert("Rename group", isPresented: $showsRename) {
        TextField("Name", text: $name)
        Button("common.save") { Task { _ = await model.chatsV3Store.updateGroup(chatID: thread.id, name: name) } }
        Button("action.cancel", role: .cancel) { }
      }
      .sheet(isPresented: $showsAddMember) { ChatsV3AddMemberSheet(chatID: thread.id) }
      .task {
        await model.chatsV3Store.loadPreference(for: thread.id)
        if thread.isGroup { await model.chatsV3Store.loadMembers(for: thread.id) }
      }
    }
  }
}

private struct ChatsV3AddMemberSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let chatID: String
  @State private var query = ""
  @State private var people = [ChatPerson]()

  var body: some View {
    NavigationStack {
      List(people) { person in
        Button {
          Task {
            if await model.chatsV3Store.addMember(chatID: chatID, userID: person.id) { dismiss() }
          }
        } label: { ChatsV3PersonRow(person: person) }
        .buttonStyle(.plain)
      }
      .navigationTitle("chat.new.group")
      .searchable(text: $query, prompt: "Search people")
      .onChange(of: query) { _, value in Task { people = await model.chatsV3Store.searchPeople(value) } }
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("common.done") { dismiss() } } }
      .task { people = await model.chatsV3Store.searchPeople("") }
    }
  }
}

private struct ChatsV3MemberRow: View {
  let member: ChatGroupMember
  let canManage: Bool
  let updateRole: (String) -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      ChatsV3Avatar(url: member.avatarUrl, title: member.displayName, isGroup: false)
      VStack(alignment: .leading) {
        Text(member.displayName)
        Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if canManage {
        Menu {
          Button(member.role == "admin" ? "Make member" : "Make admin") { updateRole(member.role == "admin" ? "member" : "admin") }
          Button("action.remove", role: .destructive) { remove() }
        } label: { Image(systemName: "ellipsis.circle") }
      }
    }
    .padding(.vertical, 2)
  }
}
