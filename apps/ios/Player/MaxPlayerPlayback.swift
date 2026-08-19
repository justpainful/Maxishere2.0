@preconcurrency import AVFoundation
import SwiftUI
import UIKit

extension MaxPlayerSingleView {
  func preparePlayback() async {
    removeTimeObserver()
    demoPlaybackTask?.cancel()
    playbackState = .loading
    isFinished = false
    actionError = nil

    guard isVideo else {
      playbackState = .ready
      return
    }

    if model.isDemoMode {
      UIApplication.shared.isIdleTimerDisabled = true
      duration = max(item.duration ?? 90, 30)
      position = min(max(item.lastPosition, 0), max(duration - 1, 0))
      lastPersistedPosition = position
      playbackState = .ready
      playPlayback()
      return
    }

    guard var playbackURL else {
      playbackState = .failed(ProductError(
        area: .player,
        code: .unknown,
        title: String(localized: "error.player.no_url.title"),
        reason: String(localized: "error.player.no_url.reason"),
        recoverySuggestion: String(localized: "error.player.no_url.retry")
      ))
      UIApplication.shared.isIdleTimerDisabled = false
      return
    }

    if !playbackURL.isFileURL {
      playbackURL = playbackURL.resolved(against: MaxConfiguration.fromBundle().baseURL)

      // The API signs a playback URL for a short window. Browsing the library
      // for a while and then opening a video used to hand AVFoundation a
      // signature the server had already rejected, with no way back. The new
      // URL is used for this attempt only; storing it here would change
      // `playerTaskID` and restart the very task doing the work.
      if MaxPresignedURL.isExpired(playbackURL),
         let refreshed = await refreshedRemoteURL() {
        playbackURL = refreshed.resolved(against: MaxConfiguration.fromBundle().baseURL)
      }
    }

    UIApplication.shared.isIdleTimerDisabled = true

    do {
      // Local downloads are file URLs, not HTTP responses. Sending them through
      // the API preflight produces `invalid_response` before AVPlayer sees the
      // valid offline file.
      if !playbackURL.isFileURL {
        // A session check only proves that the API responds. AVPlayer needs a
        // ranged response from the specific file, so validate that contract.
        try await model.apiClient.preflightMediaStream(url: playbackURL)
      }
      MaxPlaybackSession.activateForPlayback()

      // A presigned GET URL cannot be safely reissued as the loader's HEAD
      // request. Passing it through a custom scheme therefore made AVPlayer
      // report an unplayable asset and left a black screen. Let AVFoundation
      // stream the original URL; offline files already use this same path.
      let asset = AVURLAsset(url: playbackURL)
      guard try await asset.load(.isPlayable) else {
        throw MaxPlayerError.notPlayable
      }

      let playerItem = AVPlayerItem(asset: asset)
      playerItem.preferredForwardBufferDuration = 12
      player.replaceCurrentItem(with: playerItem)
      player.automaticallyWaitsToMinimizeStalling = true

      // Observe item status so an AVFoundation-level failure (e.g. DRM
      // rejection, unsupported codec) surfaces as a clear .failed state
      // rather than leaving the UI stuck on a spinner.
      let statusToken = playerItem.observe(\AVPlayerItem.status, options: [.new]) { [weak playerItem] item, _ in
        guard item.status == .failed else { return }
        let description = item.error?.localizedDescription
          ?? playerItem?.error?.localizedDescription
          ?? "Playback failed"
        print("[MaxPlayer] AVPlayerItem failed: \(description)")
        Task { @MainActor in
          guard case .loading = playbackState else { return }
          playbackState = .failed(ProductError(
            area: .player,
            code: .unknown,
            title: description,
            reason: "",
            recoverySuggestion: String(localized: "error.product.retry")
          ))
          isPlaying = false
          UIApplication.shared.isIdleTimerDisabled = false
        }
      }
      // Extend token lifetime until the player item is replaced or the view tears down.
      // We intentionally do not store it on self to keep this extension state-free;
      // the observation is automatically invalidated when the token is deallocated, which
      // happens after `withExtendedLifetime` exits (well past the ready-state transition).
      _ = statusToken
      playbackSpeed = model.preferencesStore.playbackRate
      player.defaultRate = playbackSpeed

      let loadedDuration = try? await asset.load(.duration)
      duration = loadedDuration?.seconds.isFinite == true
        ? max(loadedDuration?.seconds ?? 0, 0)
        : max(item.duration ?? 0, 0)
      position = min(max(item.lastPosition, 0), max(duration - 1, 0))
      lastPersistedPosition = position

      if position > 0 {
        await player.seek(
          to: CMTime(seconds: position, preferredTimescale: 600),
          toleranceBefore: .zero,
          toleranceAfter: .zero
        )
      }

      attachTimeObserver()
      playbackState = .ready
      playPlayback()
    } catch is CancellationError {
      return
    } catch {
      // An expired signature is indistinguishable from an unplayable asset at
      // this level. Re-sign once and let the task restart on the new URL before
      // telling the user the video is broken.
      if !didRefreshMediaURL,
         !playbackURL.isFileURL,
         let refreshed = await refreshedRemoteURL(),
         refreshed != (refreshedMediaURL ?? item.mediaUrl) {
        didRefreshMediaURL = true
        refreshedMediaURL = refreshed
        return
      }
      print("[MaxPlayer] Playback failed: \(error)")
      playbackState = .failed(ProductError.from(error, area: .player))
      isPlaying = false
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  /// A newly signed remote URL for this item, or nil when the API cannot
  /// produce one. Local downloads never need it.
  func refreshedRemoteURL() async -> URL? {
    guard !model.isDemoMode, model.networkMonitor.isOnline else { return nil }
    guard let refreshed = await MaxMediaRefresh.refreshedItem(
      for: item,
      api: model.apiClient
    )?.mediaUrl, !refreshed.isFileURL else {
      return nil
    }
    return refreshed
  }

  func retryPlayback() {
    // An explicit retry is allowed to re-sign again: the previous refresh may
    // itself have aged out while the failure card was on screen.
    didRefreshMediaURL = false
    Task { await preparePlayback() }
  }

  func dismissPlaybackError() {
    playbackState = .idle
    actionError = nil
    showControls(scheduleHide: false)
  }

  func openAdjacent(offset: Int) {
    pausePlayback()
    persistCurrentPosition()
    Task {
      await model.openAdjacentPlayer(offset: offset)
    }
  }

  func togglePlayback() {
    if isPlaying {
      pausePlayback()
    } else if isFinished {
      restartPlayback()
    } else {
      playPlayback()
    }
    showControls()
  }

  func playPlayback() {
    guard playbackState == .ready else { return }
    if isFinished {
      seek(to: 0)
      isFinished = false
    }
    if model.isDemoMode {
      isPlaying = true
      startDemoClock()
    } else {
      player.playImmediately(atRate: playbackSpeed)
      isPlaying = true
    }
    showControls()
  }

  func pausePlayback() {
    player.pause()
    demoPlaybackTask?.cancel()
    demoPlaybackTask = nil
    isPlaying = false
    hideControlsTask?.cancel()
    showControls(scheduleHide: false)
  }

  func restartPlayback() {
    isFinished = false
    seek(to: 0)
    playPlayback()
  }

  func skip(by seconds: Double) {
    seek(to: position + seconds)
    showControls()
  }

  func seek(to requestedPosition: Double) {
    let target = min(max(requestedPosition, 0), max(duration, 0))
    position = target
    if target < max(duration - 0.5, 0) { isFinished = false }
    guard !model.isDemoMode else { return }
    Task {
      await player.seek(
        to: CMTime(seconds: target, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  func handleSeekEditing(_ editing: Bool) {
    isSeeking = editing
    if editing {
      hideControlsTask?.cancel()
    } else {
      seek(to: position)
      persistCurrentPosition()
      showControls()
    }
  }

  func attachTimeObserver() {
    let observedPlayer = player
    timeObserver = observedPlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { time in
      Task { @MainActor in
        guard time.seconds.isFinite, !isSeeking else { return }
        position = time.seconds
        handleProgressTick()
      }
    }
  }

  func removeTimeObserver() {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }

  func startDemoClock() {
    demoPlaybackTask?.cancel()
    demoPlaybackTask = Task { @MainActor in
      while !Task.isCancelled, isPlaying {
        do {
          try await Task.sleep(for: .milliseconds(500))
        } catch {
          return
        }
        guard !Task.isCancelled, !isSeeking else { continue }
        position = min(position + 0.5, duration)
        handleProgressTick()
      }
    }
  }

  func handleProgressTick() {
    if duration > 0, position >= duration - 0.35 {
      finishPlayback()
      return
    }
    guard abs(position - lastPersistedPosition) >= 15 else { return }
    lastPersistedPosition = position
    persistCurrentPosition()
  }

  func finishPlayback() {
    guard !isFinished else { return }
    player.pause()
    demoPlaybackTask?.cancel()
    demoPlaybackTask = nil
    position = duration
    isPlaying = false
    isFinished = true
    controlsVisible = true
    hideControlsTask?.cancel()
    Task { await model.persistPlayback(for: item, position: 0) }
  }

  func persistCurrentPosition() {
    let persistedPosition = isFinished ? 0 : max(position, 0)
    Task { await model.persistPlayback(for: item, position: persistedPosition) }
  }

  func toggleFavorite() {
    isFavorite.toggle()
    showControls()
    Task { await model.toggleFavorite(item) }
  }

  /// Moves the current item to Trash (recoverable for 30 days) and closes the
  /// player. Optimistic catalog removal drops it from the browse grid too.
  func deleteCurrent() {
    showControls()
    Task {
      if await model.libraryStore.trash(item) {
        onClose()
      }
    }
  }

  func togglePictureInPicture() {
    pictureInPicture.toggle()
    showControls()
  }

  func setPlaybackSpeed(_ speed: Float) {
    playbackSpeed = speed
    model.preferencesStore.playbackRate = speed
    if isPlaying, !model.isDemoMode {
      player.rate = speed
    }
    showControls()
  }

  func startDownload() {
    showControls()
    if !model.preferencesStore.allowsCellularDownloads,
       model.networkMonitor.isExpensive {
      actionError = ProductError(
        area: .transfers,
        code: .downloadFailed,
        title: String(localized: "error.product.download_policy.title"),
        reason: String(localized: "error.product.download_policy.reason"),
        recoverySuggestion: String(localized: "error.product.download_policy.recovery")
      )
      pausePlayback()
      return
    }
    Task { await model.transferStore.download(item) }
  }

  func startPhotoExport() {
    guard !isSavingToPhotos, !didSaveToPhotos else { return }
    isSavingToPhotos = true
    actionError = nil
    showControls(scheduleHide: false)
    Task {
      do {
        try await MediaPhotoExporter.save(item, transferStore: model.transferStore)
        didSaveToPhotos = true
      } catch {
        actionError = ProductError(
          area: .transfers,
          code: .downloadFailed,
          title: String(localized: "error.photos.save.title"),
          reason: error.localizedDescription,
          recoverySuggestion: String(localized: "error.photos.save.recovery")
        )
      }
      isSavingToPhotos = false
      showControls(scheduleHide: false)
    }
  }

  func toggleControls() {
    hideControlsTask?.cancel()
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
      controlsVisible.toggle()
    }
    if controlsVisible { showControls() }
  }

  func showControls(scheduleHide: Bool = true) {
    hideControlsTask?.cancel()
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
      controlsVisible = true
    }
    guard scheduleHide, isPlaying, actionError == nil else { return }
    hideControlsTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(4))
      } catch {
        return
      }
      guard isPlaying, !isSeeking, actionError == nil else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
        controlsVisible = false
      }
    }
  }

  func tearDown() {
    hideControlsTask?.cancel()
    demoPlaybackTask?.cancel()
    removeTimeObserver()
    player.pause()
    pictureInPicture.stop()
    UIApplication.shared.isIdleTimerDisabled = false
    persistCurrentPosition()
  }

}
