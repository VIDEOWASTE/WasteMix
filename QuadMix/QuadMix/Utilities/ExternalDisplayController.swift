import UIKit
import SwiftUI

/// Manages a fullscreen UIWindow on an external display (HDMI / USB-C iPad)
/// so the user doesn't have to drag the SwiftUI live-output window over and
/// hit fullscreen with a mouse — it just lights up the moment the display is
/// selected as a destination.
///
/// Bypasses SwiftUI's WindowGroup system because WindowGroups don't expose
/// the external-screen routing APIs cleanly on iPad. Uses UIKit's UIWindow
/// + UIHostingController with the OutputDisplayView SwiftUI view inside.
final class ExternalDisplayController {
    static let shared = ExternalDisplayController()

    private var window: UIWindow?
    private weak var renderEngine: RenderEngine?
    private var screenIndex: Int = 0
    private var isShowing: Bool = false

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screenConnected(_:)),
                       name: UIScreen.didConnectNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenDisconnected(_:)),
                       name: UIScreen.didDisconnectNotification, object: nil)
    }

    /// Whether an external (non-main) display is currently attached.
    var hasExternalDisplay: Bool {
        UIScreen.screens.contains(where: { $0 != UIScreen.main })
    }

    /// Show the live-output content fullscreen on the connected external
    /// display. Safe to call without an external display attached — it just
    /// caches the request and lights up automatically when one connects.
    func show(renderEngine: RenderEngine, screenIndex: Int) {
        self.renderEngine = renderEngine
        self.screenIndex = screenIndex
        self.isShowing = true
        attachIfPossible()
    }

    /// Tear down the external window. Call when the user changes destination
    /// away from a display, or when the live-output should stop.
    func hide() {
        isShowing = false
        window?.isHidden = true
        window = nil
    }

    // MARK: - Internal

    private func attachIfPossible() {
        guard isShowing, let engine = renderEngine else { return }
        guard let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main }) else {
            // No external display yet — `isShowing` stays true so this fires
            // automatically when one connects.
            return
        }
        // Don't double-attach.
        if window?.screen == externalScreen { return }
        window?.isHidden = true

        // Prefer a UIWindowScene tied to the external screen if iPadOS has
        // already created one (Stage Manager / extended display path);
        // otherwise fall back to UIWindow(frame:) + setting `screen` directly,
        // which still works on iPadOS 17+ for non-Stage-Manager iPads in
        // mirror-disabled mode.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.screen == externalScreen })

        let win: UIWindow
        if let scene = scene {
            win = UIWindow(windowScene: scene)
            win.frame = externalScreen.bounds
        } else {
            win = UIWindow(frame: externalScreen.bounds)
            win.screen = externalScreen
        }

        let host = UIHostingController(rootView:
            OutputDisplayView(renderEngine: engine, screenIndex: screenIndex)
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        )
        host.view.backgroundColor = .black
        win.rootViewController = host
        win.backgroundColor = .black
        win.isUserInteractionEnabled = false  // pure output, no touches
        win.isHidden = false
        // Don't makeKeyAndVisible — that would steal first responder from
        // the main mixer window. Just show.
        window = win
    }

    @objc private func screenConnected(_ note: Notification) {
        // Display plugged in — light it up if we'd been waiting.
        DispatchQueue.main.async { [weak self] in
            self?.attachIfPossible()
        }
    }

    @objc private func screenDisconnected(_ note: Notification) {
        // Display unplugged — release the orphan window.
        DispatchQueue.main.async { [weak self] in
            if (note.object as? UIScreen) == self?.window?.screen {
                self?.window?.isHidden = true
                self?.window = nil
            }
        }
    }
}
