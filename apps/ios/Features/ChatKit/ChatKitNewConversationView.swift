import SwiftUI

/// Start a new conversation: search people, tap for a direct message, or switch
/// to group mode to pick several members and name the group. Backed by
/// ChatStore.searchPeople / createDirectChat / createGroupChat.
struct ChatKitNewConversationView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var onCreated: (ChatThread) -> Void

  @State private var searchText = ""
  @State private var isGroupMode = false
  @State private var selected: [ChatPerson] = []
  @State private var groupName = ""
  @State private var isCreating = false

  private var store: ChatStore { model.chatStore }
  private var people: [ChatPerson] { store.peopleSearch.value ?? [] }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 0) {
          if isGroupMode {
            groupHeader
            Divider()
          }

          if store.peopleSearch.isLoading && people.isEmpty {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 200)
          } else if people.isEmpty {
            MaxEmptyState(
              title: searchText.isEmpty ? "Find people" : "No matches",
              subtitle: searchText.isEmpty ? "Search by name or username." : "Try a different search.",
              symbol: "person.2"
            )
            .padding(.top, MaxSpace.xl)
          } else {
            ForEach(people) { person in
              Button { handleTap(person) } label: {
                personRow(person)
              }
              .buttonStyle(.plain)
              Divider().padding(.leading, 72).opacity(0.4)
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "Search people")
      .navigationTitle(isGroupMode ? "New Group" : "New Chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isGroupMode {
            Button("Create") { createGroup() }
              .disabled(selected.isEmpty || isCreating)
          } else {
            Button("Group", systemImage: "person.3") { isGroupMode = true }
          }
        }
      }
      .task(id: searchText) { await runSearch() }
      .maxScreenBackground()
    }
  }

  private var groupHeader: some View {
    VStack(alignment: .leading, spacing: MaxSpace.sm) {
      TextField("Group name", text: $groupName)
        .font(.headline)
        .padding(.horizontal, MaxSpace.md)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      if !selected.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MaxSpace.sm) {
            ForEach(selected) { person in
              HStack(spacing: 4) {
                Text(person.displayName).font(.caption)
                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(.regularMaterial, in: Capsule())
              .onTapGesture { toggle(person) }
            }
          }
        }
      }
    }
    .padding(MaxSpace.md)
  }

  private func personRow(_ person: ChatPerson) -> some View {
    HStack(spacing: MaxSpace.sm) {
      ChatKitAvatar(url: person.avatarUrl, title: person.displayName)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 1) {
        Text(person.displayName).foregroundStyle(.primary)
        if let username = person.username, !username.isEmpty {
          Text(verbatim: "@\(username)").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if isGroupMode {
        Image(systemName: isSelected(person) ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected(person) ? AnyShapeStyle(MaxColor.accent) : AnyShapeStyle(.secondary))
      }
    }
    .padding(.horizontal, MaxSpace.md)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }

  private func isSelected(_ person: ChatPerson) -> Bool {
    selected.contains { $0.id == person.id }
  }

  private func toggle(_ person: ChatPerson) {
    if isSelected(person) {
      selected.removeAll { $0.id == person.id }
    } else {
      selected.append(person)
    }
  }

  private func handleTap(_ person: ChatPerson) {
    if isGroupMode {
      toggle(person)
    } else {
      startDM(person)
    }
  }

  private func runSearch() async {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    try? await Task.sleep(for: .milliseconds(300))
    if Task.isCancelled { return }
    await store.searchPeople(query: query)
  }

  private func startDM(_ person: ChatPerson) {
    guard !isCreating else { return }
    isCreating = true
    Task {
      if let thread = await store.createDirectChat(userID: person.id) {
        onCreated(thread)
        dismiss()
      }
      isCreating = false
    }
  }

  private func createGroup() {
    guard !selected.isEmpty, !isCreating else { return }
    isCreating = true
    let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = trimmed.isEmpty ? "New Group" : trimmed
    Task {
      if let thread = await store.createGroupChat(name: name, memberIDs: selected.map(\.id)) {
        onCreated(thread)
        dismiss()
      }
      isCreating = false
    }
  }
}
