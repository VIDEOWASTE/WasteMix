import SwiftUI

private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

struct ColorCorrectionView: View {
    let title: String
    @Binding var correction: ColorCorrection
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.isEmpty ? "COLOR" : title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button("RESET") { correction.reset() }
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(R)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray).padding(6)
                        .background(Color.white.opacity(0.06))
                }
            }

            CorrectionSlider(label: "BRI", value: $correction.brightness, range: -1...1, tint: R)
            CorrectionSlider(label: "CON", value: $correction.contrast, range: 0...2, tint: R)
            CorrectionSlider(label: "SAT", value: $correction.saturation, range: 0...2, tint: R)
            CorrectionSlider(label: "HUE", value: $correction.hueShift, range: 0...360, format: "%.0f", tint: R)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.vertical, 2)

            Text("RGB GAIN")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.gray)

            CorrectionSlider(label: "R", value: $correction.redGain, range: 0...2, tint: Color(red: 1, green: 0.3, blue: 0.3))
            CorrectionSlider(label: "G", value: $correction.greenGain, range: 0...2, tint: Color(red: 0.3, green: 1, blue: 0.3))
            CorrectionSlider(label: "B", value: $correction.blueGain, range: 0...2, tint: Color(red: 0.3, green: 0.3, blue: 1))

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.vertical, 2)

            Text("BLACK BALANCE")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.gray)

            CorrectionSlider(label: "BLK", value: $correction.blackLevel, range: 0...0.5, tint: R)
            CorrectionSlider(label: "LFT R", value: $correction.liftR, range: -0.5...0.5, tint: Color(red: 1, green: 0.3, blue: 0.3))
            CorrectionSlider(label: "LFT G", value: $correction.liftG, range: -0.5...0.5, tint: Color(red: 0.3, green: 1, blue: 0.3))
            CorrectionSlider(label: "LFT B", value: $correction.liftB, range: -0.5...0.5, tint: Color(red: 0.3, green: 0.3, blue: 1))
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }
}

struct CorrectionSlider: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var format: String = "%.2f"
    var tint: Color = .red

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 36, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(tint)
            Text(String(format: format, value))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 45, alignment: .trailing)
        }
    }
}
