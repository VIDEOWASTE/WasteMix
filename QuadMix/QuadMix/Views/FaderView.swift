import SwiftUI

struct FaderView: View {
    @Binding var level: Float
    var isTransitioning: Bool = false
    var channelColor: Color = .red

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Track
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                // Tick marks at 0, 25, 50, 75, 100
                tickMarks(height: geo.size.height)

                // Fill
                Rectangle()
                    .fill(channelColor.opacity(0.3))
                    .frame(width: 44, height: max(0, geo.size.height * CGFloat(level)))

                // Knob
                Rectangle()
                    .fill(isTransitioning ? Color.white : channelColor)
                    .frame(width: 52, height: 4)
                    .offset(y: -geo.size.height * CGFloat(level) + 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = 1.0 - Float(value.location.y / geo.size.height)
                        level = max(0, min(1, raw))
                    }
            )
        }
        .frame(width: 50)
    }

    private func tickMarks(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<5) { i in
                if i > 0 { Spacer() }
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 30, height: 1)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 44)
    }
}

struct LevelIndicator: View {
    let level: Float

    var body: some View {
        Text("\(Int(level * 100))")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(level > 0.001 ? .white.opacity(0.7) : .gray.opacity(0.3))
            .frame(width: 28)
    }
}
