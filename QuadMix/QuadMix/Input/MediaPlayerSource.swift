import AVFoundation
import CoreVideo

final class MediaPlayerSource: FrameProvider {
    private let player: AVPlayer
    private let playerItem: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private var looper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
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

        // Also add output to template items via notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let currentItem = self.queuePlayer?.currentItem,
               !currentItem.outputs.contains(where: { $0 === self.videoOutput }) {
                currentItem.add(self.videoOutput)
            }
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
