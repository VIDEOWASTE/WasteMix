import SwiftUI
import PhotosUI
import AVFoundation

struct SourcePickerView: View {
    let channel: Channel
    let renderEngine: RenderEngine
    let inputManager: InputManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedImageItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Camera
                    sourceSection("Camera") {
                        sourceRow(icon: "camera", label: "Back Camera", tint: .blue) {
                            selectSource(.camera(position: .back))
                        }
                        sourceRow(icon: "camera.rotate", label: "Front Camera", tint: .blue) {
                            selectSource(.camera(position: .front))
                        }
                    }

                    // Test Patterns
                    sourceSection("Test Patterns") {
                        ForEach(PatternType.allCases) { pattern in
                            sourceRow(icon: "checkerboard.rectangle", label: pattern.displayName, tint: .purple) {
                                selectSource(.pattern(pattern))
                            }
                        }
                    }

                    // Solid Colors
                    sourceSection("Solid Colors") {
                        HStack(spacing: 8) {
                            colorSwatch(.black, r: 0, g: 0, b: 0)
                            colorSwatch(.white, r: 1, g: 1, b: 1)
                            colorSwatch(.red, r: 1, g: 0, b: 0)
                            colorSwatch(.green, r: 0, g: 1, b: 0)
                            colorSwatch(.blue, r: 0, g: 0, b: 1)
                            colorSwatch(.yellow, r: 1, g: 1, b: 0)
                            colorSwatch(.cyan, r: 0, g: 1, b: 1)
                            colorSwatch(.orange, r: 1, g: 0.5, b: 0)
                        }
                        .padding(.vertical, 4)
                    }

                    // Video
                    sourceSection("Video") {
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            HStack(spacing: 10) {
                                Image(systemName: "film")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Choose Video")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("MP4, MOV, M4V from your library")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // Images
                    sourceSection("Images") {
                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            HStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 16))
                                    .foregroundColor(.cyan)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Choose Image")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("JPG, PNG, HEIF from your library")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // NDI Sources
                    sourceSection("NDI Network Sources") {
                        if inputManager.discoveredNDISources.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Scanning local network...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            ForEach(inputManager.discoveredNDISources, id: \.name) { source in
                                sourceRow(icon: "network", label: source.name, tint: .cyan) {
                                    selectSource(.ndi(sourceName: source.name, ipAddress: source.address))
                                }
                            }
                        }
                    }

                    // Clear source
                    if channel.source != nil {
                        Button {
                            channel.source = nil
                            inputManager.clearSource(for: channel.id, renderEngine: renderEngine)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear Source")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Rectangle()
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .navigationTitle("Source — \(channel.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                if let item = newItem { loadMedia(from: item, isVideo: true) }
            }
            .onChange(of: selectedImageItem) { _, newItem in
                if let item = newItem { loadMedia(from: item, isVideo: false) }
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Components

    private func sourceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
                .tracking(1)
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                content()
            }
            .background(Color.white.opacity(0.04))
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    private func sourceRow(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(tint)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ color: Color, r: Float, g: Float, b: Float) -> some View {
        Button {
            selectSource(.solidColor(red: r, green: g, blue: b))
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func selectSource(_ source: ContentSource) {
        channel.source = source
        inputManager.applySource(source, to: channel.id, renderEngine: renderEngine)
        dismiss()
    }

    private func loadMedia(from item: PhotosPickerItem, isVideo: Bool) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let ext = isVideo ? "mov" : "png"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try? data.write(to: tempURL)

                await MainActor.run {
                    if isVideo {
                        selectSource(.mediaFile(url: tempURL))
                    } else {
                        selectSource(.image(url: tempURL))
                    }
                }
            }
        }
    }
}
