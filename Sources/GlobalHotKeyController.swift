import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyController {
    // Carbon owns these opaque handles. Marking their storage unsafe-nonisolated
    // lets deinit release them under Swift 6's nonisolated deinit rules.
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in controller.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            registerIfNeeded()
        } else if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func registerIfNeeded() {
        guard hotKey == nil else { return }
        let identifier = EventHotKeyID(
            signature: OSType(0x584D3543), // XM5C
            id: 1
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
