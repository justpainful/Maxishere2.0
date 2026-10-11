@preconcurrency import AVFoundation
@preconcurrency import AVKit
import Observation
import SwiftUI
import UIKit

/// Owns the one AVPlayerLayer used for both inline playback and system Picture in Picture.
/// Keeping PiP at the player-layer boundary prevents AVPlayerViewController from adding
/// playback-speed, subtitle, or track-selection controls that do not belong in Max.
@MainActor
@Observable
final class MaxPictureInPictureController:
  NSObject,
  @preconcurrency AVPictureInPictureControllerDelegate {
  private(set) var isActive = false

  let playerLayer = AVPlayerLayer()

  private var controller: AVPictureInPictureController?

  var isSupported: Bool {
    AVPictureInPictureController.isPictureInPictureSupported()
  }

  override init() {
    super.init()
    playerLayer.videoGravity = .resizeAspect
    guard isSupported else { return }
    if let controller = AVPictureInPictureController(playerLayer: playerLayer) {
      controller.canStartPictureInPictureAutomaticallyFromInline = true
      controller.delegate = self
      self.controller = controller
    }
  }

  func attach(player: AVPlayer) {
    guard playerLayer.player !== player else { return }
    playerLayer.player = player
  }

  func toggle() {
    guard let controller else { return }
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    } else if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    }
  }

  func stop() {
    if controller?.isPictureInPictureActive == true {
      controller?.stopPictureInPicture()
    }
    isActive = false
  }

  /// Flipped on the *will* callback, not only the *did* one: automatic PiP
  /// starts as the app is being backgrounded, and the player consults this flag
  /// on the same transition to decide whether it still has to pause.
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = true
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = true
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = false
    if UIApplication.shared.applicationState != .active {
      playerLayer.player?.pause()
    }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: any Error
  ) {
    isActive = false
  }
}

struct MaxPlayerSurface: UIViewRepresentable {
  let player: AVPlayer
  let pictureInPicture: MaxPictureInPictureController

  func makeUIView(context: Context) -> MaxPlayerLayerView {
    pictureInPicture.attach(player: player)
    return MaxPlayerLayerView(playerLayer: pictureInPicture.playerLayer)
  }

  func updateUIView(_ uiView: MaxPlayerLayerView, context: Context) {
    pictureInPicture.attach(player: player)
  }
}

/// A lightweight player-layer surface for feeds and feature-local viewers.
/// It deliberately has no system chrome, PiP ownership, or route coupling.
struct MaxInlinePlayerSurface: UIViewRepresentable {
  let player: AVPlayer
  var videoGravity: AVLayerVideoGravity = .resizeAspect

  func makeUIView(context: Context) -> MaxInlinePlayerLayerView {
    MaxInlinePlayerLayerView(player: player, videoGravity: videoGravity)
  }

  func updateUIView(_ uiView: MaxInlinePlayerLayerView, context: Context) {
    uiView.update(player: player, videoGravity: videoGravity)
  }
}

@MainActor
final class MaxInlinePlayerLayerView: UIView {
  private let playerLayer = AVPlayerLayer()

  init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
    super.init(frame: .zero)
    backgroundColor = .black
    playerLayer.player = player
    playerLayer.videoGravity = videoGravity
    layer.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
    layer.addSublayer(playerLayer)
  }

  func update(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
    if playerLayer.player !== player {
      playerLayer.player = player
    }
    playerLayer.videoGravity = videoGravity
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer.frame = bounds
    CATransaction.commit()
  }
}

@MainActor
final class MaxPlayerLayerView: UIView {
  private let playerLayer: AVPlayerLayer

  init(playerLayer: AVPlayerLayer) {
    self.playerLayer = playerLayer
    super.init(frame: .zero)
    backgroundColor = .black
    layer.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) {
    let playerLayer = AVPlayerLayer()
    self.playerLayer = playerLayer
    super.init(coder: coder)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
    layer.addSublayer(playerLayer)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer.frame = bounds
    CATransaction.commit()
  }
}
