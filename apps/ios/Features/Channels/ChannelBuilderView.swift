import SwiftUI

/// Writing a channel's rule.
///
/// Each facet is a Menu of whole meanings, so a contradiction cannot be
/// expressed: choosing an answer replaces the previous one rather than stacking
/// beside it. The count underneath runs the SAME evaluation that freezes a
/// programme, so it cannot promise a channel the server will not produce.
struct ChannelBuilderView: View {
  let existing: ChannelDoc?

  @Environment(MaxAppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.maxThemePalette) private var palette

  @State private var input: ChannelInput
  @State private var preview: ChannelPreview?
  @State private var busy = false
  @State private var failure: String?
  @State private var confirmingDelete = false
  @State private var previewTask: Task<Void, Never>?

  init(existing: ChannelDoc?) {
    self.existing = existing
    _input = State(
      initialValue: existing.map {
        ChannelInput(name: $0.name, rule: $0.rule, ordering: $0.ordering, alwaysRunning: $0.alwaysRunning)
      } ?? ChannelInput(name: "", rule: ChannelRule(), ordering: .shuffle, alwaysRunning: true)
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(String(localized: "channels.builder.name_placeholder"), text: $input.name)
            .accessibilityIdentifier("ui_channel_name")
        } header: {
          Text("channels.builder.name")
        }

        Section {
          ForEach(facets) { facet in
            facetRow(facet)
          }
        } header: {
          Text("channels.builder.include")
        } footer: {
          Text(conditionCount == 0
               ? "channels.builder.no_conditions"
               : "channels.builder.condition_count \(conditionCount)")
        }

        Section {
          Picker(selection: $input.ordering) {
            Text("channels.order.shuffle").tag(ChannelOrdering.shuffle)
            Text("channels.order.newest").tag(ChannelOrdering.newest)
            Text("channels.order.rating").tag(ChannelOrdering.rating)
          } label: {
            Text("channels.builder.order")
          }
          .pickerStyle(.segmented)

          Toggle(isOn: $input.alwaysRunning) {
            VStack(alignment: .leading, spacing: 2) {
              Text("channels.builder.always_running")
              // The hint states what the CURRENT setting means, not what the
              // switch does — the switch already shows that.
              Text(input.alwaysRunning
                   ? "channels.builder.always_running_on"
                   : "channels.builder.always_running_off")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            }
          }
        }

        Section {
          previewBody
        } header: {
          Text("channels.builder.would_hold")
        }

        if existing != nil {
          Section {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Label("channels.builder.delete", systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle(Text(existing == nil ? "channels.builder.title" : "channels.builder.edit"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "action.cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: existing == nil ? "channels.builder.create" : "action.save")) {
            Task { await save() }
          }
          .disabled(input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
        }
      }
      .alert(
        Text("channels.builder.delete"),
        isPresented: $confirmingDelete,
        actions: {
          Button(String(localized: "action.cancel"), role: .cancel) {}
          Button(String(localized: "channels.builder.delete"), role: .destructive) {
            Task { await remove() }
          }
        },
        message: { Text("channels.builder.delete_message") }
      )
      .onChange(of: input) { _, _ in schedulePreview() }
      .task {
        await model.libraryStore.load()
        schedulePreview()
      }
      .onDisappear { previewTask?.cancel() }
    }
  }

  private var facets: [ChannelFacet] {
    // CollectionSummary names the field `name`, and it is optional: an
    // untitled collection still has to be pickable, so it falls back to its
    // own label rather than vanishing from the list.
    ChannelFacets.all(
      collections: (model.libraryStore.phase.value?.collections ?? []).map {
        (id: $0.id, title: $0.name ?? String(localized: "library.untitled_collection"))
      }
    )
  }

  private var conditionCount: Int {
    facets.filter { $0.selection(input.rule) != "any" }.count
  }

  private func facetRow(_ facet: ChannelFacet) -> some View {
    let current = facet.current(input.rule)
    return Menu {
      // A Picker inside a Menu is the platform's own way to show one answer
      // ticked among several — it replaces a set of switches that could
      // otherwise be left contradicting one another.
      ForEach(facet.options) { option in
        Button {
          var rule = input.rule
          option.apply(&rule)
          input.rule = rule
        } label: {
          if option.id == current.id {
            Label(option.label, systemImage: "checkmark")
          } else {
            Text(option.label)
          }
        }
      }
    } label: {
      HStack {
        Label(facet.label, systemImage: facet.symbol)
          .foregroundStyle(palette.primaryText)
        Spacer(minLength: MaxSpace.xs)
        Text(current.label)
          .foregroundStyle(current.id == "any" ? palette.secondaryText : palette.accent)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
          .foregroundStyle(palette.tertiaryText)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .accessibilityIdentifier("ui_channel_facet_\(facet.id)")
  }

  @ViewBuilder
  private var previewBody: some View {
    HStack(alignment: .firstTextBaseline, spacing: MaxSpace.xs) {
      Text(preview.map { String($0.count) } ?? "—")
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .monospacedDigit()
      if let preview {
        Text("channels.clips_and_loop \(preview.count) \(ChannelRuleText.duration(preview.totalSeconds))")
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
      }
    }

    if let preview, preview.count == 0 {
      Text("channels.builder.no_matches")
        .font(.caption)
        .foregroundStyle(palette.warning)
    }

    ForEach(preview?.media ?? []) { ref in
      HStack(spacing: MaxSpace.sm) {
        if let poster = ref.posterUrl, let url = URL(string: poster) {
          MaxAsyncImage(url: url) { phase in
            if let image = phase.image {
              image.resizable().aspectRatio(contentMode: .fill)
            } else {
              palette.elevatedContentSurface
            }
          }
          .frame(width: 56, height: 38)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        Text(ref.name).font(.caption).lineLimit(1)
      }
    }

    if let failure {
      // A refused rule says WHICH contradiction it is; that sentence is the
      // whole point of refusing it.
      Text(failure)
        .font(.caption)
        .foregroundStyle(palette.destructive)
    }
  }

  /// Debounced: the count is a real evaluation, not a cached number.
  private func schedulePreview() {
    previewTask?.cancel()
    previewTask = Task {
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled else { return }
      var probe = input
      if probe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { probe.name = "preview" }
      let result = await model.channelStore.preview(probe)
      guard !Task.isCancelled else { return }
      preview = result
    }
  }

  private func save() async {
    guard !busy else { return }
    busy = true
    failure = nil
    let saved: ChannelDoc?
    if let existing {
      saved = await model.channelStore.update(id: existing.id, input: input)
    } else {
      saved = await model.channelStore.create(input)
    }
    busy = false
    if saved != nil {
      dismiss()
    } else {
      failure = model.channelStore.failure ?? String(localized: "channels.builder.save_failed")
    }
  }

  private func remove() async {
    guard let existing, !busy else { return }
    busy = true
    let ok = await model.channelStore.delete(id: existing.id)
    busy = false
    if ok { dismiss() } else { failure = model.channelStore.failure }
  }
}
