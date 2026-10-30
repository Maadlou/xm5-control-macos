import Combine
import Foundation

@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let headphones: SonyHeadphonesController
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore, headphones: SonyHeadphonesController) {
        self.settings = settings
        self.headphones = headphones
        settings.$reconnectAutomatically
            .removeDuplicates()
            .sink { [weak headphones] enabled in
                headphones?.setReconnectAutomatically(enabled)
            }
            .store(in: &cancellables)
    }

    static func live() -> AppEnvironment {
        #if DEBUG
        if CommandLine.arguments.contains("-ui-testing") {
            let suiteName = "local.xm5control.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            if CommandLine.arguments.contains("--ui-test-storage-error") {
                defaults.set(Data("unreadable-storage".utf8), forKey: "preferences.equalizerStorage.v2")
            }
            let arguments = CommandLine.arguments
            let index = arguments.firstIndex(of: "--ui-test-model")
            let raw = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "xm5"
            let scenario = SonyHeadphonesController.SimulatedScenario(rawValue: raw) ?? .xm5
            let settings = SettingsStore(defaults: defaults)
            if arguments.contains("--ui-test-seed-profiles") {
                settings.saveEqualizerProfile(named: "XM5 only", settings: .flat)
                settings.saveEqualizerProfile(named: "XM6 only", settings: .flat(for: .xm6TenBand))
            }
            if arguments.contains("--ui-test-seed-draft") {
                settings.setEqualizerDraft(EqualizerSettings(layout: .xm6TenBand, clearBass: nil, bands: [2,0,0,0,0,0,0,0,0,0]))
            }
            return AppEnvironment(settings: settings, headphones: SonyHeadphonesController(simulatedScenario: scenario))
        }
        // Hosted unit tests must not open the user's Bluetooth link or migrate real preferences.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let defaults = UserDefaults(suiteName: "local.xm5control.unit-host") ?? .standard
            return AppEnvironment(settings: SettingsStore(defaults: defaults), headphones: SonyHeadphonesController(startAutomatically: false))
        }
        #endif
        return AppEnvironment(
            settings: SettingsStore(defaults: .standard, managesLaunchService: true),
            headphones: SonyHeadphonesController()
        )
    }
}
