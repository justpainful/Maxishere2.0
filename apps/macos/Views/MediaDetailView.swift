import SwiftUI

struct MediaDetailView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var position = 0.32
  @State private var isPlaying = true
  @State private var volume = 0.72
  @State private var showsShare = false

  var body: some View {
    @Bindable var model = model
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)

      if let item = model.activeMedia {
        HStack(spacing: 0) {
          player(item: item, palette: palette)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          inspector(item: item, palette: palette)
            .frame(width: 330)
            .background(.ultraThinMaterial)
        }
      } else {
        EmptyStateView(symbol: "exclamationmark.triangle", title: "Media unavailable", message: "Close this window and choose another item.")
      }
    }
    .frame(width: 1120, height: 740)
    .accessibilityIdentifier("mac_media_detail")
    .sheet(isPresented: $model.isRatingPresented) {
      RatingEditorView()
        .environment(model)
    }
    .sheet(isPresented: $showsShare) {
      ShareToChatView(isPresented: $showsShare)
        .environment(model)
    }
  }

  private func player(item: MediaItem, palette: MaxPalette) -> some View {
    VStack(spacing: 0) {
      ZStack {
        MediaArtwork(item: item)
          .overlay(Color.black.opacity(0.12))

        if item.kind == .video {
          Button { isPlaying.toggle() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 34, weight: .bold))
              .frame(width: 78, height: 78)
              .glassEffect(.regular.interactive(), in: .circle)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.white)
          .accessibilityIdentifier("mac_player_toggle")
        }

        VStack {
          HStack {
            Label("Native SwiftUI Player", systemImage: "sparkles")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .glassEffect(.regular, in: .capsule)
            Spacer()
            Button {
              model.isMediaPresented = false
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(model.copy("done"))
            .accessibilityIdentifier("mac_player_close")
          }
          Spacer()
        }
        .foregroundStyle(.white)
        .padding(20)
      }

      if item.kind == .video {
        VStack(spacing: 10) {
          Slider(value: $position)
            .accessibilityIdentifier("mac_player_seek")
          HStack {
            Text(durationText((item.duration ?? 0) * position))
            Spacer()
            HStack(spacing: 8) {
              Image(systemName: "speaker.wave.2.fill")
              Slider(value: $volume).frame(width: 100)
            }
            Text(durationText(item.duration ?? 0))
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(palette.textSecondary)
        }
        .padding(18)
        .background(.ultraThinMaterial)
      }
    }
  }

  private func inspector(item: MediaItem, palette: MaxPalette) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 7) {
          Text(item.title).font(.largeTitle.bold())
          Text(item.subtitle).foregroundStyle(palette.textSecondary)
          Label(item.kind == .video ? "Video" : "Image", systemImage: item.kind == .video ? "play.fill" : "photo.fill")
            .font(.caption.weight(.semibold))
        }

        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            actionButton(symbol: item.isSaved ? "bookmark.fill" : "bookmark", label: item.isSaved ? "Saved" : model.copy("save"), tint: palette.accent) {
              model.toggleSaved(item.id)
            }
            actionButton(symbol: item.isOffline ? "checkmark.circle.fill" : "arrow.down.circle", label: item.isOffline ? "Offline" : model.copy("download"), tint: .green) {
              model.toggleOffline(item.id)
            }
            actionButton(symbol: "paperplane.fill", label: model.copy("share"), tint: palette.secondaryAccent) {
              showsShare = true
            }
          }
        }

        Button {
          model.isRatingPresented = true
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(model.copy("ratings")).font(.headline)
              Text("Two people, two independent scores")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            RatingBadge(title: "You", value: item.ownRating, tint: palette.accent)
            RatingBadge(title: "Nora", value: item.partnerRating, tint: palette.secondaryAccent)
          }
          .padding(15)
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mac_player_rate")

        Divider()

        VStack(alignment: .leading, spacing: 11) {
          Text("Details").font(.headline)
          LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
          LabeledContent("Added", value: item.uploadedAt.formatted(date: .abbreviated, time: .omitted))
          LabeledContent("Access", value: item.workspaceID == nil ? "Private" : "Shared")
          if let duration = item.duration {
            LabeledContent("Duration", value: durationText(duration))
          }
        }

        Divider()

        Button("Move to Trash", role: .destructive) {
          model.moveToTrash(item.id)
          dismiss()
        }
        .buttonStyle(.glass)
      }
      .padding(22)
    }
  }

  private func actionButton(symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image(systemName: symbol).font(.title3)
        Text(label).font(.caption2).lineLimit(1)
      }
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity)
      .frame(height: 64)
    }
    .buttonStyle(.glass)
  }

  private func durationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

