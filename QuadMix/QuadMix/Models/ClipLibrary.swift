import Foundation
import AVFoundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.wastemix.app", category: "cliplibrary")

/// One clip on disk in the app's Documents/Clips directory. Either a
/// recording produced by `ProgramRecorder` (auto-populated when REC stops)
/// or a video the user imported via the Media Center.
struct Clip: Identifiable, Hashable {
    let id: String          // file name, unique per clip
    let url: URL
    let createdAt: Date
    let duration: Double    // seconds, 0 if unknown
    let fileSize: Int64     // bytes
    let isRecording: Bool   // recorded by the app vs imported

    var displayName: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm:ss"
        return (isRecording ? "REC " : "IMP ") + f.string(from: createdAt)
    }
}

/// Owns the persistent on-disk clip collection. Auto-populated by
/// ProgramRecorder; presented by the Media Center panel; clips are
/// loaded onto channels via the existing `.mediaFile(url:)` source.
@Observable
final class ClipLibrary {
    private(set) var clips: [Clip] = []
    private let directory: URL
    private let fm = FileManager.default
    /// Cached thumbnail per clip id. Generated lazily by the UI.
    private var thumbnailCache: [String: UIImage] = [:]

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = docs.appendingPathComponent("Clips", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        rescan()
    }

    /// Where the recorder should write its next mp4. The filename
    /// encodes the timestamp so newest-first sort is just a string sort.
    func newRecordingURL() -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "WasteMix_REC_\(stamp).mp4"
        return directory.appendingPathComponent(name)
    }

    /// Copy a video the user picked from Photos into the library.
    func importVideo(from sourceURL: URL) async -> Clip? {
        let stamp = Int(Date().timeIntervalSince1970)
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let dest = directory.appendingPathComponent("WasteMix_IMP_\(stamp).\(ext)")
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            logger.error("import copy failed: \(error.localizedDescription)")
            return nil
        }
        let clip = await makeClip(for: dest, isRecording: false)
        await MainActor.run {
            self.clips.insert(clip, at: 0)
        }
        return clip
    }

    /// Called by ProgramRecorder once finishWriting succeeds, with the
    /// URL the recorder used (i.e. one returned from newRecordingURL()).
    @MainActor
    func registerRecording(at url: URL) {
        Task { @MainActor in
            let clip = await makeClip(for: url, isRecording: true)
            self.clips.insert(clip, at: 0)
        }
    }

    func delete(_ clip: Clip) {
        try? fm.removeItem(at: clip.url)
        thumbnailCache.removeValue(forKey: clip.id)
        clips.removeAll { $0.id == clip.id }
    }

    /// Returns a cached thumbnail or generates one off the main thread.
    /// Call from a Task; UI redraws when the cache hits next time.
    func thumbnail(for clip: Clip) async -> UIImage? {
        if let cached = thumbnailCache[clip.id] { return cached }
        let img = await Self.generateThumbnail(at: clip.url)
        if let img = img {
            await MainActor.run { self.thumbnailCache[clip.id] = img }
        }
        return img
    }

    // MARK: - Private

    private func rescan() {
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let videoExts: Set<String> = ["mp4", "mov", "m4v"]
        let videos = entries.filter { videoExts.contains($0.pathExtension.lowercased()) }

        Task { @MainActor in
            var built: [Clip] = []
            for url in videos {
                let isRec = url.lastPathComponent.contains("_REC_")
                built.append(await self.makeClip(for: url, isRecording: isRec))
            }
            built.sort { $0.createdAt > $1.createdAt }
            self.clips = built
        }
    }

    private func makeClip(for url: URL, isRecording: Bool) async -> Clip {
        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let createdAt = (attrs[.creationDate] as? Date) ?? Date()
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        var duration: Double = 0
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(d)
            if !duration.isFinite { duration = 0 }
        }

        return Clip(
            id: url.lastPathComponent,
            url: url,
            createdAt: createdAt,
            duration: duration,
            fileSize: size,
            isRecording: isRecording
        )
    }

    private static func generateThumbnail(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 180)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                if let cg = cgImage {
                    cont.resume(returning: UIImage(cgImage: cg))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
