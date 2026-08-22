import AppKit
import SwiftUI

struct ChatsView: View {
  @Environment(MaxDesktopModel.self) private var model
  @State private var query = ""
  @State private var draft = ""
  @State private var showsDetails = false
  @State private var showsNewConversation = false

  private var visibleThreads: [ChatThread] {
    model.threads.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    let palette = model.palette

    HStack(spacing: 0) {
      threadList(palette: palette)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

      Divider().opacity(0.4)

      if let thread = model.activeThread {
        conversation(thread: thread, palette: palette)
      } else {
        EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "Choose a conversation", message: "Select a chat to read and send messages.")
      }

      if showsDetails, let thread = model.activeThread {
        Divider().opacity(0.4)
        ChatDetailsPanel(thread: thread)
          .environment(model)
          .frame(width: 280)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.snappy, value: showsDetails)
    .navigationTitle(model.copy("chats"))
    .accessibilityIdentifier("mac_chats_screen")
    .task {
      try? await Task.sleep(for: .milliseconds(150))
      if model.selectedThreadID == nil {
        model.selectedThreadID = visibleThreads.first?.id
      }
    }
    .sheet(isPresented: $showsNewConversation) {
      NewConversationView(isPresented: $showsNewConversation)
        .environment(model)
    }
  }

  private func threadList(palette: MaxPalette) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(model.copy("chats")).font(.title2.bold())
        Spacer()
        Button { showsNewConversation = true } label: { Image(systemName: "square.and.pencil") }
          .buttonStyle(.glass)
          .accessibilityLabel("New Conversation")
          .accessibilityIdentifier("mac_chat_new")
      }
      .padding(16)

      TextField(model.copy("search"), text: $query)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)

      Divider().opacity(0.35)

      List(selection: Binding(
        get: { model.selectedThreadID },
        set: { model.selectedThreadID = $0 }
      )) {
        ForEach(visibleThreads) { thread in
          HStack(spacing: 11) {
            ZStack {
              Circle().fill(Color(hue: thread.hue, saturation: 0.65, brightness: 0.88))
              Text(thread.title.prefix(1)).font(.headline.bold()).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(thread.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if thread.isMuted { Image(systemName: "speaker.slash.fill").font(.caption2) }
              }
              Text(thread.subtitle).font(.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            if thread.unreadCount > 0 {
              Text("\(thread.unreadCount)")
                .font(.caption2.bold())
                .padding(6)
                .background(palette.accent, in: Circle())
                .foregroundStyle(.white)
            }
          }
          .padding(.vertical, 5)
          .tag(thread.id)
          .accessibilityIdentifier("mac_chat_thread_\(thread.id)")
        }
      }
      .scrollContentBackground(.hidden)
      .listStyle(.sidebar)
    }
  }

  private func conversation(thread: ChatThread, palette: MaxPalette) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Circle()
          .fill(Color(hue: thread.hue, saturation: 0.65, brightness: 0.88))
          .frame(width: 36, height: 36)
          .overlay(Text(thread.title.prefix(1)).font(.headline.bold()).foregroundStyle(.white))
        VStack(alignment: .leading, spacing: 2) {
          Text(thread.title).font(.headline)
          Text("Active now").font(.caption).foregroundStyle(.green)
        }
        Spacer()
        GlassEffectContainer(spacing: 8) {
          HStack(spacing: 8) {
            Button { } label: { Image(systemName: "phone.fill") }.buttonStyle(.glass)
            Button { } label: { Image(systemName: "video.fill") }.buttonStyle(.glass)
            Button { showsDetails.toggle() } label: { Image(systemName: "info.circle.fill") }
              .buttonStyle(.glass)
              .accessibilityLabel("Conversation Details")
              .accessibilityIdentifier("mac_chat_details")
          }
        }
      }
      .padding(14)

      Divider().opacity(0.35)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 13) {
            Text("Today")
              .font(.caption.weight(.semibold))
              .foregroundStyle(palette.textSecondary)
              .padding(.vertical, 7)
            ForEach(thread.messages) { message in
              ChatBubble(message: message)
                .environment(model)
                .id(message.id)
            }
          }
          .padding(20)
        }
        .onChange(of: thread.messages.count) { _, _ in
          if let last = thread.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }

      Divider().opacity(0.35)

      HStack(alignment: .bottom, spacing: 10) {
        Button { } label: { Image(systemName: "plus") }.buttonStyle(.glass)
        TextField(model.copy("messagePlaceholder"), text: $draft, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...5)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .glassEffect(.regular, in: .rect(cornerRadius: 18))
          .accessibilityIdentifier("mac_chat_composer")
          .onSubmit(send)
        Button(action: send) {
          Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up")
        }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("mac_chat_send")
      }
      .padding(14)
    }
    .accessibilityIdentifier("mac_chat_detail")
  }

  private func send() {
    model.sendMessage(draft)
    draft = ""
  }
}

