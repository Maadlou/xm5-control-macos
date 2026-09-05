import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment.live()

    private var menuBarController: MenuBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private var uiTestWindow: NSWindow?
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !isRunningTests,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        #if MENU_BAR_APP
        NSApp.setActivationPolicy(.accessory)
        #endif
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            CommandLine.arguments.contains("--ui-test-host")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if MENU_BAR_APP || HYBRID_APP
        menuBarController = MenuBarController(environment: environment)
        globalHotKeyController = GlobalHotKeyController { [weak self] in
            self?.environment.headphones.toggleNoiseControl()
        }
        environment.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.globalHotKeyController?.setEnabled(enabled) }
            .store(in: &cancellables)
        #endif

        #if DEBUG && (MENU_BAR_APP || HYBRID_APP)
        if CommandLine.arguments.contains("--ui-test-host") {
            showUITestHost()
        }
        #endif
    }

    #if DEBUG && (MENU_BAR_APP || HYBRID_APP)
    private func showUITestHost() {
        let content = MenuBarView()
            .environmentObject(environment.settings)
            .environmentObject(environment.headphones)
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "app.name")
        window.setContentSize(MenuBarMetrics.displaySize)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestWindow = window
    }
    #endif
}
