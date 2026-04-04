import SwiftUI

/// Compact master controls that stays visible at the smallest sizes.
/// Horizontal bar with crossfader, quick actions, and tap into full master.
struct MiniMasterView: View {
    let mixerState: MixerState
    @State private var showFullMaster = false
    @State private var crossfaderPos: Float = 0.5
    @State private var crossfaderA: Int = 0
    @State private var crossfaderB: Int = 1

    var body: some View {
        VStack(spacing: 4) {
            // Crossfader
            HStack(spacing: 4) {
                Text("A:\(crossfaderA + 1)")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 20)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 16)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 10)
                            .offset(x: geo.size.width / 2 - 0.5)
                        Rectangle().fill(Color.white).frame(width: 24, height: 14)
                            .offset(x: CGFloat(crossfaderPos) * (geo.size.width - 24))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                crossfaderPos = max(0, min(1, Float(v.location.x / geo.size.width)))
                                applyCrossfade()
                            }
                    )
                }
                .frame(height: 16)

                Text("B:\(crossfaderB + 1)")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 20)
            }

            // Quick action buttons row
            HStack(spacing: 3) {
                miniAction(icon: "moon.fill", label: "BLK", fg: .red.opacity(0.7)) {
                    for ch in mixerState.channels { ch.faderLevel = 0 }
                    Haptics.bump()
                }
                miniAction(icon: "sun.max.fill", label: "FUL", fg: .yellow.opacity(0.7)) {
                    for ch in mixerState.channels { if ch.source != nil { ch.faderLevel = 1.0 } }
                    Haptics.thud()
                }
                miniAction(icon: "arrow.counterclockwise", label: "RST", fg: .gray.opacity(0.6)) {
                    for ch in mixerState.channels {
                        ch.blendMode = .normal; ch.effectType = .none
                        ch.isFrozen = false; ch.keySettings = KeySettings()
                    }
                    Haptics.thud()
                }

                // Open full master
                Button {
                    showFullMaster = true
                    Haptics.tap()
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(TactileButtonStyle())
                .sheet(isPresented: $showFullMaster) {
                    NavigationStack {
                        ScrollView {
                            GlobalControlsView(mixerState: mixerState)
                                .padding()
                        }
                        .navigationTitle("Master")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showFullMaster = false }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            Rectangle()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func miniAction(icon: String, label: String, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 8))
                Text(label).font(.system(size: 6, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Rectangle().fill(Color.white.opacity(0.03))
            )
        }
        .buttonStyle(TactileButtonStyle())
    }

    private func applyCrossfade() {
        guard crossfaderA != crossfaderB,
              crossfaderA < mixerState.channels.count,
              crossfaderB < mixerState.channels.count else { return }
        mixerState.channels[crossfaderA].faderLevel = 1.0 - crossfaderPos
        mixerState.channels[crossfaderB].faderLevel = crossfaderPos
    }
}
