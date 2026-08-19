import SwiftUI

struct MaxS6ComposerSuggestions: View {
  @Environment(\.maxThemePalette) private var palette
  let mentionQuery: String?
  let commandQuery: String?
  let members: [ChatGroupMember]
  let selectMention: (ChatGroupMember) -> Void
  let selectCommand: (MaxS6ComposerCommand) -> Void

  private var matchingMembers: [ChatGroupMember] {
    guard let mentionQuery else { return [] }
    return members.filter {
      mentionQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(mentionQuery)
    }.prefix(6).map { $0 }
  }

  private var matchingCommands: [MaxS6ComposerCommand] {
    guard let commandQuery else { return [] }
    return MaxS6ComposerCommand.allCases.filter {
      commandQuery.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(commandQuery)
    }
  }

  var body: some View {
    if !matchingMembers.isEmpty || !matchingCommands.isEmpty {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(matchingMembers) { member in
            Button {
              selectMention(member)
            } label: {
              HStack(spacing: 10) {
                MaxAvatar(name: member.displayName, imageURL: member.avatarUrl, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                  Text(verbatim: member.displayName)
                    .font(.subheadline.weight(.semibold))
                  Text(verbatim: member.role.capitalized)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Image(systemName: "at")
                  .foregroundStyle(palette.accent)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
          }

          ForEach(matchingCommands) { command in
            Button {
              selectCommand(command)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: command.icon)
                  .font(.body.weight(.semibold))
                  .foregroundStyle(palette.accent)
                  .frame(width: 34, height: 34)
                  .background(palette.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                  Text(verbatim: "/\(command.rawValue)")
                    .font(.subheadline.weight(.semibold).monospaced())
                  Text(command.subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                }
                Spacer()
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(maxHeight: 230)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(palette.separator.opacity(0.6), lineWidth: 0.75)
      }
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .accessibilityIdentifier("ui_s6_composer_suggestions")
    }
  }
}

enum MaxS6ComposerCommand: String, CaseIterable, Identifiable {
  case poll
  case shrug
  case tableflip

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .poll: "chart.bar.fill"
    case .shrug: "person.crop.circle.badge.questionmark"
    case .tableflip: "table.furniture.fill"
    }
  }

  var subtitle: LocalizedStringKey {
    switch self {
    case .poll: "chat.command.poll"
    case .shrug: "chat.command.shrug"
    case .tableflip: "chat.command.tableflip"
    }
  }
}
