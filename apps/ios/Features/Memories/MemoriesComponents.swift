import SwiftUI
import UIKit

struct MemoriesPrivacyBadge: View {
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Label("memories.local.badge", systemImage: "lock.iphone")
      .font(isCouncil ? CouncilTypography.eyebrow : MaxTypography.caption.weight(.semibold))
      .foregroundStyle(isCouncil ? AnyShapeStyle(CouncilColor.primaryText) : AnyShapeStyle(MaxColor.textPrimary))
      .padding(.horizontal, MaxSpace.sm)
      .padding(.vertical, MaxSpace.xs)
      .background {
        if isCouncil {
          Capsule()
            .fill(CouncilColor.obsidianSurface)
            .overlay { Capsule().stroke(CouncilColor.quietBorder, lineWidth: 1) }
        } else {
          Color.clear.glassEffect(.regular, in: .capsule)
        }
      }
      .accessibilityIdentifier("memories.local.badge")
  }
}

struct MemoriesModeRail: View {
  let store: MemoriesStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return ScrollView(.horizontal, showsIndicators: false) {
      Group {
        if isCouncil {
          HStack(spacing: MaxSpace.xs) {
            ForEach(MemoryMode.allCases) { mode in
              let isSelected = store.filter.mode == mode
              Button {
                select(mode)
              } label: {
                Text(mode.titleKey)
                  .font(CouncilTypography.eyebrow)
                  .foregroundStyle(isSelected ? CouncilColor.primaryText : CouncilColor.secondaryText)
                  .padding(.horizontal, MaxSpace.sm)
                  .frame(minHeight: 42)
                  .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                      .fill(isSelected ? CouncilColor.obsidianSurfaceSelected : CouncilColor.stoneSurface)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                      .stroke(isSelected ? CouncilColor.activeCrimson : CouncilColor.quietBorder, lineWidth: 1)
                  }
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(isSelected ? .isSelected : [])
              .accessibilityIdentifier("memories.mode.\(mode.rawValue)")
            }
          }
        } else {
          GlassEffectContainer(spacing: MaxSpace.xs) {
            LazyHStack(spacing: MaxSpace.xs) {
              ForEach(MemoryMode.allCases) { mode in
                Button {
                  select(mode)
                } label: {
                  Text(mode.titleKey)
                    .font(MaxTypography.caption.weight(.semibold))
                    .foregroundStyle(MaxColor.textPrimary)
                    .padding(.horizontal, MaxSpace.sm)
                    .frame(minHeight: 42)
                    .contentShape(Capsule())
                }
                .buttonStyle(.glass)
                .tint(store.filter.mode == mode ? MaxColor.accent : nil)
                .accessibilityAddTraits(store.filter.mode == mode ? .isSelected : [])
                .accessibilityIdentifier("memories.mode.\(mode.rawValue)")
              }
            }
          }
        }
      }
      .padding(.horizontal, MaxSpace.md)
    }
    .contentMargins(.vertical, 2, for: .scrollContent)
  }

  private func select(_ mode: MemoryMode) {
    if reduceMotion || !motionEnabled || store.calmMotionEnabled {
      store.selectMode(mode)
    } else {
      withAnimation(MaxMotion.quick) { store.selectMode(mode) }
    }
  }
}

