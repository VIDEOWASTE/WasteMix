import UIKit
import CoreGraphics

/// Detects and tracks connected external displays.
/// Uses CoreGraphics on Mac Catalyst (where UIScreen doesn't see external monitors)
/// and UIScreen on iPad.
@Observable
final class DisplayManager {
    struct ConnectedDisplay: Identifiable {
        let id: UInt32       // CGDirectDisplayID or screen index
        let name: String
        let width: Int
        let height: Int
        let isMain: Bool
    }

    private(set) var externalDisplays: [ConnectedDisplay] = []
    private(set) var allDisplays: [ConnectedDisplay] = []

    private var observer: Any?

    init() {
        refreshDisplays()

        // Listen for display configuration changes (works on both Catalyst and iPad)
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() }

        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() }

        // Also poll on a timer for CG display changes (Catalyst doesn't always notify)
        #if targetEnvironment(macCatalyst)
        startDisplayPolling()
        #endif
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    func refreshDisplays() {
        #if targetEnvironment(macCatalyst)
        refreshDisplaysCG()
        #else
        refreshDisplaysUIScreen()
        #endif
    }

    // MARK: - CoreGraphics (Mac Catalyst)

    #if targetEnvironment(macCatalyst)
    private var pollTimer: Timer?

    private func startDisplayPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshDisplays()
        }
    }

    private func refreshDisplaysCG() {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        let mainID = CGMainDisplayID()
        var all: [ConnectedDisplay] = []
        var external: [ConnectedDisplay] = []

        for i in 0..<Int(displayCount) {
            let did = displayIDs[i]
            let w = CGDisplayPixelsWide(did)
            let h = CGDisplayPixelsHigh(did)
            let isMain = (did == mainID)

            let display = ConnectedDisplay(
                id: did,
                name: isMain ? "Main Display" : "External Display \(external.count + 1)",
                width: w,
                height: h,
                isMain: isMain
            )
            all.append(display)
            if !isMain {
                external.append(display)
            }
        }

        allDisplays = all
        externalDisplays = external
    }
    #endif

    // MARK: - UIScreen (iPad)

    private func refreshDisplaysUIScreen() {
        var all: [ConnectedDisplay] = []
        var external: [ConnectedDisplay] = []

        for (i, screen) in UIScreen.screens.enumerated() {
            let isMain = (i == 0)
            let display = ConnectedDisplay(
                id: UInt32(i),
                name: isMain ? "Main Display" : "External Display \(i)",
                width: Int(screen.bounds.width * screen.scale),
                height: Int(screen.bounds.height * screen.scale),
                isMain: isMain
            )
            all.append(display)
            if !isMain {
                external.append(display)
            }
        }

        allDisplays = all
        externalDisplays = external
    }
}
