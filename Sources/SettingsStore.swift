import Combine
import Foundation
import ServiceManagement

struct SavedEqualizerProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let layout: EqualizerLayoutID
    var settings: EqualizerSettings

    private enum CodingKeys: String, CodingKey { case id, name, layout, settings }

    init(id: UUID, name: String, settings: EqualizerSettings) {
        self.id = id
        self.name = name
        layout = settings.layout
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layout = try container.decode(EqualizerLayoutID.self, forKey: .layout)
        settings = try container.decode(EqualizerSettings.self, forKey: .settings)
        guard layout == settings.layout else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Profile layout does not match its curve"))
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var reconnectAutomatically: Bool {
        didSet { defaults.set(reconnectAutomatically, forKey: Keys.reconnectAutomatically) }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?
    @Published var globalShortcutEnabled: Bool {
        didSet { defaults.set(globalShortcutEnabled, forKey: Keys.globalShortcutEnabled) }
    }
    @Published private(set) var equalizerProfiles: [SavedEqualizerProfile] = []
    @Published private(set) var equalizerStorageError: String?
    @Published private(set) var canSaveEqualizerChanges = true
    @Published private var equalizerDrafts: [EqualizerLayoutID: EqualizerSettings] = [:]

    private let defaults: UserDefaults
    private let managesLaunchService: Bool

    init(defaults: UserDefaults, managesLaunchService: Bool = false) {
        self.defaults = defaults
        self.managesLaunchService = managesLaunchService
        reconnectAutomatically = defaults.object(forKey: Keys.reconnectAutomatically) == nil
            ? true : defaults.bool(forKey: Keys.reconnectAutomatically)
        launchAtLogin = managesLaunchService && SMAppService.mainApp.status == .enabled
        globalShortcutEnabled = defaults.object(forKey: Keys.globalShortcutEnabled) == nil
            ? true : defaults.bool(forKey: Keys.globalShortcutEnabled)

        if let stored = defaults.object(forKey: Keys.equalizerStorageV2) {
            if let data = stored as? Data, let loaded = Self.readV2(data) {
                equalizerDrafts = loaded.drafts
                equalizerProfiles = loaded.profiles
                canSaveEqualizerChanges = !loaded.hadInvalidRecords
                if loaded.hadInvalidRecords {
                    equalizerStorageError = "Some saved EQ data could not be read. Recoverable profiles are available; the original data is unchanged and saving is disabled."
                }
            } else {
                let legacy = Self.readLegacy(defaults)
                equalizerDrafts = legacy.drafts
                equalizerProfiles = legacy.profiles
                canSaveEqualizerChanges = false
                equalizerStorageError = "Saved EQ storage is damaged or uses an unsupported version. Original data is unchanged; saving is disabled."
            }
        } else {
            let legacy = Self.readLegacy(defaults)
            equalizerDrafts = legacy.drafts
            equalizerProfiles = legacy.profiles
            canSaveEqualizerChanges = !legacy.hadInvalidRecords || !legacy.drafts.isEmpty || !legacy.profiles.isEmpty
            if legacy.hadInvalidRecords {
                equalizerStorageError = "Some legacy EQ data could not be imported. Recoverable profiles were retained and the original data is unchanged."
            }
            if canSaveEqualizerChanges { persistEqualizerStorage() }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard managesLaunchService else {
            launchAtLogin = enabled
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func equalizerDraft(for layout: EqualizerLayoutID) -> EqualizerSettings {
        equalizerDrafts[layout] ?? .flat(for: layout)
    }

    func setEqualizerDraft(_ settings: EqualizerSettings) {
        guard validate(settings), canSaveEqualizerChanges else { return }
        equalizerDrafts[settings.layout] = settings
        persistEqualizerStorage()
    }

    func compatibleEqualizerProfiles(for layout: EqualizerLayoutID) -> [SavedEqualizerProfile] {
        equalizerProfiles.filter { $0.layout == layout }
    }

    @discardableResult
    func saveEqualizerProfile(named proposedName: String, settings: EqualizerSettings) -> SavedEqualizerProfile? {
        guard validate(settings), canSaveEqualizerChanges else { return nil }
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "My EQ \(compatibleEqualizerProfiles(for: settings.layout).count + 1)" : String(trimmed.prefix(32))
        let profile: SavedEqualizerProfile
        if let index = equalizerProfiles.firstIndex(where: {
            $0.layout == settings.layout && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            equalizerProfiles[index].settings = settings
            profile = equalizerProfiles[index]
        } else {
            profile = SavedEqualizerProfile(id: UUID(), name: name, settings: settings)
            equalizerProfiles.append(profile)
        }
        return persistEqualizerStorage() ? profile : nil
    }

    func deleteEqualizerProfile(id: UUID) {
        guard canSaveEqualizerChanges else { return }
        equalizerProfiles.removeAll { $0.id == id }
        persistEqualizerStorage()
    }

    private func validate(_ settings: EqualizerSettings) -> Bool {
        guard settings.isValid else {
            equalizerStorageError = "This EQ curve does not match a supported layout or gain range. Saved data is unchanged."
            return false
        }
        return true
    }

    @discardableResult
    private func persistEqualizerStorage() -> Bool {
        guard canSaveEqualizerChanges else { return false }
        do {
            let data = try JSONEncoder().encode(EqualizerStorageV2(drafts: equalizerDrafts, profiles: equalizerProfiles))
            defaults.set(data, forKey: Keys.equalizerStorageV2)
            return true
        } catch {
            equalizerStorageError = "EQ changes could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private struct EqualizerStorageV2: Encodable {
        let version = 2
        let drafts: [String: EqualizerSettings]
        let profiles: [SavedEqualizerProfile]

        init(drafts: [EqualizerLayoutID: EqualizerSettings], profiles: [SavedEqualizerProfile]) {
            self.drafts = Dictionary(uniqueKeysWithValues: drafts.map { ($0.key.rawValue, $0.value) })
            self.profiles = profiles
        }
    }

    private struct LoadedStorage {
        var drafts: [EqualizerLayoutID: EqualizerSettings] = [:]
        var profiles: [SavedEqualizerProfile] = []
        var hadInvalidRecords = false
    }

    private static func readV2(_ data: Data) -> LoadedStorage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 2,
              let drafts = object["drafts"] as? [String: Any],
              let profiles = object["profiles"] as? [Any] else { return nil }
        var loaded = LoadedStorage()
        for (key, value) in drafts {
            guard let layout = EqualizerLayoutID(rawValue: key),
                  let settings = decodeRecord(EqualizerSettings.self, value), settings.layout == layout else {
                loaded.hadInvalidRecords = true
                continue
            }
            loaded.drafts[layout] = settings
        }
        var seenIDs: Set<UUID> = []
        for value in profiles {
            guard let profile = decodeRecord(SavedEqualizerProfile.self, value), seenIDs.insert(profile.id).inserted else {
                loaded.hadInvalidRecords = true
                continue
            }
            loaded.profiles.append(profile)
        }
        return loaded
    }

    // Separate DTOs ensure legacy shapes do not weaken the v2 decoder.
    private struct LegacySettings: Decodable {
        let clearBass: Int
        let bands: [Int]

        var migrated: EqualizerSettings? {
            guard (-10...10).contains(clearBass), bands.count == 5, bands.allSatisfy((-10...10).contains) else { return nil }
            return EqualizerSettings(clearBass: clearBass, bands: bands)
        }
    }

    private struct LegacyProfile: Decodable {
        let id: UUID
        let name: String
        let settings: LegacySettings
    }

    private static func readLegacy(_ defaults: UserDefaults) -> LoadedStorage {
        var loaded = LoadedStorage()
        if let raw = defaults.object(forKey: Keys.customEqualizerDraft) {
            if let data = raw as? Data, let draft = try? JSONDecoder().decode(LegacySettings.self, from: data),
               let settings = draft.migrated {
                loaded.drafts[.xm5SixValue] = settings
            } else { loaded.hadInvalidRecords = true }
        }
        if let raw = defaults.object(forKey: Keys.equalizerProfiles) {
            guard let data = raw as? Data, let records = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                loaded.hadInvalidRecords = true
                return loaded
            }
            var seenIDs: Set<UUID> = []
            for value in records {
                guard let profile = decodeRecord(LegacyProfile.self, value), let settings = profile.settings.migrated,
                      seenIDs.insert(profile.id).inserted else {
                    loaded.hadInvalidRecords = true
                    continue
                }
                loaded.profiles.append(SavedEqualizerProfile(id: profile.id, name: profile.name, settings: settings))
            }
        }
        return loaded
    }

    private static func decodeRecord<T: Decodable>(_ type: T.Type, _ object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let reconnectAutomatically = "preferences.reconnectAutomatically"
        static let globalShortcutEnabled = "preferences.globalShortcutEnabled"
        static let customEqualizerDraft = "preferences.customEqualizerDraft"
        static let equalizerProfiles = "preferences.equalizerProfiles"
        static let equalizerStorageV2 = "preferences.equalizerStorage.v2"
    }
}
