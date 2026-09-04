import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(environment.settings)
                .environmentObject(environment.headphones)
        )

        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityLabel(String(localized: "status.accessibilityLabel"))
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        Publishers.CombineLatest3(
            environment.headphones.$linkState,
            environment.headphones.$noiseControlMode,
            environment.headphones.$batteryLevel
        )
        .sink { [weak self] _, _, _ in self?.updateStatusItem() }
        .store(in: &cancellables)
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let headphones = environment.headphones
        if headphones.isReady {
            if let battery = headphones.batteryLevel {
                button.title = " \(battery)%"
            } else if let mode = headphones.noiseControlMode {
                button.title = " \(mode.compactTitle)"
            }
        } else {
            button.title = ""
        }
        let details = [
            headphones.statusText,
            headphones.noiseControlMode?.title,
            headphones.batteryLevel.map { "Battery \($0) percent" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        button.setAccessibilityLabel("XM5 Control, \(details)")
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button, button.window != nil else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
