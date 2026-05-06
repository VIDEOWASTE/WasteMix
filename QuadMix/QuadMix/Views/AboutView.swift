import SwiftUI

/// About / credits screen — also satisfies the NDI Advanced SDK's
/// attribution requirement.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (build \(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WASTEMIX")
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                            .foregroundColor(R)
                            .tracking(4)
                        Text(version)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    Divider()

                    section("ABOUT") {
                        Text("4-channel real-time video mixer with NDI I/O, projection mapping, and live effects. Built for VJ performance.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    section("NDI® TECHNOLOGY") {
                        Text("This product uses NDI® technology, available through the NDI® SDK from Vizrt NDI AB.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                        Text("NDI® is a registered trademark of Vizrt NDI AB.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                        Text("Copyright © 2014–2026 Vizrt NDI AB. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Link("ndi.video", destination: URL(string: "https://ndi.video")!)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(R)
                    }

                    section("LICENSES") {
                        Text("WasteMix is built with Apple's Metal, MetalKit, AVFoundation, SwiftUI, and Accelerate frameworks. Audio/video capture uses standard iOS system APIs.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    section("CREDITS") {
                        Text("Created by VIDEOWASTE.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    Spacer(minLength: 24)
                }
                .padding(20)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.05))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(R)
                        .font(.system(size: 14, weight: .heavy))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Rectangle().fill(R).frame(width: 2, height: 12)
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(R)
                    .tracking(1)
            }
            content()
        }
    }
}