private struct RatingEditorView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var ownRating = 0
  @State private var partnerRating = 0

  var body: some View {
    let palette = model.palette

    ZStack {
      MaxAtmosphere(palette: palette)
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(model.copy("ratings")).font(.largeTitle.bold())
            Text(model.activeMedia?.title ?? "Media").foregroundStyle(palette.textSecondary)
          }
          Spacer()
          Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
        }

        ratingRail(title: "Your rating", value: $ownRating, tint: palette.accent, identifier: "mac_rating_own")
        ratingRail(title: "Nora’s rating", value: $partnerRating, tint: palette.secondaryAccent, identifier: "mac_rating_partner")

        HStack {
          Text("Select the current score again to clear it.")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
          Spacer()
          Button(model.copy("save")) {
            guard let id = model.selectedMediaID else { return }
            model.setRatings(itemID: id, own: ownRating == 0 ? nil : ownRating, partner: partnerRating == 0 ? nil : partnerRating)
            dismiss()
          }
          .buttonStyle(.glassProminent)
          .accessibilityIdentifier("mac_rating_save")
        }
      }
      .padding(28)
      .glassEffect(.regular, in: .rect(cornerRadius: 26))
      .padding(30)
    }
    .frame(width: 720, height: 450)
    .onAppear {
      ownRating = model.activeMedia?.ownRating ?? 0
      partnerRating = model.activeMedia?.partnerRating ?? 0
    }
    .accessibilityIdentifier("mac_rating_editor")
  }

  private func ratingRail(title: String, value: Binding<Int>, tint: Color, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        Text(value.wrappedValue == 0 ? "—" : "\(value.wrappedValue)")
          .font(.title2.bold())
          .foregroundStyle(tint)
      }
      HStack(spacing: 7) {
        ForEach(1...10, id: \.self) { score in
          Button {
            value.wrappedValue = value.wrappedValue == score ? 0 : score
          } label: {
            Text("\(score)")
              .font(.caption.bold())
              .frame(maxWidth: .infinity)
              .frame(height: 34)
              .background(value.wrappedValue == score ? tint : .clear, in: RoundedRectangle(cornerRadius: 9))
              .foregroundStyle(value.wrappedValue == score ? .white : .primary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(7)
      .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }
    .accessibilityIdentifier(identifier)
  }
}

private struct ShareToChatView: View {
  @Environment(MaxDesktopModel.self) private var model
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Send to Chat").font(.largeTitle.bold())
        Spacer()
        Button { isPresented = false } label: { Image(systemName: "xmark") }.buttonStyle(.glass)
      }
      ForEach(model.threads) { thread in
        Button {
          isPresented = false
          model.selectedDestination = .chats
          model.selectedThreadID = thread.id
        } label: {
          HStack {
            Circle().fill(Color(hue: thread.hue, saturation: 0.65, brightness: 0.88)).frame(width: 34, height: 34)
            Text(thread.title).font(.headline)
            Spacer()
            Image(systemName: "paperplane.fill")
          }
          .padding(12)
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(24)
    .frame(width: 520, height: 430)
    .accessibilityIdentifier("mac_share_to_chat")
  }
}

