import SwiftUI
import PhotosUI
import AVFoundation

/// Media Center panel — lists every clip in the on-disk ClipLibrary
/// (recorded by the app or imported by the user) and lets you assign
/// any clip to a channel as a `.mediaFile` source. Hooks the existing
/// PhotosPicker pipeline for new imports.
struct MediaCenterView: View {
    let clipLibrary: ClipLibrary
    let mixerState: MixerState
    let inputManager: InputManager
    let renderEngine: RenderEngine
    var onAssigned: () -> Void = {}

    @State private var selectedImportItem: PhotosPickerItem?
    @State private var importing = false
    @State private var pendingDelete: Clip?

    private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            if clipLibrary.clips.isEmpty {
                emptyState
            } else {
                clipList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onChange(of: selectedImportItem) { _, item in
            guard let item = item else { return }
            importing = true
            Task {
                await importClip(from: item)
                await MainActor.run {
                    selectedImportItem = nil
                    importing = false
                }
            }
        }
        .alert("Delete clip?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let c = pendingDelete { clipLibrary.delete(c) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.url.lastPathComponent ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(clipLibrary.clips.count) CLIP\(clipLibrary.clips.count == 1 ? "" : "S")")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            PhotosPicker(selection: $selectedImportItem, matching: .videos) {
                HStack(spacing: 5) {
                    if importing {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    Text(importing ? "IMPORTING…" : "IMPORT")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .overlay(Rectangle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .disabled(importing)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.gray.opacity(0.5))
            Text("No clips yet")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
            Text("Tap REC to record the program output, or IMPORT to add a video from your Photos library. Recorded clips appear here automatically.")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Clip list

    private var clipList: some View {
        VStack(spacing: 6) {
            ForEach(clipLibrary.clips) { clip in
                ClipRow(
                    clip: clip,
                    library: clipLibrary,
                    accent: R,
                    onSendTo: { ch in assign(clip: clip, to: ch) },
                    onDelete: { pendingDelete = clip }
                )
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func assign(clip: Clip, to channelIndex: Int) {
        guard channelIndex >= 0, channelIndex < mixerState.channels.count else { return }
        let channel = mixerState.channels[channelIndex]
        let source: ContentSource = .mediaFile(url: clip.url)
        channel.source = source
        inputManager.applySource(source, to: channel.id, channel: channel, renderEngine: renderEngine)
        Haptics.success()
        onAssigned()
    }

    private func importClip(from item: PhotosPickerItem) async {
        // Photos returns transferable Data — write it to a temp file
        // and have the library copy it into Documents/Clips.
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try? data.write(to: temp)
        _ = await clipLibrary.importVideo(from: temp)
        try? FileManager.default.removeItem(at: temp)
    }
}

// MARK: - Row

private struct ClipRow: View {
    let clip: Clip
    let library: ClipLibrary
    let accent: Color
    let onSendTo: (Int) -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 10) {
            thumbView
                .frame(width: 96, height: 54)
                .background(Color.black)
                .overlay(Rectangle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(clip.isRecording ? "REC" : "IMP")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(clip.isRecording ? accent : .cyan)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((clip.isRecording ? accent : Color.cyan).opacity(0.18))
                    Text(formattedDate)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(formattedDuration)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(formattedSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }

            Spacer()

            // Channel send pad — assigns the clip as the source for that channel.
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        onSendTo(i)
                    } label: {
                        Text("CH\(i+1)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 28)
                            .background(accent.opacity(0.25))
                            .overlay(Rectangle().stroke(accent.opacity(0.55), lineWidth: 0.5))
                    }
                    .buttonStyle(TactileButtonStyle())
                }
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.04))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(TactileButtonStyle())
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .task(id: clip.id) {
            thumbnail = await library.thumbnail(for: clip)
        }
    }

    @ViewBuilder
    private var thumbView: some View {
        if let img = thumbnail {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            ZStack {
                Color.black
                Image(systemName: "film")
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm:ss"
        return f.string(from: clip.createdAt)
    }

    private var formattedDuration: String {
        let s = Int(clip.duration.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var formattedSize: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useKB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: clip.fileSize)
    }
}
