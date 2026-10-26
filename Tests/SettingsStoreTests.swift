import Foundation
import XCTest
@testable import XM5Control

final class SettingsStoreTests: XCTestCase {
    // Literal pre-migration JSON, not produced by the current encoder.
    static let legacyDraft = Data(#"{"clearBass":4,"bands":[1,2,3,4,5]}"#.utf8)
    static let legacyProfiles = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"Night","settings":{"clearBass":4,"bands":[1,2,3,4,5]}}]"#.utf8)

    @MainActor
    func testLegacyJSONBaseline() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "local.xm5control.tests.\(UUID())"))
        defaults.set(Self.legacyDraft, forKey: "preferences.customEqualizerDraft")
        defaults.set(Self.legacyProfiles, forKey: "preferences.equalizerProfiles")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.customEqualizerDraft, EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5]))
        XCTAssertEqual(store.equalizerProfiles.first?.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(store.equalizerProfiles.first?.name, "Night")
        XCTAssertEqual(store.equalizerProfiles.first?.settings, store.customEqualizerDraft)
        defaults.removeObject(forKey: "preferences.customEqualizerDraft")
        defaults.removeObject(forKey: "preferences.equalizerProfiles")
    }

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
