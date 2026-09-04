import AppKit
import SwiftUI

private enum ListeningPreset: String, CaseIterable, Identifiable {
    case focus, office, aware

    var id: Self { self }
    var title: String {
        switch self {
        case .focus: "Focus"
        case .office: "Office"
        case .aware: "Aware"
        }
    }
    var symbol: String {
        switch self {
        case .focus: "moon.stars.fill"
        case .office: "person.2.fill"
        case .aware: "figure.walk"
        }
    }
    var mode: NoiseControlMode { self == .focus ? .anc : .ambient }
    var level: Int {
        switch self {
        case .focus: 10
        case .office: 8
        case .aware: 20
        }
    }
    var focusOnVoice: Bool { self == .office }
}

struct MenuBarView: View {
    @EnvironmentObject private var headphones: SonyHeadphonesController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEqualizerEditor = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider().opacity(0.55)
            controls
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 390)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingEqualizerEditor) {
            EqualizerEditorView()
                .environmentObject(headphones)
                .environmentObject(settings)
        }
        .accessibilityIdentifier("headphones.dashboard")
    }

    private var hero: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headphones.deviceName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .accessibilityIdentifier("menu.title")
                    Label(headphones.statusText, systemImage: headphones.isReady ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(headphones.isReady ? Color.green : Color.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let battery = headphones.batteryLevel {
                    Label("\(battery)%", systemImage: headphones.isCharging ? "battery.100percent.bolt" : batterySymbol(battery))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(battery <= 15 ? Color.red : Color.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel("Battery \(battery) percent\(headphones.isCharging ? ", charging" : "")")
                }
                Button { headphones.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh headphone status")
                    .accessibilityLabel("Refresh headphone status")
            }

            ZStack {
                acousticAura
                Image("XM5Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 154)
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                    .accessibilityHidden(true)

                if headphones.isApplyingChange {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 116, y: 56)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Applying headphone setting")
                }
            }
            .frame(height: 166)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: headphones.noiseControlMode)
            .animation(.easeOut(duration: 0.18), value: headphones.isApplyingChange)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var acousticAura: some View {
        ZStack {
            Circle()
                .fill(modeColor.opacity(0.12))
                .frame(width: 150, height: 150)
                .blur(radius: 18)
            if headphones.noiseControlMode == .ambient {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(modeColor.opacity(0.24 - Double(index) * 0.055), lineWidth: 1)
                        .frame(width: 150 + CGFloat(index * 28), height: 150 + CGFloat(index * 28))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Noise control").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let mode = headphones.noiseControlMode {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(modeColor)
                }
            }

            HStack(spacing: 8) {
                modeButton(.off)
                modeButton(.anc)
                modeButton(.ambient)
            }

            if headphones.noiseControlMode == .ambient {
                ambientControls.transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(ListeningPreset.allCases) { preset in
                        Button {
                            headphones.applyPreset(mode: preset.mode, ambientLevel: preset.level, focusOnVoice: preset.focusOnVoice)
                        } label: {
                            Label(preset.title, systemImage: preset.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!headphones.isReady)
                        .help(presetDescription(preset))
                    }
                }
            }

            HStack(spacing: 10) {
                Label("Equalizer", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Menu {
                    ForEach(EqualizerPreset.selectableCases) { preset in
                        Button {
                            headphones.setEqualizerPreset(preset)
                        } label: {
                            if headphones.equalizerPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                    if !settings.equalizerProfiles.isEmpty {
                        Divider()
                        Menu("Mac Presets") {
                            ForEach(settings.equalizerProfiles) { profile in
                                Button(profile.name) {
                                    settings.customEqualizerDraft = profile.settings
                                    headphones.setCustomEqualizer(profile.settings)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Custom Equalizer…") { showingEqualizerEditor = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(headphones.equalizerPreset?.title ?? "Unavailable")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(minWidth: 100, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!headphones.isReady)
                .help("Choose a Sony equalizer preset")
                .accessibilityIdentifier("equalizer.preset")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            connectionMessage
        }
        .padding(18)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: headphones.noiseControlMode)
    }

    private var ambientControls: some View {
        VStack(spacing: 11) {
            HStack {
                Label("Ambient sound", systemImage: "ear").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(headphones.ambientLevel)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(headphones.ambientLevel) },
                    set: { headphones.setAmbientLevel(Int($0.rounded())) }
                ),
                in: 1...20,
                step: 1
            )
            Toggle(
                "Focus on voice",
                isOn: Binding(
                    get: { headphones.focusOnVoice },
                    set: { headphones.setFocusOnVoice($0) }
                )
            )
            .font(.system(size: 12, weight: .medium))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(13)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var connectionMessage: some View {
        if case .failed(let message) = headphones.linkState {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if !headphones.isDeviceConnected {
            VStack(alignment: .leading, spacing: 10) {
                Label("Power on the headphones, then connect them here.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Connect WH-1000XM5") { headphones.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("headphones.connect")
            }
        }
    }

    private func modeButton(_ mode: NoiseControlMode) -> some View {
        let selected = headphones.noiseControlMode == mode
        return Button { headphones.setNoiseControl(mode) } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol).font(.system(size: 16, weight: .semibold))
                Text(mode.compactTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 57)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? modeColor : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!headphones.isReady)
        .accessibilityIdentifier("noiseControl.\(mode.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }
                .buttonStyle(.borderless)
            Spacer()
            Text("⌥⌘A · ANC / Ambient").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("app.quit")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var modeColor: Color {
        switch headphones.noiseControlMode {
        case .anc: Color(red: 0.25, green: 0.48, blue: 0.98)
        case .ambient: Color(red: 0.12, green: 0.66, blue: 0.78)
        case .wind: Color(red: 0.45, green: 0.55, blue: 0.95)
        default: .secondary
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ...15: "battery.0percent"
        case ...50: "battery.25percent"
        case ...80: "battery.50percent"
        default: "battery.100percent"
        }
    }

    private func presetDescription(_ preset: ListeningPreset) -> String {
        switch preset {
        case .focus: "Noise cancelling for uninterrupted listening"
        case .office: "Ambient level 8 with voice focus"
        case .aware: "Maximum ambient awareness"
        }
    }
}
