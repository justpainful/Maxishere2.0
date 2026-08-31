import Foundation
import Observation

/// Clips & Markers — the player's range-and-bookmark layer.
///
/// A CLIP is a saved range of a media item ("the good forty seconds"), stored
/// server-side as a row; playing one is ordinary playback with enforced bounds.
/// A MARKER is a labelled timecode drawn as a tick on the scrubber. Mirrors the
/// desktop's clipsMarkers store: optimistic removals, truth restored on failure.
@MainActor
@Observable
final class ClipsStore {
  private let api: any MaxService

  private(set) var clipsByMedia: [String: [MediaClip]] = [:]
  private(set) var markersByMedia: [String: [MediaMarker]] = [:]
  /// 100 normalised re-watch bins per item — the scrubber's heat lane.
  private(set) var heatmapByMedia: [String: [Double]] = [:]
  /// The Clips shelf: everything the user has clipped, newest first.
  private(set) var shelf: [MediaClip]?
  private(set) var isShelfLoading = false
  private var loadingMediaIDs = Set<String>()

  init(api: any MaxService) {
    self.api = api
  }

  func reset() {
    clipsByMedia = [:]
    markersByMedia = [:]
    heatmapByMedia = [:]
    shelf = nil
    isShelfLoading = false
    loadingMediaIDs = []
  }

  func clips(for mediaID: String) -> [MediaClip] {
    clipsByMedia[mediaID] ?? []
  }

  func markers(for mediaID: String) -> [MediaMarker] {
    markersByMedia[mediaID] ?? []
  }

  func heatmap(for mediaID: String) -> [Double] {
    heatmapByMedia[mediaID] ?? []
  }

  /// Clips + markers + re-watch heat for one item, fetched together when the
  /// player opens it. The heat lane is decoration, so its failure is swallowed
  /// separately and cannot take the ticks down with it.
  func load(mediaID: String) async {
    guard !loadingMediaIDs.contains(mediaID) else { return }
    loadingMediaIDs.insert(mediaID)
    defer { loadingMediaIDs.remove(mediaID) }
    do {
      async let clips = api.mediaClips(mediaID: mediaID)
      async let markers = api.mediaMarkers(mediaID: mediaID)
      async let heat = api.heatmap(mediaID: mediaID)
      heatmapByMedia[mediaID] = (try? await heat) ?? []
      clipsByMedia[mediaID] = try await clips
      markersByMedia[mediaID] = try await markers
    } catch {
      // The scrubber simply shows no ticks; nothing to break.
    }
  }

  func loadShelf() async {
    guard !isShelfLoading else { return }
    isShelfLoading = true
    defer { isShelfLoading = false }
    do {
      shelf = try await api.allClips()
    } catch {
      // The shelf keeps whatever it last showed.
    }
  }

  @discardableResult
  func addMarker(
    mediaID: String,
    atSeconds: Double,
    label: String = ""
  ) async -> MediaMarker? {
    do {
      let marker = try await api.createMarker(
        mediaID: mediaID,
        atSeconds: atSeconds,
        label: label
      )
      var list = markersByMedia[mediaID] ?? []
      list.append(marker)
      markersByMedia[mediaID] = list.sorted { $0.atSeconds < $1.atSeconds }
      return marker
    } catch {
      return nil
    }
  }

  func removeMarker(mediaID: String, markerID: String) async {
    markersByMedia[mediaID] = (markersByMedia[mediaID] ?? [])
      .filter { $0.id != markerID }
    do {
      _ = try await api.deleteMarker(markerID: markerID)
    } catch {
      await load(mediaID: mediaID) // restore truth on failure
    }
  }

  @discardableResult
  func addClip(
    mediaID: String,
    title: String,
    startSeconds: Double,
    endSeconds: Double
  ) async -> MediaClip? {
    do {
      let clip = try await api.createClip(
        mediaID: mediaID,
        title: title,
        startSeconds: startSeconds,
        endSeconds: endSeconds
      )
      var list = clipsByMedia[mediaID] ?? []
      list.append(clip)
      clipsByMedia[mediaID] = list.sorted { $0.startSeconds < $1.startSeconds }
      if let shelf {
        self.shelf = [clip] + shelf
      }
      return clip
    } catch {
      return nil
    }
  }

  func removeClip(clipID: String, mediaID: String?) async {
    shelf = shelf?.filter { $0.id != clipID }
    if let mediaID {
      clipsByMedia[mediaID] = (clipsByMedia[mediaID] ?? [])
        .filter { $0.id != clipID }
    }
    do {
      _ = try await api.deleteClip(clipID: clipID)
    } catch {
      if let mediaID { await load(mediaID: mediaID) }
      await loadShelf()
    }
  }
}

/// A clip armed by the Clips shelf, consumed by the next player open of its
/// media — the desktop's `openClipNext` pattern, so a stale range can never
/// attach to a later, plain open.
struct PendingClipRange: Hashable, Sendable {
  let clipID: String
  let mediaID: String
  let title: String
  let startSeconds: Double
  let endSeconds: Double
}
