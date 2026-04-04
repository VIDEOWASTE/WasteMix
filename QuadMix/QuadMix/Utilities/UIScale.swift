import SwiftUI

/// Dynamic UI scale factor based on window size.
/// Baseline: 700pt width = 1.0x scale.
/// Everything multiplies by this: fonts, paddings, heights.
struct UIScale {
    let factor: CGFloat

    init(width: CGFloat) {
        // Clamp between 0.7x (tiny window) and 2.0x (huge display)
        factor = min(2.0, max(0.7, width / 700.0))
    }

    /// Scale a point value
    func s(_ value: CGFloat) -> CGFloat { value * factor }

    /// Scale for font size (slightly less aggressive so text stays readable)
    func f(_ size: CGFloat) -> CGFloat { max(6, size * min(1.8, max(0.8, factor))) }

    /// Scale for padding
    func p(_ value: CGFloat) -> CGFloat { max(1, value * factor) }
}

// Environment key so all child views can read the scale
private struct UIScaleKey: EnvironmentKey {
    static let defaultValue = UIScale(width: 700)
}

extension EnvironmentValues {
    var uiScale: UIScale {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}
