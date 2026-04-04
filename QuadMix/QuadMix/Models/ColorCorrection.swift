import Foundation

struct ColorCorrection: Codable {
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    var hueShift: Float = 0.0
    var redGain: Float = 1.0
    var greenGain: Float = 1.0
    var blueGain: Float = 1.0
    // Black balance / lift
    var blackLevel: Float = 0.0   // 0 to 0.5 — raises the black point
    var liftR: Float = 0.0        // -0.5 to 0.5 — tints the shadows red
    var liftG: Float = 0.0        // -0.5 to 0.5 — tints the shadows green
    var liftB: Float = 0.0        // -0.5 to 0.5 — tints the shadows blue

    var isIdentity: Bool {
        brightness == 0 && contrast == 1 && saturation == 1 &&
        hueShift == 0 && redGain == 1 && greenGain == 1 && blueGain == 1 &&
        blackLevel == 0 && liftR == 0 && liftG == 0 && liftB == 0
    }

    mutating func reset() {
        self = ColorCorrection()
    }
}
