import SwiftUI

/// Max-native fork of S6's ChatChannelListContentView and ChannelList.
/// The presentation follows the reference package while mutations stay in ChatStore.
struct MaxS6ChannelList<Destination: View>: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let threads: [ChatThread]
  let destination: (ChatThread) -> Destination
  let markRead: (ChatThread) -> Void

  init(
    threads: [ChatThread],
    @ViewBuilder destination: @escaping (ChatThread) -> Destination,
    markRead: @escaping (ChatThread) -> Void
  ) {
    self.threads = threads
    self.destination = destination
    self.markRead = markRead
  }

  private var activeThreads: [ChatThread] {
    threads.filter { $0.isArchived != true }
  }

  private var archivedThreads: [ChatThread] {
    threads.filter { $0.isArchived == true }
  }

  var body: some View {
    List {
      if !archivedThreads.isEmpty {
        NavigationLink {
          MaxS6ArchivedChannelList(
            threads: archivedThreads,
            destination: destination
          )
        } label: {
          HStack(spacing: 16) {
            Image(systemName: "archivebox.fill")
              .font(.title3)
              .foregroundStyle(palette.accent)
              .frame(width: 56, height: 56)
              .background(palette.accent.opacity(0.12), in: Circle())
            Text("chat.archived")
              .font(.body.weight(.semibold))
            Spacer()
            Text(verbatim: archivedThreads.count.formatted())
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(palette.secondaryText)
          }
          .padding(.vertical, 4)
        }
        .listRowSeparator(.visible)
        .listRowBackground(palette.canvas)
      }

      ForEach(activeThreads) { thread in
        channelLink(thread)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(palette.canvas)
    .accessibilityIdentifier("ui_s6_channel_list")
  }

  private func channelLink(_ thread: ChatThread) -> some View {
    NavigationLink {
      destination(thread)
    } label: {
      MaxS6ChannelListItem(thread: thread)
        .padding(.vertical, 4)
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
    .listRowBackground(palette.canvas)
    .listRowSeparatorTint(palette.separator.opacity(0.55))
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      if thread.unreadCount > 0 {
        Button {
          markRead(thread)
        } label: {
          Label("common.mark_read", systemImage: "checkmark.message.fill")
        }
        .tint(palette.accent)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        setArchived(true, thread: thread)
      } label: {
        Label("chat.archive", systemImage: "archivebox.fill")
      }
      .tint(palette.warning)

      Button {
        setMuted(thread.isMuted != true, thread: thread)
      } label: {
        Label(
          thread.isMuted == true ? "chat.unmute" : "chat.mute",
          systemImage: thread.isMuted == true ? "speaker.wave.2.fill" : "speaker.slash.fill"
        )
      }
      .tint(palette.secondaryText)
    }
    .contextMenu {
      if thread.unreadCount > 0 {
        Button("common.mark_read", systemImage: "checkmark.message") {
          markRead(thread)
        }
      }
      Button(
        thread.isMuted == true ? "chat.unmute" : "chat.mute",
        systemImage: thread.isMuted == true ? "speaker.wave.2" : "speaker.slash"
      ) {
        setMuted(thread.isMuted != true, thread: thread)
      }
      Button("chat.archive", systemImage: "archivebox") {
        setArchived(true, thread: thread)
      }
    }
    .accessibilityIdentifier("ui_chat_thread_\(thread.id)")
  }

  private func setMuted(_ value: Bool, thread: ChatThread) {
    Task {
      _ = await model.chatStore.updatePreference(
        for: thread.id,
        isMuted: value,
        isArchived: thread.isArchived == true,
        mutedUntil: nil
      )
    }
  }

  private func setArchived(_ value: Bool, thread: ChatThread) {
    Task {
      _ = await model.chatStore.updatePreference(
        for: thread.id,
        isMuted: thread.isMuted == true,
        isArchived: value,
        mutedUntil: thread.mutedUntil
      )
    }
  }
}

private struct MaxS6ArchivedChannelList<Destination: View>: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette
  let threads: [ChatThread]
  let destination: (ChatThread) -> Destination

  var body: some View {
    List(threads) { thread in
      NavigationLink {
        destination(thread)
      } label: {
        MaxS6ChannelListItem(thread: thread)
          .padding(.vertical, 4)
      }
      .listRowBackground(palette.canvas)
      .swipeActions {
        Button {
          Task {
            _ = await model.chatStore.updatePreference(
              for: thread.id,
              isMuted: thread.isMuted == true,
              isArchived: false,
              mutedUntil: thread.mutedUntil
            )
          }
        } label: {
          Label("chat.unarchive", systemImage: "archivebox.fill")
        }
        .tint(palette.accent)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(palette.canvas)
    .navigationTitle("chat.archived")
  }
}
