import SwiftUI

struct MaxS6CreatePollSheet: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let thread: ChatThread

  @State private var question = ""
  @State private var options = ["", ""]
  @State private var allowMultipleVotes = false
  @State private var isCreating = false
  @State private var errorMessage: String?

  private var normalizedQuestion: String {
    question.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var normalizedOptions: [String] {
    options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private var canCreate: Bool {
    !isCreating && !normalizedQuestion.isEmpty && normalizedOptions.count >= 2
      && Set(normalizedOptions.map { $0.localizedLowercase }).count == normalizedOptions.count
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("chat.poll.question") {
          TextField("chat.poll.question.placeholder", text: $question, axis: .vertical)
            .lineLimit(1...4)
            .accessibilityIdentifier("ui_s6_poll_question")
        }

        Section("chat.poll.options") {
          ForEach(options.indices, id: \.self) { index in
            HStack {
              TextField(
                String(localized: "chat.poll.option.placeholder"),
                text: Binding(
                  get: { options[index] },
                  set: { options[index] = $0 }
                )
              )
              if options.count > 2 {
                Button(role: .destructive) {
                  options.remove(at: index)
                } label: {
                  Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
              }
            }
          }
          if options.count < 10 {
            Button("chat.poll.add_option", systemImage: "plus.circle") {
              options.append("")
            }
          }
        }

        Section {
          Toggle("chat.poll.multiple", isOn: $allowMultipleVotes)
        } footer: {
          Text("chat.poll.multiple.help")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("chat.poll.create")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
            .disabled(isCreating)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("chat.poll.create") { create() }
            .disabled(!canCreate)
        }
      }
      .interactiveDismissDisabled(isCreating)
    }
    .presentationDetents([.large])
    .accessibilityIdentifier("ui_s6_create_poll")
  }

  private func create() {
    isCreating = true
    errorMessage = nil
    Task {
      let message = await model.chatStore.createPoll(
        in: thread.id,
        question: normalizedQuestion,
        options: normalizedOptions,
        allowMultipleVotes: allowMultipleVotes
      )
      isCreating = false
      if message != nil {
        dismiss()
      } else {
        errorMessage = model.chatStore.sendStateByChat[thread.id]?.errorMessage
          ?? String(localized: "chat.poll.failed")
      }
    }
  }
}

struct MaxS6PollAttachmentView: View {
  @Environment(MaxAppModel.self) private var model
  @Environment(\.maxThemePalette) private var palette

  let threadID: String
  let poll: ChatPoll

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        Image(systemName: "chart.bar.fill")
          .foregroundStyle(palette.accent)
        Text("chat.poll")
          .font(.caption.weight(.bold))
          .foregroundStyle(palette.secondaryText)
        Spacer()
        if poll.isClosed {
          Text("chat.poll.closed")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.tertiaryText)
        }
      }

      Text(verbatim: poll.question)
        .font(.body.weight(.semibold))
        .foregroundStyle(palette.primaryText)
        .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 7) {
        ForEach(poll.options) { option in
          pollOption(option)
        }
      }

      HStack {
        Text(verbatim: poll.totalVotes.formatted())
        Text("chat.poll.votes")
        if poll.allowMultipleVotes {
          Text("chat.poll.multiple.short")
        }
      }
      .font(.caption2)
      .foregroundStyle(palette.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func pollOption(_ option: ChatPollOption) -> some View {
    let fraction = poll.totalVotes > 0
      ? Double(option.voteCount) / Double(poll.totalVotes) : 0
    return Button {
      guard !poll.isClosed else { return }
      Task {
        _ = await model.chatStore.setPollVote(
          in: threadID,
          pollID: poll.id,
          optionID: option.id,
          selected: !option.votedByMe
        )
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: option.votedByMe
          ? (poll.allowMultipleVotes ? "checkmark.square.fill" : "checkmark.circle.fill")
          : (poll.allowMultipleVotes ? "square" : "circle"))
          .foregroundStyle(option.votedByMe ? palette.accent : palette.secondaryText)
        Text(verbatim: option.text)
          .font(.subheadline.weight(option.votedByMe ? .semibold : .regular))
          .foregroundStyle(palette.primaryText)
          .lineLimit(2)
        Spacer()
        Text(verbatim: option.voteCount.formatted())
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(palette.secondaryText)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .background(alignment: .leading) {
        GeometryReader { geometry in
          palette.accent.opacity(option.votedByMe ? 0.19 : 0.09)
            .frame(width: geometry.size.width * fraction)
        }
      }
      .background(palette.selectedControl, in: RoundedRectangle(cornerRadius: 11))
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .overlay {
        RoundedRectangle(cornerRadius: 11)
          .stroke(
            option.votedByMe ? palette.accent.opacity(0.65) : palette.separator.opacity(0.55),
            lineWidth: 0.75
          )
      }
    }
    .buttonStyle(.plain)
    .disabled(poll.isClosed)
    .accessibilityIdentifier("ui_s6_poll_option_\(option.id)")
  }
}
