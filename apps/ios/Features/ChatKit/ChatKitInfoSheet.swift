import SwiftUI

/// Conversation details: large identity header, mute control, and — for groups —
/// the member roster. Uses ChatStore.loadMembers + updatePreference.
struct ChatKitInfoSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let thread: ChatThread

  private var store: ChatStore { model.chatStore }
  private var members: [ChatGroupMember] { store.membersByChat[thread.id]?.value ?? [] }

  private var muteBinding: Binding<Bool> {
    Binding(
      get: { thread.isMuted ?? false },
      set: { newValue in
        Task {
          await store.updatePreference(
            for: thread.id,
            isMuted: newValue,
            isArchived: thread.isArchived ?? false
          )
        }
      }
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MaxSpace.md) {
          VStack(spacing: MaxSpace.sm) {
            ChatKitAvatar(url: thread.avatarUrl, title: thread.title, isGroup: thread.isGroup)
              .frame(width: 96, height: 96)
            Text(thread.title)
              .font(.title2.bold())
              .multilineTextAlignment(.center)
            Text(thread.isGroup ? "Group · \(members.count) members" : "Direct message")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, MaxSpace.lg)

          VStack(spacing: 0) {
            Toggle(isOn: muteBinding) {
              Label("Mute notifications", systemImage: "bell.slash")
            }
            .padding(MaxSpace.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .padding(.horizontal, MaxSpace.md)

          if thread.isGroup {
            VStack(alignment: .leading, spacing: MaxSpace.sm) {
              Text("Members")
                .font(.headline)
                .padding(.horizontal, MaxSpace.md)

              if store.membersByChat[thread.id]?.isLoading == true, members.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
              } else {
                LazyVStack(spacing: 0) {
                  ForEach(members) { member in
                    HStack(spacing: MaxSpace.sm) {
                      ChatKitAvatar(url: member.avatarUrl, title: member.displayName)
                        .frame(width: 40, height: 40)
                      Text(member.displayName).foregroundStyle(.primary)
                      Spacer()
                      if member.role.lowercased() == "owner" || member.role.lowercased() == "admin" {
                        Text(member.role.capitalized)
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      }
                    }
                    .padding(.horizontal, MaxSpace.md)
                    .padding(.vertical, 6)
                  }
                }
              }
            }
          }
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
      .maxScreenBackground()
    }
  }
}
