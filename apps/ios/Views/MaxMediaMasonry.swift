import SwiftUI

/// A column layout that gives every tile the shape of its own media.
///
/// `LazyVGrid` gives each cell the same height, so a library holding both
/// portrait and landscape video has to crop one of them to fit. That produced two
/// faults at once: portrait clips looked zoomed in, because a tall frame was
/// being filled into a short cell, and the rows read as unevenly spaced, because
/// tiles of very different natural shapes were forced onto a shared baseline.
///
/// This places each item in whichever column is currently shortest and sizes it
/// from its own aspect ratio. Gaps stay uniform — the same `spacing` horizontally
/// and vertically — while the tiles vary, which is what mixed media calls for.
///
/// No geometry reading is involved. Every column is the same width, so a tile's
/// height is proportional to `1 / aspectRatio`; balancing on that ratio alone is
/// equivalent to balancing on points, and it lets the layout size itself
/// naturally inside a scroll view.
struct MaxMediaMasonry<Item: Identifiable, Content: View>: View {
  let items: [Item]
  let columnCount: Int
  let spacing: CGFloat
  /// Width divided by height for an item. nil accepts the default shape.
  let aspectRatio: (Item) -> CGFloat?
  @ViewBuilder let content: (Item) -> Content

  /// Used when the server has not measured an item. Slightly taller than square
  /// suits a library that is mostly phone-shot video, without committing to it.
  private static var fallbackAspectRatio: CGFloat { 3.0 / 4.0 }

  init(
    items: [Item],
    columnCount: Int = 2,
    spacing: CGFloat = MaxSpace.sm,
    aspectRatio: @escaping (Item) -> CGFloat?,
    @ViewBuilder content: @escaping (Item) -> Content
  ) {
    self.items = items
    self.columnCount = max(1, columnCount)
    self.spacing = spacing
    self.aspectRatio = aspectRatio
    self.content = content
  }

  var body: some View {
    HStack(alignment: .top, spacing: spacing) {
      ForEach(Array(balancedColumns.enumerated()), id: \.offset) { _, column in
        LazyVStack(spacing: spacing) {
          ForEach(column) { item in
            content(item)
              // The layout owns the tile's shape so the content never has to
              // crop itself into a frame that does not match its media.
              .aspectRatio(ratio(for: item), contentMode: .fit)
          }
        }
        .frame(maxWidth: .infinity, alignment: .top)
      }
    }
  }

  private func ratio(for item: Item) -> CGFloat {
    guard let value = aspectRatio(item), value > 0 else { return Self.fallbackAspectRatio }
    return value
  }

  /// Distributes items into columns, always appending to the shortest.
  ///
  /// Deterministic: the same items in the same order always produce the same
  /// arrangement, so scrolling away and back never reshuffles the grid.
  private var balancedColumns: [[Item]] {
    var buckets = Array(repeating: [Item](), count: columnCount)
    var relativeHeights = Array(repeating: CGFloat.zero, count: columnCount)

    for item in items {
      var shortest = 0
      for index in 1..<columnCount where relativeHeights[index] < relativeHeights[shortest] {
        shortest = index
      }
      buckets[shortest].append(item)
      relativeHeights[shortest] += 1 / ratio(for: item)
    }
    return buckets
  }
}
