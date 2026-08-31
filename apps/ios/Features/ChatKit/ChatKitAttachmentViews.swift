import AVFoundation
import Observation
import QuickLook
import Speech
import SwiftUI

/// The one audio player shared by every voice bubble in a thread, so starting
/// one voice note always stops the previous one instead of layering them.
@MainActor
@Observable
final class ChatKitAudioPlayer {
  private(set) var playingID: String?
  private(set) var isPlaying = false
  private(set) var currentTime: Double = 0
  private(set) var duration: Double = 0
  /// Voice-note speed (1×, 1.5×, 2×) — kept across notes, the way every
  /// messenger's speed button behaves.
  private(set) var rate: Float = 1

  @ObservationIgnored private var player: AVPlayer?
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var endObserver: NSObjectProtocol?

  func toggle(id: String, url: URL) {
    if playingID == id, let player {
      if isPlaying {
        player.pause()
        isPlaying = false
      } else {
        player.rate = rate
        isPlaying = true
      }
      return
    }
    play(id: id, url: url)
  }

  /// Cycles 1× → 1.5× → 2× → 1×, applied live to whatever is playing.
  func cycleRate() {
    switch rate {
    case 1: rate = 1.5
    case 1.5: rate = 2
    default: rate = 1
    }
    if isPlaying { player?.rate = rate }
  }

  /// Jumps the playing note to a 0...1 fraction of its duration — the
  /// waveform's drag-to-seek.
  func seek(id: String, toFraction fraction: Double) {
    guard playingID == id, let player, duration > 0 else { return }
    let clamped = min(max(fraction, 0), 1)
    let target = clamped * duration
    currentTime = target
    player.seek(
      to: CMTime(seconds: target, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
  }

  func stop() {
    if let timeObserver, let player {
      player.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    player?.pause()
    player = nil
    playingID = nil
    isPlaying = false
    currentTime = 0
    duration = 0
  }

  private func play(id: String, url: URL) {
    stop()
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)

    let item = AVPlayerItem(url: url)
    // Keep spoken pitch natural at 1.5× and 2×.
    item.audioTimePitchAlgorithm = .timeDomain
    let player = AVPlayer(playerItem: item)
    player.defaultRate = rate
    self.player = player
    playingID = id
    isPlaying = true
    currentTime = 0
    duration = 0

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      let seconds = time.seconds
      Task { @MainActor [weak self] in
        self?.tick(seconds)
      }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.stop()
      }
    }
    player.play()
  }

  private func tick(_ seconds: Double) {
    guard player != nil else { return }
    currentTime = seconds.isFinite ? max(seconds, 0) : 0
    if let itemDuration = player?.currentItem?.duration.seconds,
       itemDuration.isFinite, itemDuration > 0 {
      duration = itemDuration
    }
  }
}

/// Compact play/pause voice-note row rendered inside a message bubble, with the
/// sender's transcript underneath when one exists — and a Transcribe action on
/// the sender's own untranscribed notes, run on-device via the Speech framework.
struct ChatKitAudioBubble: View {
  @Environment(MaxAppModel.self) private var model
  let attachment: ChatAttachment
  let player: ChatKitAudioPlayer
  /// Only the sender may write a transcript for their own voice note.
  var isMine: Bool = false
  var threadID: String = ""
  var messageID: String = ""

  @State private var isTranscribing = false
  @State private var isTranscriptExpanded = false
  @State private var transcribeError: String?
  /// Non-nil while a finger drags the bar: the previewed 0...1 position.
  @State private var scrubFraction: Double?

  private var isActive: Bool { player.playingID == attachment.mediaId }

  private var progress: Double {
    if let scrubFraction { return scrubFraction }
    guard isActive, player.duration > 0 else { return 0 }
    return min(max(player.currentTime / player.duration, 0), 1)
  }

  private var rateLabel: String {
    player.rate == 1.5 ? "1.5×" : (player.rate == 2 ? "2×" : "1×")
  }

