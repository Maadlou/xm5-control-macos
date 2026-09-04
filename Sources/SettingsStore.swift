import Combine
import Foundation
import ServiceManagement

struct SavedEqualizerProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var settings: EqualizerSettings
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
    @Published var customEqualizerDraft: EqualizerSettings {
        didSet { persist(customEqualizerDraft, forKey: Keys.customEqualizerDraft) }
    }
    @Published private(set) var equalizerProfiles: [SavedEqualizerProfile] {
        didSet { persist(equalizerProfiles, forKey: Keys.equalizerProfiles) }
    }

    private let defaults: UserDefaults

    private let managesLaunchService: Bool

    init(defaults: UserDefaults, managesLaunchService: Bool = false) {
        self.defaults = defaults
        self.managesLaunchService = managesLaunchService
        reconnectAutomatically = defaults.object(forKey: Keys.reconnectAutomatically) == nil
            ? true
            : defaults.bool(forKey: Keys.reconnectAutomatically)
        launchAtLogin = managesLaunchService && SMAppService.mainApp.status == .enabled
        globalShortcutEnabled = defaults.object(forKey: Keys.globalShortcutEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.globalShortcutEnabled)
        customEqualizerDraft = Self.decode(EqualizerSettings.self, from: defaults.data(forKey: Keys.customEqualizerDraft)) ?? .flat
        equalizerProfiles = Self.decode([SavedEqualizerProfile].self, from: defaults.data(forKey: Keys.equalizerProfiles)) ?? []
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard managesLaunchService else {
            launchAtLogin = enabled
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    @discardableResult
    func saveEqualizerProfile(named proposedName: String) -> SavedEqualizerProfile {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "My EQ \(equalizerProfiles.count + 1)" : String(trimmed.prefix(32))
        if let index = equalizerProfiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            equalizerProfiles[index].settings = customEqualizerDraft
            return equalizerProfiles[index]
        }
        let profile = SavedEqualizerProfile(id: UUID(), name: name, settings: customEqualizerDraft)
        equalizerProfiles.append(profile)
        return profile
    }

    func deleteEqualizerProfile(id: UUID) {
        equalizerProfiles.removeAll { $0.id == id }
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let reconnectAutomatically = "preferences.reconnectAutomatically"
        static let globalShortcutEnabled = "preferences.globalShortcutEnabled"
        static let customEqualizerDraft = "preferences.customEqualizerDraft"
        static let equalizerProfiles = "preferences.equalizerProfiles"
    }
}
