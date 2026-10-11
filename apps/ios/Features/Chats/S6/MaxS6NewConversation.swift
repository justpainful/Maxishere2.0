import SwiftUI

struct MaxS6NewConversationSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette

  let onCreated: (ChatThread) -> Void

  @State private var mode = ConversationMode.direct
  @State private var query = ""
  @State private var groupName = ""
  @State private var selectedPersonIDs = Set<String>()
  @State private var isCreating = false

  private var people: [ChatPerson] {
    model.chatStore.peopleSearch.value ?? []
  }

  private var canCreate: Bool {
    guard !isCreating else { return false }
    switch mode {
    case .direct:
      return selectedPersonIDs.count == 1
    case .group:
      return !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !selectedPersonIDs.isEmpty
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("chat.new.kind", selection: $mode) {
          Text("chat.new.direct").tag(ConversationMode.direct)
          Text("chat.new.group").tag(ConversationMode.group)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if mode == .group {
          TextField("chat.new.group_name", text: $groupName)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("ui_s6_new_group_name")
        }

        peopleContent
      }
      .navigationTitle("chat.new.title")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "chat.new.search_people")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
            .disabled(isCreating)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("chat.new.create") { create() }
            .disabled(!canCreate)
        }
      }
      .task { await model.chatStore.searchPeople(query: "") }
      .task(id: query) {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        await model.chatStore.searchPeople(query: query)
      }
      .onChange(of: mode) { _, _ in selectedPersonIDs = [] }
      .interactiveDismissDisabled(isCreating)
    }
    .presentationDetents([.large])
    .accessibilityIdentifier("ui_s6_new_conversation")
  }

  @ViewBuilder
  private var peopleContent: some View {
    if model.chatStore.peopleSearch.isLoading && people.isEmpty {
      Spacer()
      ProgressView("chat.new.loading_people")
      Spacer()
    } else if let error = model.chatStore.peopleSearch.errorMessage, people.isEmpty {
      Spacer()
      MaxLoadFailureView(message: error) {
        Task { await model.chatStore.searchPeople(query: query) }
      }
      Spacer()
    } else if people.isEmpty {
      Spacer()
      MaxEmptyState(
        title: "chat.new.no_people",
        subtitle: "chat.new.no_people_hint",
        symbol: "person.2.slash"
      )
      Spacer()
    } else {
      List(people) { person in
        Button { toggle(person.id) } label: {
          HStack(spacing: 12) {
            MaxAvatar(name: person.displayName, imageURL: person.avatarUrl, size: 44)
            VStack(alignment: .leading, spacing: 3) {
              Text(verbatim: person.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primaryText)
              if let username = person.username, !username.isEmpty {
                Text(verbatim: "@\(username)")
                  .font(.caption)
                  .foregroundStyle(palette.secondaryText)
              }
            }
            Spacer()
            Image(systemName: selectedPersonIDs.contains(person.id)
              ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(
                selectedPersonIDs.contains(person.id) ? palette.accent : palette.tertiaryText
              )
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui_s6_chat_person_\(person.id)")
      }
      .listStyle(.plain)
      .overlay {
        if isCreating {
          ZStack {
            Color.black.opacity(0.12)
            ProgressView().controlSize(.large)
          }
          .ignoresSafeArea()
        }
      }
    }

    if let error = model.chatStore.createChatError {
      Text(verbatim: error)
        .font(.footnote)
        .foregroundStyle(.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
  }

  private func toggle(_ personID: String) {
    if mode == .direct {
      selectedPersonIDs = [personID]
    } else if !selectedPersonIDs.insert(personID).inserted {
      selectedPersonIDs.remove(personID)
    }
  }

  private func create() {
    guard canCreate else { return }
    isCreating = true
    Task {
      let created: ChatThread?
      if mode == .direct, let personID = selectedPersonIDs.first {
        created = await model.chatStore.createDirectChat(userID: personID)
      } else {
        created = await model.chatStore.createGroupChat(
          name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
          memberIDs: Array(selectedPersonIDs)
        )
      }
      isCreating = false
      if let created {
        dismiss()
        onCreated(created)
      }
    }
  }
}

private enum ConversationMode: String, CaseIterable, Identifiable {
  case direct
  case group
  var id: String { rawValue }
}
