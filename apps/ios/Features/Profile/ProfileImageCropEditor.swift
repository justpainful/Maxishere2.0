import SwiftUI
import UIKit

struct ProfileCropRequest: Identifiable {
  let id = UUID()
  let kind: ProfileImageKind
  let image: UIImage
}

struct ProfileImageCropEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let request: ProfileCropRequest
  let completion: (UIImage) -> Void

  @State private var zoom: CGFloat = 1
  @State private var settledOffset: CGSize = .zero
  @State private var canvasSize: CGSize = .zero
  @State private var isRendering = false
  @State private var renderFailed = false
  @GestureState private var dragOffset: CGSize = .zero

  private var zoomReadout: String {
    "\(Double(zoom).formatted(.number.precision(.fractionLength(1))))×"
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: MaxSpace.lg) {
        GeometryReader { proxy in
          cropPreview(size: proxy.size)
            .onAppear { canvasSize = proxy.size }
            .onChange(of: proxy.size) { _, size in canvasSize = size }
        }
        .aspectRatio(request.kind.cropAspectRatio, contentMode: .fit)
        .clipShape(request.kind.previewShape)
        .overlay {
          request.kind.previewShape
            .stroke(.white.opacity(0.82), lineWidth: 2)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        .padding(.horizontal, MaxSpace.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(request.kind.cropTitleKey))
        .accessibilityHint(Text("profile.crop.drag_hint"))
        .accessibilityIdentifier("ui_profile_crop_canvas")

        VStack(alignment: .leading, spacing: MaxSpace.sm) {
          HStack {
            Label("profile.crop.zoom", systemImage: "plus.magnifyingglass")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text(verbatim: zoomReadout)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(MaxColor.textSecondary)
          }
          .accessibilityHidden(true)

          Slider(value: $zoom, in: 1...3, step: 0.05) {
            Text("profile.crop.zoom")
          }
          .accessibilityValue(Text(verbatim: zoomReadout))
          .accessibilityIdentifier("ui_profile_crop_zoom")
          .onChange(of: zoom) { _, _ in
            settledOffset = clamped(settledOffset, within: canvasSize)
          }
        }
        .padding(.horizontal, MaxSpace.lg)

        Button("profile.crop.reset", systemImage: "arrow.counterclockwise") {
          withAnimation(reduceMotion ? nil : MaxMotion.quick) {
            zoom = 1
            settledOffset = .zero
          }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("ui_profile_crop_reset")

        Spacer(minLength: MaxSpace.md)
      }
      .padding(.top, MaxSpace.lg)
      .maxScreenBackground()
      .navigationTitle(request.kind.cropTitleKey)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("common.cancel") { dismiss() }
            .disabled(isRendering)
        }
        ToolbarItem(placement: .confirmationAction) {
          if isRendering {
            ProgressView()
              .accessibilityLabel(Text("profile.edit.state.preparing"))
          } else {
            Button("profile.crop.use") { finishCropping() }
              .fontWeight(.semibold)
              .accessibilityIdentifier("ui_profile_crop_use")
          }
        }
      }
      .alert(
        "error.product.profile_image.title",
        isPresented: $renderFailed
      ) {
        Button("common.dismiss", role: .cancel) { }
      } message: {
        Text("error.product.profile_image.reason")
      }
    }
  }

  private func cropPreview(size: CGSize) -> some View {
    let combinedOffset = CGSize(
      width: settledOffset.width + dragOffset.width,
      height: settledOffset.height + dragOffset.height
    )
    return ZStack {
      Color.black
      Image(uiImage: request.image)
        .resizable()
        .scaledToFill()
        .scaleEffect(zoom)
        .offset(combinedOffset)
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .updating($dragOffset) { value, state, _ in
          // Clamp live: an unbounded drag would slide the photo off the crop
          // window and expose the black canvas underneath.
          let target = CGSize(
            width: settledOffset.width + value.translation.width,
            height: settledOffset.height + value.translation.height
          )
          let bounded = clamped(target, within: size)
          state = CGSize(
            width: bounded.width - settledOffset.width,
            height: bounded.height - settledOffset.height
          )
        }
        .onEnded { value in
          withAnimation(reduceMotion ? nil : MaxMotion.quick) {
            settledOffset = clamped(
              CGSize(
                width: settledOffset.width + value.translation.width,
                height: settledOffset.height + value.translation.height
              ),
              within: size
            )
          }
        }
    )
  }

  @MainActor
  private func finishCropping() {
    guard canvasSize.width > 0, canvasSize.height > 0, !isRendering else { return }
    isRendering = true
    Task { @MainActor in
      // Let the spinner paint before the synchronous rasterisation begins.
      await Task.yield()
      let rendered = renderCroppedImage()
      isRendering = false
      guard let rendered else {
        renderFailed = true
        return
      }
      completion(rendered)
      dismiss()
    }
  }

  @MainActor
  private func renderCroppedImage() -> UIImage? {
    let outputSize = request.kind.outputSize
    let normalizedOffset = CGSize(
      width: settledOffset.width / canvasSize.width,
      height: settledOffset.height / canvasSize.height
    )
    let renderView = ProfileCropRenderView(
      image: request.image,
      zoom: zoom,
      normalizedOffset: normalizedOffset,
      outputSize: outputSize
    )
    let renderer = ImageRenderer(content: renderView)
    renderer.scale = 1
    return renderer.uiImage
  }

  /// The pannable range is exactly the overflow left by `scaledToFill` at the
  /// current zoom. Deriving it from the canvas alone let the user pan a photo
  /// that had no overflow on that axis, baking black bars into the export.
  private func clamped(_ offset: CGSize, within size: CGSize) -> CGSize {
    let source = request.image.size
    guard source.width > 0, source.height > 0, size.width > 0, size.height > 0 else {
      return .zero
    }
    let fill = max(size.width / source.width, size.height / source.height) * zoom
    let drawnWidth = source.width * fill
    let drawnHeight = source.height * fill
    let horizontalLimit = max(0, (drawnWidth - size.width) / 2)
    let verticalLimit = max(0, (drawnHeight - size.height) / 2)
    return CGSize(
      width: min(max(offset.width, -horizontalLimit), horizontalLimit),
      height: min(max(offset.height, -verticalLimit), verticalLimit)
    )
  }
}

private struct ProfileCropRenderView: View {
  let image: UIImage
  let zoom: CGFloat
  let normalizedOffset: CGSize
  let outputSize: CGSize

  var body: some View {
    ZStack {
      Color.black
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .scaleEffect(zoom)
        .offset(
          x: normalizedOffset.width * outputSize.width,
          y: normalizedOffset.height * outputSize.height
        )
    }
    .frame(width: outputSize.width, height: outputSize.height)
    .clipped()
  }
}

private extension ProfileImageKind {
  var cropAspectRatio: CGFloat {
    self == .avatar ? 1 : ProfileCoverMetrics.aspectRatio
  }

  var outputSize: CGSize {
    self == .avatar
      ? CGSize(width: 1_024, height: 1_024)
      : CGSize(width: ProfileCoverMetrics.pixelWidth, height: ProfileCoverMetrics.pixelHeight)
  }

  var cropTitleKey: LocalizedStringKey {
    self == .avatar ? "profile.crop.avatar" : "profile.crop.cover"
  }

  var previewShape: AnyShape {
    self == .avatar ? AnyShape(Circle()) : AnyShape(
      RoundedRectangle(cornerRadius: MaxRadius.large, style: .continuous)
    )
  }
}
