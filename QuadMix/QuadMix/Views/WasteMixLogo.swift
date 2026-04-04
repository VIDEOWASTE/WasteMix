import SwiftUI

/// The WasteMix logo — 4 overlapping color bars representing the 4 mix channels,
/// with the brand name underneath. Used in the header bar and can be rendered
/// to an image for the app icon.
struct WasteMixLogo: View {
    var size: CGFloat = 32
    var showText: Bool = true

    private let barColors: [Color] = [
        Color(red: 0.3, green: 0.55, blue: 1.0),
        Color(red: 0.2, green: 0.78, blue: 0.45),
        Color(red: 1.0, green: 0.55, blue: 0.2),
        Color(red: 0.7, green: 0.35, blue: 1.0),
    ]

    var body: some View {
        HStack(spacing: showText ? 6 : 0) {
            // The mark: 4 overlapping vertical bars
            ZStack {
                ForEach(0..<4) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [barColors[i], barColors[i].opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.22, height: size * (0.5 + CGFloat(i) * 0.15))
                        .offset(x: CGFloat(i - 2) * size * 0.18 + size * 0.09)
                        .opacity(0.85)
                }
            }
            .frame(width: size, height: size)
            .blendMode(.screen)

            if showText {
                VStack(alignment: .leading, spacing: -1) {
                    Text("WASTE")
                        .font(.system(size: size * 0.38, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(size * 0.06)
                    Text("MIX")
                        .font(.system(size: size * 0.28, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(size * 0.12)
                }
            }
        }
    }
}

/// Compact inline logo for tight spaces
struct WasteMixBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            // Mini 4-bar mark
            HStack(spacing: 1.5) {
                Rectangle()
                    .fill(Color(red: 0.3, green: 0.55, blue: 1.0))
                    .frame(width: 3, height: 8)
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.78, blue: 0.45))
                    .frame(width: 3, height: 11)
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.55, blue: 0.2))
                    .frame(width: 3, height: 14)
                Rectangle()
                    .fill(Color(red: 0.7, green: 0.35, blue: 1.0))
                    .frame(width: 3, height: 10)
            }

            Text("WASTEMIX")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .tracking(1)
        }
    }
}
