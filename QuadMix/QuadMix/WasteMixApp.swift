import SwiftUI
import UIKit

/// App delegate that prevents secondary windows from auto-opening on launch.
class WasteMixAppDelegate: NSObject, UIApplicationDelegate {
    /// Track whether the app has finished launching — secondary windows are only allowed after this
    static var appDidFinishLaunching = false
    /// Set by `MixerView`'s onAppear so we can identify the mixer scene
    /// reliably (vs. naively trusting "first scene to connect", which got
    /// confused by state-restoration scenes).
    static weak var mixerSceneSession: UISceneSession?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Allow secondary windows after a delay (user-initiated only)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Self.appDidFinishLaunching = true
        }

        // When the mixer scene disconnects, take the auxiliary scenes with it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification, object: nil)

        // Mac Catalyst — give the mixer a proper Mac-shaped default
        // window. The previous compact 420×600 was tuned for testing the
        // Catalyst path from an iPad-first project; on a real Mac it's
        // tiny and the channel strips squish together.
        #if targetEnvironment(macCatalyst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for scene in application.connectedScenes {
                if let ws = scene as? UIWindowScene {
                    // Min 900×640 keeps all four channel strips legible
                    // even when the user resizes down. Max is unbounded
                    // so the mixer can fill an external display if
                    // desired.
                    ws.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 640)
                    let geo = UIWindowScene.GeometryPreferences.Mac(
                        systemFrame: CGRect(x: 80, y: 80, width: 1280, height: 800)
                    )
                    ws.requestGeometryUpdate(geo) { _ in }
                    break // only the first (mixer) window
                }
            }
        }
        #endif

        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)

        // On cold launch, suppress *state-restored* auxiliary scenes only —
        // earlier this also ate user-tapped "Advanced Output" / "Output"
        // openWindow calls during the first 2 seconds, which made the window
        // flash open and grey out (had to tap again to actually keep it).
        // User-initiated openWindow scenes have no stateRestorationActivity,
        // so this guard now only catches the OS-level restoration path.
        if !Self.appDidFinishLaunching,
           connectingSceneSession.stateRestorationActivity != nil,
           application.connectedScenes.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                application.requestSceneSessionDestruction(connectingSceneSession, options: nil)
            }
        }

        return config
    }

    @objc private func sceneDidDisconnect(_ note: Notification) {
        guard let scene = note.object as? UIScene else { return }
        // Only cascade-destroy when the *known* mixer session disconnects.
        guard let mixer = Self.mixerSceneSession, scene.session === mixer else { return }
        Self.mixerSceneSession = nil
        DispatchQueue.main.async {
            let app = UIApplication.shared
            for session in app.openSessions where session !== scene.session {
                app.requestSceneSessionDestruction(session, options: nil)
            }
        }
    }
}

/// UIViewRepresentable that captures its host window's UISceneSession on
/// appear so the AppDelegate knows which session belongs to the mixer.
struct MixerSceneTracker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isHidden = true
        DispatchQueue.main.async { register(from: v) }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        register(from: uiView)
    }
    private func register(from view: UIView) {
        if let session = view.window?.windowScene?.session {
            WasteMixAppDelegate.mixerSceneSession = session
        }
    }
}

@main
struct WasteMixApp: App {
    @UIApplicationDelegateAdaptor(WasteMixAppDelegate.self) var appDelegate
    @State private var mixerState: MixerState
    @State private var inputManager: InputManager
    @State private var renderEngine: RenderEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Build the engine eagerly at app init so any scene (including ones
        // restored before MixerView appears) can use it. Previously the
        // engine was created lazily inside MixerView's `onAppear`, so a
        // restored Advanced Output scene without the mixer would show
        // black indefinitely.
        let mixer = MixerState()
        let inputs = InputManager()
        let engine = RenderEngine(mixerState: mixer)
        _mixerState = State(initialValue: mixer)
        _inputManager = State(initialValue: inputs)
        _renderEngine = State(initialValue: engine)
    }

    var body: some Scene {
        // Main mixer window
        WindowGroup("WasteMix", id: "mixer") {
            MixerView(
                mixerState: mixerState,
                renderEngine: renderEngine,
                inputManager: inputManager
            )
            // Tracks this scene's session so the AppDelegate can cascade-close
            // auxiliary windows when this one closes.
            .background(MixerSceneTracker())
            .preferredColorScheme(.dark)
            .tint(Color(red: 1.0, green: 0.15, blue: 0.15))
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active: renderEngine.resumeForForeground()
                case .inactive, .background: renderEngine.pauseForBackground()
                @unknown default: break
                }
            }
        }

        // Advanced Output — only opens via button
        WindowGroup("Advanced Output", id: "advancedOutput") {
            AdvancedOutputView(
                outputConfig: renderEngine.outputConfig,
                renderEngine: renderEngine
            )
            .onAppear { renderEngine.outputConfig.isAdvancedOutputOpen = true }
            .onDisappear { renderEngine.outputConfig.isAdvancedOutputOpen = false }
            .preferredColorScheme(.dark)
            .tint(Color(red: 1.0, green: 0.15, blue: 0.15))
            .onAppear {
                #if targetEnvironment(macCatalyst)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    for scene in UIApplication.shared.connectedScenes {
                        if let ws = scene as? UIWindowScene,
                           ws.title?.contains("Advanced") == true || ws.session.stateRestorationActivity?.activityType.contains("advancedOutput") == true {
                            // Advanced Output needs room for the canvas
                            // + slice list + preview thumbnails. Bumped
                            // from 380×280 (iPad-tuned) to 1100×680 so
                            // the canvas reads comfortably on a Mac.
                            ws.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 480)
                            ws.sizeRestrictions?.maximumSize = CGSize(width: 3200, height: 2000)
                            let geo = UIWindowScene.GeometryPreferences.Mac(
                                systemFrame: CGRect(x: 200, y: 200, width: 1100, height: 680)
                            )
                            ws.requestGeometryUpdate(geo) { _ in }
                        }
                    }
                }
                #endif
            }
        }

        // Live Output — only opens via button
        WindowGroup("Output", id: "liveOutput") {
            OutputDisplayView(
                renderEngine: renderEngine,
                screenIndex: renderEngine.outputConfig.selectedScreenIndex
            )
            .preferredColorScheme(.dark)
        }
    }
}

