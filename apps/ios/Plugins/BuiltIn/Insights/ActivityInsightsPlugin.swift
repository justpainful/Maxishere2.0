import SwiftUI

final class ActivityInsightsPlugin: MaxPlugin, @unchecked Sendable {
  let manifest: MaxPluginManifest
  let context: MaxPluginContext

  init() {
    let author = PluginAuthor(name: "Max Lab", email: "insights@max.app", website: nil)
    self.manifest = MaxPluginManifest(
      schemaVersion: 1,
      id: "com.max.plugin.activity-insights",
      name: "Activity Insights",
      version: "0.8.0-experimental",
      description: "Summarizes local Max activity metadata, showing aggregates and media distributions.",
      longDescription: "Gain insight into your library. This experimental feature plugin analyzes local file records to present total storage distribution, favorite counts, and kind distributions without inspecting private content or sending data off-device.",
      author: author,
      category: .feature,
      tags: ["experimental", "insights", "analytics"],
      icon: PluginIcon(
        light: AssetReference(type: "system", name: "chart.bar.fill"),
        dark: AssetReference(type: "system", name: "chart.bar.fill"),
        monochrome: nil,
        animated: nil
      ),
      hero: nil,
      previews: [],
      capabilities: [.customRoute, .customWidget, .settingsPage],
      permissions: [.readPublicMetadata, .modifyAppearance],
      network: nil,
      minimumAppVersion: "26.0",
      maximumAppVersion: nil
    )
    self.context = MaxPluginContext(pluginId: "com.max.plugin.activity-insights")
  }

  func register(using context: MaxPluginContext) throws {
    // Register Insights view route
    context.routes.register(
      id: "insights",
      title: "Activity Insights",
      iconName: "chart.bar"
    ) { _ in
      AnyView(ActivityInsightsView(context: context))
    }

    // Register Insights Widget
    context.widgets.register(
      id: "insights:widget",
      pointId: "home:afterHero",
      title: "Insights",
      accessibilityLabel: "Library Insights Widget"
    ) {
      AnyView(ActivityInsightsWidget(context: context))
    }
  }

  func settingsView() -> AnyView? {
    AnyView(
      VStack(alignment: .leading, spacing: MaxSpace.xxs) {
        Text(verbatim: "Insights Settings")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MaxColor.textPrimary)
        Text(verbatim: "Local aggregation: ON")
          .font(.caption)
          .foregroundStyle(MaxColor.textSecondary)
      }
      .padding()
      .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    )
  }
}

// MARK: - Activity Insights View
struct ActivityInsightsView: View {
  let context: MaxPluginContext
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        // Statistics overview card
        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          Text(verbatim: "Library Metadata Aggregates")
            .font(.headline)
            .foregroundStyle(palette.primaryText)
          
          if let library = context.library {
            let totalFiles = library.getMediaItemsCount()
            let favorites = library.getFavoritesCount()
            let storage = library.getStorageUsed()
            
            HStack(spacing: MaxSpace.md) {
              StatCard(title: "Total Files", value: "\(totalFiles)", icon: "doc.fill", color: palette.accent)
              StatCard(title: "Favorites", value: "\(favorites)", icon: "heart.fill", color: .red)
            }
            
            StatCard(
              title: "Estimated Storage",
              value: String(format: "%.1f MB", Double(storage) / (1024.0 * 1024.0)),
              icon: "internaldrive.fill",
              color: .blue
            )
            
            Text(verbatim: "Kind Distribution")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(palette.primaryText)
              .padding(.top, MaxSpace.xs)
            
            let dist = library.getMediaDistribution()
            if dist.isEmpty {
              Text(verbatim: "No distribution metadata available")
                .font(.caption)
                .foregroundStyle(palette.tertiaryText)
            } else {
              ForEach(dist.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                HStack {
                  Image(systemName: key == "video" ? "video.fill" : "photo.fill")
                    .foregroundStyle(palette.secondaryText)
                  Text(verbatim: key.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.secondaryText)
                  Spacer()
                  Text(verbatim: "\(val) files")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                }
                .padding(.vertical, 4)
              }
            }
          } else {
            // Unavailable/Empty State
            VStack(spacing: MaxSpace.xs) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
              Text(verbatim: "Max Library Integration Unavailable")
                .font(.headline)
              Text(verbatim: "Activate the plugin and ensure you have read public metadata permissions.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding()
          }
        }
        .padding(MaxSpace.md)
        .background(palette.primaryContentSurface)
        .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
        .overlay {
          RoundedRectangle(cornerRadius: MaxRadius.medium)
            .stroke(palette.separator, lineWidth: 1)
        }
      }
      .padding(MaxSpace.md)
    }
    .background(palette.canvas)
  }
}

// MARK: - Activity Insights Widget
struct ActivityInsightsWidget: View {
  let context: MaxPluginContext
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    Button {
      // Open the insights route path via navigation proxy
      context.navigation?.openRoute(routeId: "insights")
    } label: {
      HStack(spacing: MaxSpace.md) {
        Image(systemName: "chart.bar.xaxis")
          .font(.title2)
          .foregroundStyle(palette.accent)
          .frame(width: 44, height: 44)
          .background(palette.selectedControl, in: Circle())
        
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "Library Analysis")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primaryText)
          if let library = context.library {
            Text(verbatim: "Total Items: \(library.getMediaItemsCount()) | Favorites: \(library.getFavoritesCount())")
              .font(.caption)
              .foregroundStyle(palette.secondaryText)
          } else {
            Text(verbatim: "Tap to review library statistics")
              .font(.caption)
              .foregroundStyle(palette.tertiaryText)
          }
        }
        Spacer()
        Image(systemName: "chevron.forward")
          .foregroundStyle(palette.tertiaryText)
      }
      .padding(MaxSpace.md)
      .background(palette.primaryContentSurface)
      .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MaxRadius.medium)
          .stroke(palette.separator, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Statistics Card Helper
struct StatCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color
  @Environment(\.maxThemePalette) private var palette

  var body: some View {
    HStack {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(color)
        .frame(width: 36, height: 36)
        .background(color.opacity(0.12), in: Circle())
      
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
          .font(.caption2)
          .foregroundStyle(palette.secondaryText)
        Text(verbatim: value)
          .font(.headline)
          .foregroundStyle(palette.primaryText)
      }
      Spacer()
    }
    .padding(MaxSpace.sm)
    .background(palette.elevatedContentSurface)
    .clipShape(RoundedRectangle(cornerRadius: MaxRadius.small))
  }
}


