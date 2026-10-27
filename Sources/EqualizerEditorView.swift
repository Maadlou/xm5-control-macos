import SwiftUI

struct EqualizerEditorView: View {
    @EnvironmentObject private var headphones: SonyHeadphonesController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var profileName = ""
    @State private var offlineLayout: EqualizerLayoutID = .xm5SixValue
    @State private var locallyEditedLayouts: Set<EqualizerLayoutID> = []

    private var isConnecting: Bool { headphones.linkState == .opening || headphones.linkState == .handshaking }
    private var specification: EqualizerSpecification? {
        if headphones.isReady { return headphones.equalizerSpecification }
        return isConnecting ? nil : offlineLayout.specification
    }
    private var canApplyLive: Bool { headphones.isReady && headphones.equalizerSpecification != nil }
    private var confirmationText: String {
        if !canApplyLive { return "Offline editing" }
        if headphones.isApplyingChange { return "Applying…" }
        if headphones.lastErrorMessage != nil { return "Not confirmed" }
        guard let specification else { return "Unavailable" }
        return headphones.hasReportedEqualizerCurve && headphones.equalizerPreset?.rawValue == 0xA0 && settings.equalizerDraft(for: specification.id) == headphones.customEqualizer ? "Synced" : "Draft"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            ScrollView {
                VStack(spacing: 16) {
                    if !headphones.isReady && !isConnecting {
                        Picker("Offline EQ layout", selection: $offlineLayout) {
                            Text("XM5: five bands + Clear Bass").tag(EqualizerLayoutID.xm5SixValue)
                            Text("XM6: ten bands").tag(EqualizerLayoutID.xm6TenBand)
                        }
                        .accessibilityIdentifier("equalizer.offlineLayout")
                    }
                    if let specification {
                        curvePreview(specification)
                        controls(specification).id(specification.id)
                        savedProfiles(specification)
                    } else {
                        Text(headphones.equalizerUnavailableReason ?? "Waiting for the headphone controls…")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("equalizer.unavailable")
                    }
                    if let error = headphones.lastErrorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("equalizer.commandError")
                    }
                }.padding(20)
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 430, height: 590)
        .background(.ultraThinMaterial)
        .onAppear {
            offlineLayout = headphones.lastKnownEqualizerLayout ?? .xm5SixValue
            syncReportedDraft()
        }
        .onChange(of: headphones.equalizerSpecification?.id) { _, _ in syncReportedDraft() }
        .onChange(of: headphones.customEqualizer) { _, _ in syncReportedDraft() }
        .onChange(of: headphones.pendingEqualizer) { _, _ in syncReportedDraft() }
        .onChange(of: headphones.lastSyncDate) { _, _ in syncReportedDraft() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("equalizer.editor")
    }
    private func syncReportedDraft() {
        guard let specification = headphones.equalizerSpecification,
              headphones.lastErrorMessage == nil, headphones.hasReportedEqualizerCurve,
              headphones.equalizerPreset?.rawValue == 0xA0, headphones.pendingEqualizer == nil,
              headphones.customEqualizer.layout == specification.id else { return }
        if locallyEditedLayouts.contains(specification.id),
           settings.equalizerDraft(for: specification.id) != headphones.customEqualizer { return }
        locallyEditedLayouts.remove(specification.id)
        settings.setEqualizerDraft(headphones.customEqualizer)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Equalizer").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(canApplyLive ? "Changes apply live to \(headphones.deviceName)" : "Edit and save while disconnected")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let specification { locallyEditedLayouts.remove(specification.id) }
                headphones.refreshEqualizer()
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(!canApplyLive)
                .accessibilityLabel("Sync equalizer from headphones")
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).font(.system(size: 18)).foregroundStyle(.secondary)
                .accessibilityLabel("Close equalizer editor")
        }.padding(18)
    }
    private func curvePreview(_ specification: EqualizerSpecification) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05))
            Divider().opacity(0.28)
            EqualizerCurve(values: settings.equalizerDraft(for: specification.id).bands, gainLimit: specification.gainRange.upperBound)
                .stroke(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 22).padding(.vertical, 15)
        }.frame(height: 92).accessibilityHidden(true)
    }
    private func controls(_ specification: EqualizerSpecification) -> some View {
        VStack(spacing: 13) {
            if specification.hasClearBass {
                equalizerRow(title: "Clear Bass", identifier: "Clear Bass", specification: specification, band: nil)
                Divider().opacity(0.45)
            }
            ForEach(specification.bandLabels.indices, id: \.self) { index in
                equalizerRow(title: specification.bandLabels[index], identifier: "equalizer.band.\(specification.id.rawValue).\(index)",
                             specification: specification, band: index)
            }
        }.padding(15)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
    private func valueBinding(_ specification: EqualizerSpecification, band: Int?) -> Binding<Double> {
        Binding(get: {
            let draft = settings.equalizerDraft(for: specification.id)
            return Double(band.map { draft.bands[$0] } ?? draft.clearBass ?? 0)
        }, set: { value in
            // A slider being removed during a model change must not write into the new layout.
            guard self.specification?.id == specification.id else { return }
            var draft = settings.equalizerDraft(for: specification.id)
            if let band { draft[band: band] = Int(value.rounded()) }
            else { draft.clearBass = max(specification.gainRange.lowerBound, min(specification.gainRange.upperBound, Int(value.rounded()))) }
            apply(draft)
        })
    }
    private func equalizerRow(title: String, identifier: String, specification: EqualizerSpecification, band: Int?) -> some View {
        let binding = valueBinding(specification, band: band)
        return HStack(spacing: 10) {
            Label(title, systemImage: band == nil ? "speaker.wave.3.fill" : "waveform")
                .font(.system(size: 11, weight: .medium)).frame(width: 92, alignment: .leading)
            Slider(value: binding, in: Double(specification.gainRange.lowerBound)...Double(specification.gainRange.upperBound), step: 1)
                .accessibilityLabel(title).accessibilityValue(signed(Int(binding.wrappedValue)))
                .accessibilityIdentifier(identifier)
            Text(signed(Int(binding.wrappedValue))).font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit().frame(width: 30).accessibilityHidden(true)
        }
    }
    private func savedProfiles(_ specification: EqualizerSpecification) -> some View {
        let profiles = settings.compatibleEqualizerProfiles(for: specification.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("MAC PRESETS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(0.7)
            HStack(spacing: 8) {
                TextField("Preset name", text: $profileName).textFieldStyle(.roundedBorder).onSubmit(saveProfile)
                Button("Save", action: saveProfile).buttonStyle(.borderedProminent).disabled(!settings.canSaveEqualizerChanges)
            }
            if let error = settings.equalizerStorageError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).accessibilityIdentifier("equalizer.storageError")
            }
            if profiles.isEmpty {
                Text("Saved on this Mac for this EQ layout. Applying a profile sends its curve to the headphones.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(profiles) { profile in
                    HStack {
                        Button { apply(profile.settings) } label: {
                            Label(profile.name, systemImage: "play.fill").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { settings.deleteEqualizerProfile(id: profile.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                            .disabled(!settings.canSaveEqualizerChanges).accessibilityLabel("Delete \(profile.name)")
                    }.padding(.horizontal, 11).frame(height: 32)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
    private var footer: some View {
        HStack {
            Button("Reset Flat") {
                if let specification { apply(.flat(for: specification.id)) }
            }.buttonStyle(.borderless).disabled(specification == nil)
            Spacer()
            #if DEBUG
            if CommandLine.arguments.contains("-ui-testing") && CommandLine.arguments.contains("--ui-test-host") {
                Button("XM5") { headphones.useSimulation(.xm5) }.accessibilityIdentifier("simulation.switch.xm5")
                Button("XM6") { headphones.useSimulation(.xm6) }.accessibilityIdentifier("simulation.switch.xm6")
                Button("Noise") { headphones.setNoiseControl(.anc) }.accessibilityIdentifier("simulation.noise")
            }
            #endif
            if headphones.isApplyingChange { ProgressView().controlSize(.small).accessibilityLabel("Applying equalizer") }
            Text(confirmationText).font(.system(size: 10, weight: .medium))
                .foregroundStyle(headphones.lastErrorMessage == nil ? Color.secondary : .orange)
                .accessibilityIdentifier("equalizer.confirmation")
        }.padding(.horizontal, 20).frame(height: 48)
    }
    private func apply(_ equalizer: EqualizerSettings) {
        guard specification?.id == equalizer.layout else { return }
        locallyEditedLayouts.insert(equalizer.layout)
        settings.setEqualizerDraft(equalizer)
        if canApplyLive { headphones.setCustomEqualizer(equalizer) }
    }
    private func saveProfile() {
        guard let specification,
              let profile = settings.saveEqualizerProfile(named: profileName, settings: settings.equalizerDraft(for: specification.id)) else { return }
        profileName = ""; apply(profile.settings)
    }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}

private struct EqualizerCurve: Shape {
    let values: [Int]
    let gainLimit: Int
    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let points = values.indices.map { index in
            CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.midY - CGFloat(values[index]) / CGFloat(max(1, gainLimit)) * rect.height / 2)
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], current = points[index], midpoint = (previous.x + current.x) / 2
            path.addCurve(to: current, control1: CGPoint(x: midpoint, y: previous.y), control2: CGPoint(x: midpoint, y: current.y))
        }
        return path
    }
}