  /// The bar itself: linear progress that a finger can grab. Only an active
  /// note seeks — a drag on an idle bubble simply starts nothing.
  private var seekBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(.secondary.opacity(0.35))
        Capsule()
          .fill(.primary)
          .frame(width: max(geo.size.width * progress, 3))
      }
      .frame(height: scrubFraction == nil ? 4 : 7)
      .frame(maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard isActive, player.duration > 0 else { return }
            scrubFraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
          }
          .onEnded { value in
            guard isActive, player.duration > 0 else {
              scrubFraction = nil
              return
            }
            let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
            player.seek(id: attachment.mediaId, toFraction: fraction)
            scrubFraction = nil
          }
      )
    }
    .frame(width: 128, height: 18)
  }

  private var timeText: String {
    if isActive, player.duration > 0 {
      return "\(Self.clock(player.currentTime)) / \(Self.clock(player.duration))"
    }
    if let duration = attachment.durationSeconds, duration > 0 {
      return Self.clock(duration)
    }
    return "Voice message"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Button {
          guard let url = attachment.url else { return }
          player.toggle(id: attachment.mediaId, url: url)
        } label: {
          Image(systemName: isActive && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 32))
        }
        .buttonStyle(.plain)
        .disabled(attachment.url == nil)

        VStack(alignment: .leading, spacing: 4) {
          seekBar
          Text(timeText)
            .font(.caption2.monospacedDigit())
            .opacity(0.8)
        }

        Button {
          player.cycleRate()
        } label: {
          Text(verbatim: rateLabel)
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Playback speed"))
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text("Voice message"))

      transcriptSection
    }
    .padding(.vertical, 2)
    .alert(
      "Couldn't transcribe",
      isPresented: Binding(
        get: { transcribeError != nil },
        set: { if !$0 { transcribeError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(transcribeError ?? "")
    }
  }

  private var trimmedTranscript: String? {
    let text = attachment.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
  }

  @ViewBuilder
  private var transcriptSection: some View {
    if let transcript = trimmedTranscript {
      VStack(alignment: .leading, spacing: 2) {
        Text(transcript)
          .font(.caption)
          .opacity(0.85)
          .lineLimit(isTranscriptExpanded ? nil : 4)
          .frame(maxWidth: 220, alignment: .leading)
        if !isTranscriptExpanded, transcript.count > 160 {
          Button("More") { isTranscriptExpanded = true }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
        }
      }
    } else if isMine, !threadID.isEmpty, !messageID.isEmpty {
      Button(action: transcribe) {
        HStack(spacing: 4) {
          if isTranscribing {
            ProgressView()
              .controlSize(.small)
            Text("Transcribing…")
          } else {
            Image(systemName: "text.bubble")
            Text("Transcribe")
          }
        }
        .font(.caption.weight(.semibold))
        .opacity(0.9)
      }
      .buttonStyle(.plain)
      .disabled(isTranscribing || attachment.url == nil)
      .accessibilityIdentifier("ui_chat_transcribe")
    }
  }

  /// Downloads the audio to a local temp file (recognition needs a real file,
  /// and remote URLs expire), runs on-device speech recognition, then shares
  /// the result through the transcript endpoint.
  private func transcribe() {
    guard let url = attachment.url, !isTranscribing else { return }
    isTranscribing = true
    Task {
      defer { isTranscribing = false }
      do {
        let result = try await model.apiClient.downloadFile(from: url, progress: { _ in })
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("ChatKitTranscribe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
          .appendingPathComponent("\(attachment.mediaId).\(audioFileExtension)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: result.url, to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        let text = try await ChatKitSpeechTranscriber.transcribe(fileURL: destination)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          transcribeError = "No speech was recognized in this voice message."
          return
        }
        let saved = await model.chatStore.submitTranscript(
          threadID: threadID,
          messageID: messageID,
          mediaID: attachment.mediaId,
          transcript: trimmed
        )
        if !saved {
          transcribeError = "The transcript couldn't be saved. Try again."
        }
      } catch {
        transcribeError = error.localizedDescription
      }
    }
  }

  /// The decoder keys off the file extension, so name the temp file after what
  /// the server says the audio is.
  private var audioFileExtension: String {
    let type = (attachment.mimeType ?? "").lowercased()
    if type.contains("mpeg") || type.contains("mp3") { return "mp3" }
    if type.contains("wav") { return "wav" }
    if type.contains("ogg") || type.contains("opus") { return "ogg" }
    return "m4a"
  }

  private static func clock(_ seconds: Double) -> String {
    let total = max(Int(seconds.rounded()), 0)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// On-device speech recognition for voice notes: authorization, a URL-based
/// recognition request, and one final transcript back.
enum ChatKitSpeechTranscriber {
  enum TranscriptionError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
      switch self {
      case .denied:
        return "Allow Speech Recognition for Max in Settings to transcribe voice messages."
      case .unavailable:
        return "Speech recognition isn't available right now."
      }
    }
  }

  static func transcribe(fileURL: URL) async throws -> String {
    guard await requestAuthorization() == .authorized else {
      throw TranscriptionError.denied
    }
    guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
      throw TranscriptionError.unavailable
    }
    let request = SFSpeechURLRecognitionRequest(url: fileURL)
    request.shouldReportPartialResults = false
    // Keep the audio on this device whenever the model supports it.
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    let resumeGuard = ResumeGuard()
    let transcript: String = try await withCheckedThrowingContinuation { continuation in
      _ = recognizer.recognitionTask(with: request) { result, error in
        if let result, result.isFinal {
          guard resumeGuard.tryResume() else { return }
          continuation.resume(returning: result.bestTranscription.formattedString)
        } else if let error {
          guard resumeGuard.tryResume() else { return }
          continuation.resume(throwing: error)
        }
      }
    }
    // A deallocated recognizer cancels its tasks; touching it after the await
    // keeps it alive for the whole recognition.
    withExtendedLifetime(recognizer) {}
    return transcript
  }

  private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  /// The recognition callback can fire more than once; a continuation must not.
  private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if resumed { return false }
      resumed = true
      return true
    }
  }
}