private struct ChatBubble: View {
  @Environment(MaxDesktopModel.self) private var model
  let message: ChatMessage

  var body: some View {
    HStack {
      if message.isMine { Spacer(minLength: 90) }
      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 6) {
        if !message.isMine {
          Text(message.sender).font(.caption.weight(.semibold)).foregroundStyle(model.palette.accent)
        }
        if let mediaID = message.mediaID,
           let item = model.media.first(where: { $0.id == mediaID }) {
          Button { model.open(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
              MediaArtwork(item: item)
                .frame(width: 230, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 13))
              Label(item.title, systemImage: item.kind == .video ? "play.fill" : "photo.fill")
                .font(.caption.weight(.semibold))
            }
          }
          .buttonStyle(.plain)
        }
        Text(message.body)
          .textSelection(.enabled)
        HStack(spacing: 7) {
          if message.isEdited { Text("Edited") }
          Text(message.sentAt, style: .time)
        }
        .font(.caption2)
        .foregroundStyle(model.palette.textSecondary)
      }
      .padding(12)
      .glassEffect(
        .regular.tint(message.isMine ? model.palette.accent.opacity(0.32) : .clear),
        in: .rect(cornerRadius: 18)
      )
      .overlay(alignment: .bottomLeading) {
        if let reaction = message.reaction {
          Text(reaction)
            .font(.caption)
            .padding(4)
            .glassEffect(.regular, in: .circle)
            .offset(x: 6, y: 13)
        }
      }
      .contextMenu {
        Button("Reply") { }
        Button("Copy") { NSPasteboard.general.setString(message.body, forType: .string) }
        if message.isMine { Button("Edit") { } }
        Button("Delete", role: .destructive) { }
      }
      if !message.isMine { Spacer(minLength: 90) }
    }
    .accessibilityIdentifier("mac_chat_message_\(message.id)")
  }
}

private struct ChatDetailsPanel: View {
  @Environment(MaxDesktopModel.self) private var model
  let thread: ChatThread

  var body: some View {
    VStack(spacing: 18) {
      Circle()
        .fill(Color(hue: thread.hue, saturation: 0.65, brightness: 0.88))
        .frame(width: 78, height: 78)
        .overlay(Text(thread.title.prefix(1)).font(.largeTitle.bold()).foregroundStyle(.white))
      Text(thread.title).font(.title2.bold())
      Text("Media, links, and conversation controls")
        .font(.caption)
        .foregroundStyle(model.palette.textSecondary)
        .multilineTextAlignment(.center)
      Divider()
      VStack(alignment: .leading, spacing: 14) {
        Toggle("Mute notifications", isOn: .constant(thread.isMuted))
        Button("Shared Media") { }
        Button("Pinned Messages") { }
        Button("Search Conversation") { }
        Divider()
        Button("Delete Conversation", role: .destructive) { }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer()
    }
    .padding(22)
    .background(.ultraThinMaterial)
    .accessibilityIdentifier("mac_chat_details_panel")
  }
}

private struct NewConversationView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Binding var isPresented: Bool
  @State private var query = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(model.copy("newMessage")).font(.largeTitle.bold())
        Spacer()
        Button { isPresented = false } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
      }
      TextField(model.copy("search"), text: $query).textFieldStyle(.roundedBorder)
      ForEach(["Nora Demo", "Sami", "Max Demo Bot"], id: \.self) { name in
        Button {
          if let thread = model.threads.first(where: { $0.title == name }) {
            model.selectedThreadID = thread.id
          }
          isPresented = false
        } label: {
          Label(name, systemImage: "person.crop.circle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(26)
    .frame(width: 520, height: 440)
    .accessibilityIdentifier("mac_new_conversation")
  }
}
