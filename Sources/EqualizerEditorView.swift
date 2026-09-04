import SwiftUI

struct EqualizerEditorView: View {
    @EnvironmentObject private var headphones: SonyHeadphonesController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var profileName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            ScrollView {
                VStack(spacing: 16) {
                    curvePreview
                    controls
                    savedProfiles
                }
                .padding(20)
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 430, height: 590)
        .background(.ultraThinMaterial)
        .onAppear {
            if headphones.equalizerPreset == .manual {
                settings.customEqualizerDraft = headphones.customEqualizer
            }
        }
        .accessibilityIdentifier("equalizer.editor")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Equalizer")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(headphones.isReady ? "Changes apply live to your XM5" : "Edit and save while disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { headphones.refreshEqualizer() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!headphones.isReady)
            .help("Read the current EQ from the headphones")
            .accessibilityLabel("Sync equalizer from headphones")
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close equalizer editor")
        }
        .padding(18)
    }

    private var curvePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            VStack(spacing: 0) {
                Spacer()
                Divider().opacity(0.28)
                Spacer()
            }
            EqualizerCurve(values: settings.customEqualizerDraft.bands)
                .stroke(
                    LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .shadow(color: .blue.opacity(0.25), radius: 8)
        }
        .frame(height: 92)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 13) {
            equalizerRow(title: "Clear Bass", symbol: "speaker.wave.3.fill", value: clearBassBinding)
            Divider().opacity(0.45)
            ForEach(EqualizerSettings.bandLabels.indices, id: \.self) { index in
                equalizerRow(
                    title: EqualizerSettings.bandLabels[index],
                    symbol: "waveform",
                    value: bandBinding(index)
                )
            }
        }
        .padding(15)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func equalizerRow(title: String, symbol: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 92, alignment: .leading)
            Slider(value: value, in: -10...10, step: 1)
            Text(signed(Int(value.wrappedValue)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value.wrappedValue == 0 ? Color.secondary : Color.primary)
                .frame(width: 30)
        }
    }

    @ViewBuilder
    private var savedProfiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MAC PRESETS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.7)

            HStack(spacing: 8) {
                TextField("Preset name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveProfile)
                Button("Save") { saveProfile() }
                    .buttonStyle(.borderedProminent)
            }

            if settings.equalizerProfiles.isEmpty {
                Text("Saved on this Mac. Applying one writes its curve to the headphones, where Sound Connect can read the active Manual EQ.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(settings.equalizerProfiles) { profile in
                        HStack {
                            Button {
                                apply(profile.settings)
                            } label: {
                                Label(profile.name, systemImage: "play.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button {
                                settings.deleteEqualizerProfile(id: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Delete \(profile.name)")
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset Flat") { apply(.flat) }
                .buttonStyle(.borderless)
            Spacer()
            if headphones.isApplyingChange {
                ProgressView().controlSize(.small)
            } else {
                Label(headphones.isReady ? "Live" : "Offline", systemImage: headphones.isReady ? "checkmark.circle.fill" : "icloud.slash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(headphones.isReady ? Color.green : Color.secondary)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private var clearBassBinding: Binding<Double> {
        Binding(
            get: { Double(settings.customEqualizerDraft.clearBass) },
            set: { value in
                var draft = settings.customEqualizerDraft
                draft.clearBass = max(-10, min(10, Int(value.rounded())))
                apply(draft)
            }
        )
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { Double(settings.customEqualizerDraft[band: index]) },
            set: { value in
                var draft = settings.customEqualizerDraft
                draft[band: index] = Int(value.rounded())
                apply(draft)
            }
        )
    }

    private func apply(_ equalizer: EqualizerSettings) {
        settings.customEqualizerDraft = equalizer
        headphones.setCustomEqualizer(equalizer)
    }

    private func saveProfile() {
        let profile = settings.saveEqualizerProfile(named: profileName)
        profileName = ""
        apply(profile.settings)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct EqualizerCurve: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        let points = (0..<5).map { index -> CGPoint in
            let x = rect.minX + rect.width * CGFloat(index) / 4
            let value = CGFloat(index < values.count ? values[index] : 0)
            let y = rect.midY - value / 10 * rect.height / 2
            return CGPoint(x: x, y: y)
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midpoint, y: previous.y),
                control2: CGPoint(x: midpoint, y: current.y)
            )
        }
        return path
    }
}
