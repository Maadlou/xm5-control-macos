import Foundation
import XCTest
@testable import XM5Control

final class SettingsStoreTests: XCTestCase {
    private let v2Key = "preferences.equalizerStorage.v2"

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "local.xm5control.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @MainActor
    func testLegacyMigrationPreservesBackupAndImportsOnlyOnce() throws {
        try withDefaults { defaults in
            defaults.set(Self.legacyDraft, forKey: "preferences.customEqualizerDraft")
            defaults.set(Self.legacyProfiles, forKey: "preferences.equalizerProfiles")
            defaults.set(false, forKey: "preferences.reconnectAutomatically")
            defaults.set(false, forKey: "preferences.globalShortcutEnabled")
            let store = SettingsStore(defaults: defaults)
            let old = EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5])
            XCTAssertEqual(store.equalizerDraft(for: .xm5SixValue), old)
            XCTAssertEqual(store.compatibleEqualizerProfiles(for: .xm5SixValue).first?.settings, old)
            XCTAssertEqual(store.equalizerProfiles.first?.layout, .xm5SixValue)
            XCTAssertNil(store.equalizerStorageError)
            let v2 = try XCTUnwrap(defaults.data(forKey: v2Key))
            XCTAssertEqual((try JSONSerialization.jsonObject(with: v2) as? [String: Any])?["version"] as? Int, 2)
            for _ in 0..<2 {
                let restored = SettingsStore(defaults: defaults)
                XCTAssertEqual(restored.equalizerProfiles, store.equalizerProfiles)
                XCTAssertFalse(restored.reconnectAutomatically)
                XCTAssertFalse(restored.globalShortcutEnabled)
                XCTAssertEqual(defaults.data(forKey: v2Key), v2)
            }
            store.deleteEqualizerProfile(id: try XCTUnwrap(store.equalizerProfiles.first?.id))
            XCTAssertTrue(SettingsStore(defaults: defaults).equalizerProfiles.isEmpty)
            XCTAssertEqual(defaults.data(forKey: "preferences.customEqualizerDraft"), Self.legacyDraft)
            XCTAssertEqual(defaults.data(forKey: "preferences.equalizerProfiles"), Self.legacyProfiles)
        }
    }

    @MainActor
    func testDraftsAndSameNameProfilesAreIsolatedByLayout() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let xm5 = EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5])
            var xm6 = EqualizerSettings.flat(for: .xm6TenBand)
            xm6[band: 0] = -6
            store.setEqualizerDraft(xm5)
            store.setEqualizerDraft(xm6)
            let first = try XCTUnwrap(store.saveEqualizerProfile(named: "Night", settings: xm5))
            let second = try XCTUnwrap(store.saveEqualizerProfile(named: "night", settings: xm6))
            XCTAssertNotEqual(first.id, second.id)
            let updated = try XCTUnwrap(store.saveEqualizerProfile(named: " NIGHT ", settings: .flat))
            XCTAssertEqual(updated.id, first.id)
            XCTAssertEqual(store.compatibleEqualizerProfiles(for: .xm6TenBand), [second])
            XCTAssertEqual(store.compatibleEqualizerProfiles(for: .xm5SixValue), [updated])
            let restored = SettingsStore(defaults: defaults)
            XCTAssertEqual(restored.equalizerDraft(for: .xm5SixValue), xm5)
            XCTAssertEqual(restored.equalizerDraft(for: .xm6TenBand), xm6)
            XCTAssertEqual(restored.equalizerProfiles, store.equalizerProfiles)
        }
    }

    @MainActor
    func testPartiallyDamagedLegacyProfilesRetainHealthyRecordsAndRawBackup() throws {
        try withDefaults { defaults in
            let healthy = try XCTUnwrap((JSONSerialization.jsonObject(with: Self.legacyProfiles) as? [Any])?.first)
            let damaged: [String: Any] = ["id": "bad", "name": "Broken", "settings": ["clearBass": 0, "bands": [0]]]
            let data = try JSONSerialization.data(withJSONObject: [healthy, damaged])
            defaults.set(data, forKey: "preferences.equalizerProfiles")
            defaults.set(Data(#"{"clearBass":99,"bands":[0,0,0,0,0]}"#.utf8), forKey: "preferences.customEqualizerDraft")
            let store = SettingsStore(defaults: defaults)
            XCTAssertEqual(store.equalizerProfiles.map(\.name), ["Night"])
            XCTAssertEqual(store.equalizerDraft(for: .xm5SixValue), .flat)
            XCTAssertNotNil(store.equalizerStorageError)
            XCTAssertEqual(defaults.data(forKey: "preferences.equalizerProfiles"), data)
            XCTAssertEqual(SettingsStore(defaults: defaults).equalizerProfiles, store.equalizerProfiles)
        }
    }

    @MainActor
    func testCompletelyInvalidLegacyDataDoesNotWriteAnEmptyReplacement() throws {
        try withDefaults { defaults in
            let data = Data("broken-json".utf8)
            defaults.set(data, forKey: "preferences.equalizerProfiles")
            let store = SettingsStore(defaults: defaults)
            XCTAssertTrue(store.equalizerProfiles.isEmpty)
            XCTAssertNotNil(store.equalizerStorageError)
            XCTAssertNil(defaults.data(forKey: v2Key))
            store.setEqualizerDraft(.flat)
            _ = store.saveEqualizerProfile(named: "Attempt", settings: .flat)
            XCTAssertNil(defaults.data(forKey: v2Key))
            XCTAssertEqual(defaults.data(forKey: "preferences.equalizerProfiles"), data)
        }
    }

    @MainActor
    func testUnusableV2IsPreservedAndCannotBeOverwrittenByMutations() throws {
        for data in [Data("not-json".utf8), Data(#"{"version":3,"drafts":{},"profiles":[]}"#.utf8),
                     Data(#"{"version":2,"drafts":[],"profiles":{}}"#.utf8)] {
            try withDefaults { defaults in
                defaults.set(data, forKey: v2Key)
                defaults.set(Self.legacyProfiles, forKey: "preferences.equalizerProfiles")
                let store = SettingsStore(defaults: defaults)
                XCTAssertEqual(store.equalizerProfiles.map(\.name), ["Night"])
                XCTAssertNotNil(store.equalizerStorageError)
                store.setEqualizerDraft(.flat)
                _ = store.saveEqualizerProfile(named: "Attempt", settings: .flat)
                store.deleteEqualizerProfile(id: try XCTUnwrap(store.equalizerProfiles.first?.id))
                XCTAssertEqual(defaults.data(forKey: v2Key), data)
                XCTAssertEqual(SettingsStore(defaults: defaults).equalizerProfiles.map(\.name), ["Night"])
            }
        }
    }

    @MainActor
    func testDamagedV2RecordsAreRecoveredIndividuallyWithoutOverwritingSource() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let good = try XCTUnwrap(store.saveEqualizerProfile(named: "Healthy", settings: .flat))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: v2Key))) as? [String: Any])
            var records = try XCTUnwrap(object["profiles"] as? [[String: Any]])
            var mismatch = records[0]
            mismatch["id"] = UUID().uuidString
            mismatch["layout"] = "xm6TenBand"
            records += [mismatch, ["id": "broken"]]
            object["profiles"] = records
            object["drafts"] = ["xm6TenBand": ["layout": "xm6TenBand", "bands": [0]]]
            let raw = try JSONSerialization.data(withJSONObject: object)
            defaults.set(raw, forKey: v2Key)
            let restored = SettingsStore(defaults: defaults)
            XCTAssertEqual(restored.equalizerProfiles, [good])
            XCTAssertEqual(restored.equalizerDraft(for: .xm6TenBand), .flat(for: .xm6TenBand))
            XCTAssertNotNil(restored.equalizerStorageError)
            restored.deleteEqualizerProfile(id: good.id)
            XCTAssertEqual(defaults.data(forKey: v2Key), raw)
        }
    }

    @MainActor
    func testInvalidInMemorySettingsCannotReplaceHealthyStorage() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let original = try XCTUnwrap(store.saveEqualizerProfile(named: "Healthy", settings: .flat))
            let bytes = defaults.data(forKey: v2Key)
            var invalid = EqualizerSettings.flat
            invalid.bands = [99]
            store.setEqualizerDraft(invalid)
            _ = store.saveEqualizerProfile(named: "Healthy", settings: invalid)
            XCTAssertEqual(store.equalizerProfiles, [original])
            XCTAssertEqual(defaults.data(forKey: v2Key), bytes)
            XCTAssertNotNil(store.equalizerStorageError)
        }
    }

    @MainActor
    func testReadOnlyRecoveryStillTracksSequentialDraftEditsWithoutWritingToDisk() throws {
        try withDefaults { defaults in
            let raw = Data(#"{"version":3,"drafts":{},"profiles":[]}"#.utf8)
            defaults.set(raw, forKey: v2Key)
            let store = SettingsStore(defaults: defaults)
            var firstEdit = store.equalizerDraft(for: .xm5SixValue)
            firstEdit[band: 0] = 3
            store.setEqualizerDraft(firstEdit)
            var secondEdit = store.equalizerDraft(for: .xm5SixValue)
            secondEdit[band: 1] = -2
            store.setEqualizerDraft(secondEdit)
            XCTAssertEqual(store.equalizerDraft(for: .xm5SixValue).bands, [3, -2, 0, 0, 0])
            XCTAssertNil(store.saveEqualizerProfile(named: "Cannot save", settings: secondEdit))
            XCTAssertFalse(store.canSaveEqualizerChanges)
            XCTAssertEqual(defaults.data(forKey: v2Key), raw)
        }
    }

    // Literal pre-migration JSON, not produced by the current encoder.
    static let legacyDraft = Data(#"{"clearBass":4,"bands":[1,2,3,4,5]}"#.utf8)
    static let legacyProfiles = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"Night","settings":{"clearBass":4,"bands":[1,2,3,4,5]}}]"#.utf8)

    @MainActor
    func testLegacyJSONBaseline() throws {
        let suiteName = "local.xm5control.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.legacyDraft, forKey: "preferences.customEqualizerDraft")
        defaults.set(Self.legacyProfiles, forKey: "preferences.equalizerProfiles")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.equalizerDraft(for: .xm5SixValue), EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5]))
        XCTAssertEqual(store.equalizerProfiles.first?.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(store.equalizerProfiles.first?.name, "Night")
        XCTAssertEqual(store.equalizerProfiles.first?.settings, store.equalizerDraft(for: .xm5SixValue))
        defaults.removeObject(forKey: "preferences.customEqualizerDraft")
        defaults.removeObject(forKey: "preferences.equalizerProfiles")
    }

    @MainActor
    func testDefaultsAndPersistence() throws {
        let suiteName = "local.xm5control.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.reconnectAutomatically)
        XCTAssertTrue(settings.globalShortcutEnabled)
        XCTAssertEqual(settings.equalizerDraft(for: .xm5SixValue), .flat)

        settings.reconnectAutomatically = false
        settings.globalShortcutEnabled = false
        settings.setEqualizerDraft(EqualizerSettings(clearBass: 4, bands: [1, 2, 3, 4, 5]))
        let profile = try XCTUnwrap(settings.saveEqualizerProfile(named: "Night", settings: settings.equalizerDraft(for: .xm5SixValue)))

        XCTAssertFalse(SettingsStore(defaults: defaults).reconnectAutomatically)
        XCTAssertFalse(SettingsStore(defaults: defaults).globalShortcutEnabled)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.equalizerDraft(for: .xm5SixValue), settings.equalizerDraft(for: .xm5SixValue))
        XCTAssertEqual(restored.equalizerProfiles, [profile])
    }
}
