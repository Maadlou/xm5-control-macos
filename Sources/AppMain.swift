import SwiftUI

@main
@MainActor
struct XM5ControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        #if WINDOW_APP || HYBRID_APP
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.environment.settings)
        }
        #endif

        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment.settings)
                .environmentObject(appDelegate.environment.headphones)
        }
    }
}
