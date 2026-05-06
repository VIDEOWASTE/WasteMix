import AVFoundation
import CoreVideo

final class MediaPlayerSource: FrameProvider {
    private let player: AVPlayer
    private let playerItem: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private var looper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var loopObserver: NSObjectProtocol?
    private var currentItemObserver: NSKeyValueObservation?
    private(set) var isActive = false

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        self.playerItem = AVPlayerItem(asset: asset)

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)

        // Use AVQueuePlayer + AVPlayerLooper for seamless looping
        let qp = AVQueuePlayer()
        self.queuePlayer = qp
        self.player = qp

        let templateItem = AVPlayerItem(asset: asset)
        self.looper = AVPlayerLooper(player: qp, templateItem: templateItem)

        qp.currentItem?.add(videoOutput)

        // Re-attach the video output whenever the looper rotates currentItem.
        // KVO is more reliable than the access-log notification we used to
        // observe (which doesn't fire for local file playback) and the token
        // is cleaned up in deinit so we don't leak the entire pipeline.
        currentItemObserver = qp.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            guard let self = self,
                  let item = change.newValue ?? nil,
                  !item.outputs.contains(where: { $0 === self.videoOutput }) else { return }
            item.add(self.videoOutput)
        }
    }

    deinit {
        currentItemObserver?.invalidate()
        if let token = loopObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var latestPixelBuffer: CVPixelBuffer? {
        let currentTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else { return nil }
        return videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil)
    }

    func start() {
        if let currentItem = queuePlayer?.currentItem,
           !currentItem.outputs.contains(where: { $0 === videoOutput }) {
            currentItem.add(videoOutput)
        }
        player.play()
        isActive = true
    }

    func stop() {
        player.pause()
        isActive = false
    }
}
