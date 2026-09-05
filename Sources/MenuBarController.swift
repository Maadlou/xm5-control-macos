import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private struct StatusPresentation {
        let title: String
        let accessibilityLabel: String
    }

    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var pendingStatusPresentation: StatusPresentation?

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = MenuBarMetrics.displaySize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(onSizeChange: { [weak self] size in
                guard let self, self.popover.contentSize != size else { return }
                self.popover.contentSize = size
            })
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
        let title: String
        if headphones.isReady {
            if let battery = headphones.batteryLevel {
                title = " \(battery)%"
            } else if let mode = headphones.noiseControlMode {
                title = " \(mode.compactTitle)"
            } else {
                title = ""
            }
        } else {
            title = ""
        }
        let details = [
            headphones.statusText,
            headphones.noiseControlMode?.title,
            headphones.batteryLevel.map { "Battery \($0) percent" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        let presentation = StatusPresentation(
            title: title,
            accessibilityLabel: "XM5 Control, \(details)"
        )

        // Keep the status item's width fixed while its popover is anchored to it.
        // Accessibility remains current even while the visual title is queued.
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        guard !popover.isShown else {
            pendingStatusPresentation = presentation
            return
        }
        apply(presentation)
    }

    private func apply(_ presentation: StatusPresentation) {
        statusItem.button?.title = presentation.title
        statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let pendingStatusPresentation else { return }
        self.pendingStatusPresentation = nil
        apply(pendingStatusPresentation)
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
