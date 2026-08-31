import SwiftUI

/// Renders registered widget contributions generically at target extension points.
struct PluginExtensionPointView: View {
  let pointId: String

  init(pointId: String) {
    self.pointId = pointId
  }

  var body: some View {
    let contributions = PluginStore.shared.widgetContributions(for: pointId)
    if !contributions.isEmpty {
      VStack(spacing: MaxSpace.md) {
        ForEach(contributions) { contribution in
          PluginWidgetRowView(contribution: contribution)
        }
      }
    }
  }
}

/// Helper row view ensuring stable SwiftUI identity and scoped rendering of plugin widgets.
struct PluginWidgetRowView: View {
  let contribution: PluginWidgetContribution

  var body: some View {
    contribution.builder()
      .id(contribution.widgetId) // stable SwiftUI identity
      .accessibilityElement(children: .combine)
      .accessibilityLabel(contribution.accessibilityLabel ?? contribution.title)
  }
}

/// Identifiable route wrapper for sheet bindings.
struct IdentifiableRoute: Identifiable, Hashable {
  let id: String
  init(id: String) {
    self.id = id
  }
}


