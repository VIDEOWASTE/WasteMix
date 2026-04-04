import UIKit

enum Haptics {
    #if targetEnvironment(macCatalyst)
    static func prepare() {}
    static func tap() {}
    static func thud() {}
    static func bump() {}
    static func tick() {}
    static func success() {}
    static func warning() {}
    #else
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        selection.prepare()
    }

    static func tap() { lightImpact.impactOccurred() }
    static func thud() { mediumImpact.impactOccurred() }
    static func bump() { heavyImpact.impactOccurred() }
    static func tick() { selection.selectionChanged() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    #endif
}
