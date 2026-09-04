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
        if CommandLine.arguments.contains("-ui-testing") {
            let suiteName = "local.xm5control.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            return AppEnvironment(
                settings: SettingsStore(defaults: defaults),
                headphones: SonyHeadphonesController(startAutomatically: false, simulatedReady: true)
            )
        }
        return AppEnvironment(
            settings: SettingsStore(defaults: .standard, managesLaunchService: true),
            headphones: SonyHeadphonesController()
        )
    }
}
