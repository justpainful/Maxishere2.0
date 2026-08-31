import SwiftUI

struct MaxPluginTabBar: View {
  @Binding var selection: AppTab

  @Environment(\.maxThemePalette) private var palette
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  init(selection: Binding<AppTab>) {
    self._selection = selection
  }

  // Get active tabs (possibly reordered by active plugin contribution)
  private var tabItems: [AppTab] {
    if let contribution = PluginStore.shared.navigationContribution,
       let reorder = contribution.reorder {
      // Filter out invalid items, keep valid ones
      return reorder.compactMap { AppTab(rawValue: $0) }
    }
    return AppTab.allCases
  }

  var body: some View {
    HStack(spacing: MaxSpace.xxs) {
      ForEach(tabItems) { tab in
        let isSelected = selection == tab
        
        Button {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            selection = tab
          }
        } label: {
          VStack(spacing: 4) {
            Image(systemName: tab.symbolName)
              .font(.system(size: 20, weight: isSelected ? .bold : .medium))
            Text(tab.titleKey)
              .font(.system(size: 10, weight: .bold))
              .lineLimit(1)
          }
          .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, MaxSpace.xs)
          .background {
            if isSelected {
              tabIndicatorBackground
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityIdentifier("ui_tab_\(tab.rawValue)")
      }
    }
    .padding(.horizontal, MaxSpace.sm)
    .padding(.vertical, MaxSpace.xs)
    .background {
      tabBarContainerBackground
    }
  }

  // Custom indicator backgrounds per active visual plugin
  @ViewBuilder
  private var tabIndicatorBackground: some View {
    if let visual = PluginStore.shared.activeVisualPlugin {
      visual.decorateTabIndicator(palette: palette)
    } else {
      Capsule()
        .fill(palette.selectedControl)
    }
  }

  // Custom bar background container per active visual plugin
  @ViewBuilder
  private var tabBarContainerBackground: some View {
    if let visual = PluginStore.shared.activeVisualPlugin {
      visual.decorateTabBarContainer(palette: palette, reduceTransparency: reduceTransparency)
    } else {
      let shape = Capsule()
      ZStack {
        if #available(iOS 26.0, *) {
          Color.clear
            .glassEffect(.regular.tint(Color.white.opacity(0.16)), in: shape)
        } else {
          shape.fill(palette.primaryContentSurface.opacity(0.92))
        }
        shape.stroke(Color.white.opacity(0.24), lineWidth: 1)
      }
    }
  }
}


