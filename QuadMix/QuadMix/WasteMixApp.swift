import SwiftUI
import UIKit

/// App delegate that prevents secondary windows from auto-opening on launch.
class WasteMixAppDelegate: NSObject, UIApplicationDelegate {
    /// Track whether the app has finished launching — secondary windows are only allowed after this
    static var appDidFinishLaunching = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Allow secondary windows after a delay (user-initiated only)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Self.appDidFinishLaunching = true
        }

        // Set main mixer window to a compact size
        #if targetEnvironment(macCatalyst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for scene in application.connectedScenes {
                if let ws = scene as? UIWindowScene {
                    ws.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 260)
                    let geo = UIWindowScene.GeometryPreferences.Mac(
                        systemFrame: CGRect(x: 60, y: 60, width: 320, height: 260)
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

        // If app hasn't finished launching yet, only allow the first scene (mixer)
        if !Self.appDidFinishLaunching {
            let existingCount = application.connectedScenes.count
            if existingCount > 0 {
                // This is a restored secondary scene — reject it by destroying after connection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    application.requestSceneSessionDestruction(connectingSceneSession, options: nil)
                }
            }
        }

        return config
    }
}

@main
struct WasteMixApp: App {
    @UIApplicationDelegateAdaptor(WasteMixAppDelegate.self) var appDelegate
    @State private var mixerState = MixerState()
    @State private var inputManager = InputManager()
    @State private var renderEngine: RenderEngine?

    var body: some Scene {
        // Main mixer window
        WindowGroup("WasteMix", id: "mixer") {
            Group {
                if let engine = renderEngine {
                    MixerView(
                        mixerState: mixerState,
                        renderEngine: engine,
                        inputManager: inputManager
                    )
                } else {
                    Color.black.onAppear {
                        renderEngine = RenderEngine(mixerState: mixerState)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }

        // Advanced Output — only opens via button
        WindowGroup("Advanced Output", id: "advancedOutput") {
            Group {
                if let engine = renderEngine {
                    AdvancedOutputView(
                        outputConfig: engine.outputConfig,
                        renderEngine: engine
                    )
                } else {
                    Color.black
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                #if targetEnvironment(macCatalyst)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    for scene in UIApplication.shared.connectedScenes {
                        if let ws = scene as? UIWindowScene,
                           ws.title?.contains("Advanced") == true || ws.session.stateRestorationActivity?.activityType.contains("advancedOutput") == true {
                            ws.sizeRestrictions?.minimumSize = CGSize(width: 500, height: 350)
                            ws.sizeRestrictions?.maximumSize = CGSize(width: 3000, height: 2000)
                            let geo = UIWindowScene.GeometryPreferences.Mac(
                                systemFrame: CGRect(x: 80, y: 80, width: 750, height: 480)
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
            Group {
                if let engine = renderEngine {
                    OutputDisplayView(
                        renderEngine: engine,
                        screenIndex: engine.outputConfig.selectedScreenIndex
                    )
                } else {
                    Color.black
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