struct MemoriesHeroCard: View {
  let store: MemoriesStore
  let candidate: MemoryCandidate
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Button(action: store.openSequence) {
      ZStack(alignment: .bottomLeading) {
        MemoryThumbnailView(store: store, candidate: candidate)
          .frame(height: 360)

        LinearGradient(
          colors: [.clear, Color.black.opacity(0.14), Color.black.opacity(0.82)],
          startPoint: .top,
          endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          Label(store.filter.mode.titleKey, systemImage: "sparkles")
            .font(isCouncil ? CouncilTypography.eyebrow : MaxTypography.caption.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.86))
          Text(verbatim: candidate.title)
            .font(isCouncil ? .system(.title, design: .serif).weight(.bold) : .system(.title, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
          HStack {
            Text(verbatim: candidate.subtitle)
              .font(isCouncil ? CouncilTypography.caption : MaxTypography.caption)
              .foregroundStyle(Color.white.opacity(0.78))
            Spacer()
            Label("memories.browse", systemImage: "arrow.up")
              .font(isCouncil ? CouncilTypography.caption.weight(.bold) : MaxTypography.caption.weight(.bold))
              .foregroundStyle(.white)
              .padding(.horizontal, MaxSpace.sm)
              .padding(.vertical, MaxSpace.xs)
              .background {
                if isCouncil {
                  Capsule()
                    .fill(CouncilColor.royalCrimson)
                } else {
                  Color.clear.glassEffect(.regular.interactive(), in: .capsule)
                }
              }
          }
        }
        .padding(MaxSpace.lg)
      }
      .background {
        if isCouncil {
          CouncilCutShape(cornerRadius: MaxRadius.large, cutDepth: 20)
            .fill(CouncilColor.obsidianSurface)
            .overlay {
              CouncilCutShape(cornerRadius: MaxRadius.large, cutDepth: 20)
                .stroke(CouncilColor.quietBorder, lineWidth: 1)
            }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("memories.browse"))
    .accessibilityValue(Text(verbatim: candidate.title))
    .accessibilityIdentifier("memories.start")
  }
}

struct MemoriesCollectionBar: View {
  let store: MemoriesStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Group {
      if isCouncil {
        HStack(spacing: MaxSpace.xs) {
          ForEach(MemoryCollectionScope.allCases) { scope in
            let isSelected = store.collectionScope == scope
            Button {
              select(scope)
            } label: {
              VStack(spacing: 2) {
                Text(scope.titleKey)
                  .font(CouncilTypography.eyebrow)
                Text(count(for: scope), format: .number)
                  .font(.system(.headline, design: .serif).weight(.bold))
              }
              .foregroundStyle(isSelected ? CouncilColor.primaryText : CouncilColor.secondaryText)
              .frame(maxWidth: .infinity, minHeight: 58)
              .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .fill(isSelected ? CouncilColor.obsidianSurfaceSelected : CouncilColor.stoneSurface)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(isSelected ? CouncilColor.activeCrimson : CouncilColor.quietBorder, lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("memories.collection.\(scope.rawValue)")
          }
        }
      } else {
        GlassEffectContainer(spacing: MaxSpace.xs) {
          HStack(spacing: MaxSpace.xs) {
            ForEach(MemoryCollectionScope.allCases) { scope in
              Button {
                select(scope)
              } label: {
                VStack(spacing: 2) {
                  Text(scope.titleKey)
                    .font(MaxTypography.caption.weight(.semibold))
                  Text(count(for: scope), format: .number)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                }
                .foregroundStyle(MaxColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 58)
              }
              .buttonStyle(.glass)
              .tint(store.collectionScope == scope ? MaxColor.accent : nil)
              .accessibilityAddTraits(store.collectionScope == scope ? .isSelected : [])
              .accessibilityIdentifier("memories.collection.\(scope.rawValue)")
            }
          }
        }
      }
    }
  }

  private func count(for scope: MemoryCollectionScope) -> Int {
    switch scope {
    case .all: store.visibleCandidates.count
    case .saved: store.savedCandidates.count
    case .hidden: store.hiddenCandidates.count
    }
  }

  private func select(_ scope: MemoryCollectionScope) {
    if reduceMotion || !motionEnabled || store.calmMotionEnabled {
      store.collectionScope = scope
    } else {
      withAnimation(MaxMotion.quick) { store.collectionScope = scope }
    }
  }
}

struct MemoriesLayoutPicker: View {
  let store: MemoriesStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.maxMotionEnabled) private var motionEnabled
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Group {
      if isCouncil {
        HStack(spacing: MaxSpace.xs) {
          ForEach(MemoryLibraryLayout.allCases) { layout in
            let isSelected = store.libraryLayout == layout
            Button {
              select(layout)
            } label: {
              Label(layout.titleKey, systemImage: layout.systemName)
                .font(CouncilTypography.caption.weight(.semibold))
                .foregroundStyle(isSelected ? CouncilColor.primaryText : CouncilColor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? CouncilColor.obsidianSurfaceSelected : CouncilColor.stoneSurface)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? CouncilColor.activeCrimson : CouncilColor.quietBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
          }
        }
      } else {
        GlassEffectContainer(spacing: MaxSpace.xs) {
          HStack(spacing: MaxSpace.xs) {
            ForEach(MemoryLibraryLayout.allCases) { layout in
              Button {
                select(layout)
              } label: {
                Label(layout.titleKey, systemImage: layout.systemName)
                  .font(MaxTypography.caption.weight(.semibold))
                  .frame(maxWidth: .infinity, minHeight: 38)
              }
              .buttonStyle(.glass)
              .tint(store.libraryLayout == layout ? MaxColor.accent : nil)
              .accessibilityAddTraits(store.libraryLayout == layout ? .isSelected : [])
            }
          }
        }
      }
    }
  }

  private func select(_ layout: MemoryLibraryLayout) {
    if reduceMotion || !motionEnabled || store.calmMotionEnabled {
      store.libraryLayout = layout
    } else {
      withAnimation(MaxMotion.quick) { store.libraryLayout = layout }
    }
  }
}

struct MemoriesGrid: View {
  let store: MemoriesStore
  let candidates: [MemoryCandidate]

  private let columns = [
    GridItem(.flexible(minimum: 120), spacing: MaxSpace.xs),
    GridItem(.flexible(minimum: 120), spacing: MaxSpace.xs),
  ]

  var body: some View {
    LazyVGrid(columns: columns, spacing: MaxSpace.xs) {
      ForEach(candidates) { candidate in
        MemoryGridTile(store: store, candidate: candidate)
      }
    }
  }
}

struct MemoryGridTile: View {
  let store: MemoriesStore
  let candidate: MemoryCandidate
  @Environment(\.appTheme) private var appTheme

  var body: some View {
    let isCouncil = appTheme == .council
    return Button {
      store.prepareOpen(candidate: candidate)
    } label: {
      ZStack(alignment: .bottomLeading) {
        MemoryThumbnailView(store: store, candidate: candidate)
          .frame(height: 198)

        LinearGradient(
          colors: [.clear, Color.black.opacity(0.12), Color.black.opacity(0.74)],
          startPoint: .top,
          endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: MaxSpace.xxs) {
          Text(verbatim: candidate.title)
            .font(isCouncil ? .system(.subheadline, design: .serif).weight(.bold) : .system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(2)
          Text(candidate.year, format: .number.grouping(.never))
            .font(isCouncil ? CouncilTypography.caption : MaxTypography.caption)
            .foregroundStyle(Color.white.opacity(0.78))
        }
        .padding(MaxSpace.sm)
      }
      .background {
        if isCouncil {
          RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
            .fill(CouncilColor.stoneSurface)
            .overlay {
              RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous)
                .stroke(CouncilColor.quietBorder, lineWidth: 1)
            }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: MaxRadius.medium, style: .continuous))
    }
    .buttonStyle(.plain)
    .contextMenu {
      if store.collectionScope == .hidden {
        Button("memories.restore", systemImage: "eye") {
          store.restore(candidate)
        }
      } else {
        Button(
          store.savedKeys.contains(candidate.key) ? "memories.unsave" : "memories.saved",
          systemImage: store.savedKeys.contains(candidate.key) ? "bookmark.slash" : "bookmark"
        ) {
          store.toggleSaved(candidate)
        }
        Button("memories.hide", systemImage: "eye.slash") {
          store.hide(candidate)
        }
      }
    }
    .accessibilityIdentifier("memories.tile.\(candidate.id)")
  }
}

struct MemoriesTimeline: View {
  let store: MemoriesStore

  var body: some View {
    LazyVStack(alignment: .leading, spacing: MaxSpace.lg, pinnedViews: [.sectionHeaders]) {
      ForEach(store.timelineGroups, id: \.id) { group in
        Section {
          MemoriesGrid(store: store, candidates: group.items)
        } header: {
          Text(verbatim: group.title)
            .font(MaxTypography.sectionTitle)
            .foregroundStyle(MaxColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, MaxSpace.xs)
            .background(MaxColor.canvas)
        }
      }
    }
  }
}

struct MemoriesPlaces: View {
  let store: MemoriesStore

  var body: some View {
    LazyVStack(alignment: .leading, spacing: MaxSpace.lg) {
      if store.placeGroups.isEmpty {
        MaxEmptyState(
          title: "memories.places.empty.title",
          subtitle: "memories.places.empty.subtitle",
          symbol: "map"
        )
      } else {
        ForEach(store.placeGroups, id: \.id) { group in
          VStack(alignment: .leading, spacing: MaxSpace.sm) {
            HStack {
              Label {
                Text(verbatim: group.title)
              } icon: {
                Image(systemName: "location.fill")
              }
              .font(MaxTypography.sectionTitle)
              .foregroundStyle(MaxColor.textPrimary)
              Spacer()
              Text(group.items.count, format: .number)
                .font(MaxTypography.caption.weight(.bold))
                .foregroundStyle(MaxColor.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
              LazyHStack(spacing: MaxSpace.xs) {
                ForEach(group.items) { candidate in
                  MemoryGridTile(store: store, candidate: candidate)
                    .frame(width: 156)
                }
              }
            }
          }
          .padding(MaxSpace.md)
          .background(
            MaxColor.surface,
            in: RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous)
          )
        }
      }
    }
  }
}

struct MemoriesPermissionState: View {
  let status: MemoryPhotoAuthorizationStatus
  let requestAccess: () -> Void
  @Environment(\.openURL) private var openURL

  var body: some View {
    MaxContentSurface {
      VStack(alignment: .leading, spacing: MaxSpace.md) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(MaxColor.accent)
        Text("memories.permission.title")
          .font(.system(.title3, design: .rounded).weight(.bold))
          .foregroundStyle(MaxColor.textPrimary)
        Text("memories.permission.subtitle")
          .font(MaxTypography.body)
          .foregroundStyle(MaxColor.textSecondary)
        if status == .notDetermined {
          Button("memories.permission.allow", action: requestAccess)
            .buttonStyle(MaxPrimaryButtonStyle())
            .accessibilityIdentifier("memories.permission.allow")
        } else {
          Button("memories.permission.open_settings", action: openSettings)
            .buttonStyle(MaxPrimaryButtonStyle())
        }
      }
    }
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
  }
}

struct MemoriesViewerActionButton: View {
  let systemName: String
  let accessibilityLabel: LocalizedStringKey
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .contentShape(Circle())
    }
    .buttonStyle(.glass)
    .accessibilityLabel(accessibilityLabel)
  }
}

struct MemoriesViewerGlassPanel<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(.horizontal, MaxSpace.sm)
      .padding(.vertical, MaxSpace.xs)
      .glassEffect(.regular, in: .rect(cornerRadius: MaxRadius.medium))
  }
}
