import Foundation

enum Constants {
    static let channelCount = 4
    static let defaultWidth = 1920
    static let defaultHeight = 1080
    static let defaultFrameRate = 30
    static let previewScale: Float = 0.25
}

import SwiftUI

extension Color {
    /// Secondary label color — brighter than system `.gray` so small
    /// monospaced captions stay readable on the near-black mixer UI.
    static let wmSecondary = Color(white: 0.74)
}
