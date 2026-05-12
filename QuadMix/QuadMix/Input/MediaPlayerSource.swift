import AVFoundation
import CoreVideo

/// Plays a video file as a channel source. Uses a single AVPlayer plus a
/// manual seek-to-zero on `AVPlayerItemDidPlayToEndTime` for looping. We
/// previously used `AVPlayerLooper`, but the looper rotates currentItem
/// asynchronously — and the `AVPlayerItemVideoOutput` has to be attached
/// to whatever AVPlayerItem is current at any moment. The race could
/// leave the output unattached and the channel rendering black for the
/// entire session. The single-player approach attaches the output to the
/// item once, before play starts, so frames flow on the very first tick.
final class MediaPlayerSource: FrameProvider {
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private var endObserver: NSObjectProtocol?
    private(set) var isActive = false

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        // Attach BEFORE wrapping in the player so the very first frame the
        // player decodes is already routed to our output.
        item.add(output)

        let player = AVPlayer(playerItem: item)
        // Don't auto-pause at end — we handle the loop ourselves below.
        player.actionAtItemEnd = .none
        // Mute the player's audio track. Channel sources are video-only;
        // audio comes from the AudioEngine input. Without this, looping a
        // recorded clip would dump the recorded audio into the speakers.
        player.isMuted = true

        self.item = item
        self.videoOutput = output
        self.player = player

        // Auto-loop: when the item plays to its end, snap back to t=0 and
        // resume. Listen to the specific item so we don't fire on items
        // belonging to other MediaPlayerSources.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                self.player.play()
            }
        }
    }

    deinit {
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
        }
        player.pause()
    }

    var latestPixelBuffer: CVPixelBuffer? {
        let currentTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else { return nil }
        return videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil)
    }

    func start() {
        // Always rewind to start so the user sees the clip from the
        // beginning when they assign it (otherwise tapping CH1 a second
        // time would resume from wherever we paused).
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player.play()
        }
        isActive = true
    }

    func stop() {
        player.pause()
        isActive = false
    }
}
