import Foundation
import XCTest
@testable import XM5Control

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testDefaultsAndPersistence() {
        let suiteName = "local.xm5control.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.reconnectAutomatically)
        XCTAssertTrue(settings.globalShortcutEnabled)
        XCTAssertEqual(settings.customEqualizerDraft, .flat)

        settings.reconnectAutomatically = false
        settings.globalShortcutEnabled = false
        settings.customEqualizerDraft = EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5])
        let profile = settings.saveEqualizerProfile(named: "Night")

        XCTAssertFalse(SettingsStore(defaults: defaults).reconnectAutomatically)
        XCTAssertFalse(SettingsStore(defaults: defaults).globalShortcutEnabled)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.customEqualizerDraft, settings.customEqualizerDraft)
        XCTAssertEqual(restored.equalizerProfiles, [profile])
    }
}