/// A non-media attachment rendered as a document row. Tapping downloads the
/// file to a temporary location and opens it in a QuickLook preview.
struct ChatKitFileBubble: View {
  @Environment(MaxAppModel.self) private var model
  let attachment: ChatAttachment

  @State private var isDownloading = false
  @State private var preview: ChatKitPreviewFile?
  @State private var downloadError: String?

  var body: some View {
    Button(action: open) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 26))
        VStack(alignment: .leading, spacing: 2) {
          Text(attachment.name ?? "File")
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
          if let size = attachment.sizeBytes, size > 0 {
            Text(size.byteString)
              .font(.caption2)
              .opacity(0.8)
          }
        }
        if isDownloading {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding(.vertical, 2)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(attachment.url == nil || isDownloading)
    .sheet(item: $preview) { file in
      ChatKitFilePreview(url: file.url)
        .ignoresSafeArea()
    }
    .alert(
      "Couldn't open file",
      isPresented: Binding(
        get: { downloadError != nil },
        set: { if !$0 { downloadError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(downloadError ?? "")
    }
  }

  private var symbol: String {
    let type = (attachment.mimeType ?? "").lowercased()
    if type.contains("pdf") { return "doc.richtext.fill" }
    if type.hasPrefix("text") { return "doc.text.fill" }
    if type.contains("zip") || type.contains("compressed") { return "doc.zipper" }
    return "doc.fill"
  }

  private func open() {
    guard let url = attachment.url, !isDownloading else { return }
    isDownloading = true
    Task {
      defer { isDownloading = false }
      do {
        let result = try await model.apiClient.downloadFile(from: url, progress: { _ in })
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("ChatKitFilePreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = (attachment.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = result.suggestedFilename ?? "attachment" }
        name = name
          .replacingOccurrences(of: "/", with: "-")
          .replacingOccurrences(of: "\\", with: "-")
        let destination = directory.appendingPathComponent("\(attachment.mediaId)-\(name)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: result.url, to: destination)
        preview = ChatKitPreviewFile(id: attachment.mediaId, url: destination)
      } catch {
        downloadError = error.localizedDescription
      }
    }
  }
}

struct ChatKitPreviewFile: Identifiable {
  let id: String
  let url: URL
}

/// QuickLook wrapper for opening a downloaded attachment in-app.
struct ChatKitFilePreview: UIViewControllerRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    let url: URL

    init(url: URL) {
      self.url = url
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(
      _ controller: QLPreviewController,
      previewItemAt index: Int
    ) -> QLPreviewItem {
      url as NSURL
    }
  }
}
