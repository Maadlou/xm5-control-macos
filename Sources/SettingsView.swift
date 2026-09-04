import AppKit
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
            Section("Diagnostics") {
                LabeledContent("Bluetooth audio", value: headphones.isDeviceConnected ? "Connected" : "Disconnected")
                LabeledContent("Control link", value: headphones.statusText)
                LabeledContent("Protocol", value: diagnosticsProtocol)
                LabeledContent("Firmware", value: headphones.firmwareVersion ?? "Unknown")
                LabeledContent("Last sync", value: lastSyncText)
                if let error = headphones.lastErrorMessage {
                    LabeledContent("Last issue") {
                        Text(error)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
                HStack {
                    Button("Sync Now") { headphones.refresh() }
                    Spacer()
                    Button("Copy Diagnostics") { copyDiagnostics() }
                }
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
        .frame(width: 500, height: 600)
    }

    private var diagnosticsProtocol: String {
        headphones.controlChannelID.map { "MDR v2 · RFCOMM \($0)" } ?? "MDR v2"
    }

    private var lastSyncText: String {
        headphones.lastSyncDate?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(headphones.diagnosticReport, forType: .string)
    }
}
