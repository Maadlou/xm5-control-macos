import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var headphones: SonyHeadphonesController

    var body: some View {
        Form {
            Section("Headphones") {
                LabeledContent("Model", value: headphones.deviceName)
                LabeledContent("Bluetooth address", value: headphones.address.isEmpty ? "Not found" : headphones.address)
                LabeledContent("Sony control", value: headphones.isReady ? "Ready" : headphones.statusText)
            }
            Section("Connection") {
                Toggle("Reconnect control link automatically", isOn: $settings.reconnectAutomatically)
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                if let error = settings.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("XM5 Control uses Sony's Serial HPC service. Audio remains managed by macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Toggle("Global ANC / Ambient shortcut", isOn: $settings.globalShortcutEnabled)
                LabeledContent("Shortcut", value: "⌥⌘A")
                Text("Works while XM5 Control is running and does not require Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 430)
    }
}
