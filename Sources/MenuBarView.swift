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

private enum XM5Palette {
    static let canvas = Color(red: 0.115, green: 0.115, blue: 0.112)
    static let raised = Color(red: 0.15, green: 0.15, blue: 0.145)
    static let soft = Color.white.opacity(0.055)
    static let line = Color.white.opacity(0.14)
    static let ink = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let muted = Color(red: 0.59, green: 0.59, blue: 0.57)
    static let accent = Color(red: 0.82, green: 0.67, blue: 0.43)
    static let success = Color(red: 0.43, green: 0.72, blue: 0.57)
}

private enum PanelScreen {
    case dashboard
    case settings
}

enum MenuBarMetrics {
    static let displaySize = CGSize(width: 344, height: 606)
    static let contentInset: CGFloat = 18
}

private struct NoiseControlGlyph: Shape {
    let mode: NoiseControlMode

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch mode {
        case .off:
            path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        case .anc:
            addLine(to: &path, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 21))
            addLine(to: &path, from: CGPoint(x: 10, y: 3), to: CGPoint(x: 10, y: 4.35))
            addLine(to: &path, from: CGPoint(x: 14, y: 14), to: CGPoint(x: 14, y: 15))
            addLine(to: &path, from: CGPoint(x: 14, y: 8), to: CGPoint(x: 14, y: 8.35))
            addLine(to: &path, from: CGPoint(x: 18, y: 5), to: CGPoint(x: 18, y: 12.35))
            addLine(to: &path, from: CGPoint(x: 2, y: 10), to: CGPoint(x: 2, y: 13))
            addLine(to: &path, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 22, y: 22))
            addLine(to: &path, from: CGPoint(x: 22, y: 10), to: CGPoint(x: 22, y: 13))
            addLine(to: &path, from: CGPoint(x: 6, y: 6), to: CGPoint(x: 6, y: 17))
        case .ambient, .wind:
            path.move(to: CGPoint(x: 2, y: 16))
            path.addLine(to: CGPoint(x: 14, y: 16))
            path.addCurve(
                to: CGPoint(x: 12.8, y: 19.6),
                control1: CGPoint(x: 16.65, y: 16),
                control2: CGPoint(x: 15.65, y: 20.85)
            )

            path.move(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 19.5, y: 12))
            path.addCurve(
                to: CGPoint(x: 17.5, y: 8),
                control1: CGPoint(x: 22.8, y: 12),
                control2: CGPoint(x: 21.35, y: 6.35)
            )

            path.move(to: CGPoint(x: 2, y: 8))
            path.addLine(to: CGPoint(x: 11, y: 8))
            path.addCurve(
                to: CGPoint(x: 9.8, y: 4.4),
                control1: CGPoint(x: 13.65, y: 8),
                control2: CGPoint(x: 12.65, y: 3.15)
            )
        }

        let scale = min(rect.width, rect.height) / 24
        let xOffset = rect.midX - (12 * scale)
        let yOffset = rect.midY - (12 * scale)
        return path.applying(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: xOffset, ty: yOffset)
        )
    }

    private func addLine(to path: inout Path, from start: CGPoint, to end: CGPoint) {
        path.move(to: start)
        path.addLine(to: end)
    }
}

private struct CircularModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct HeaderActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isHovering ? XM5Palette.ink : XM5Palette.muted)
                .background(XM5Palette.soft.opacity(isHovering ? 2 : 1), in: Circle())
                .overlay(Circle().stroke(XM5Palette.line, lineWidth: 0.75))
                .contentShape(Circle())
        }
        .buttonStyle(CircularModeButtonStyle())
        .onContinuousHover { isHovering = $0 != .ended }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct SceneButton: View {
    let preset: ListeningPreset
    let selected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(XM5Palette.accent)
                Text(preset.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(XM5Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                selected ? XM5Palette.accent.opacity(0.12) : XM5Palette.soft.opacity(isHovering ? 2 : 1),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? XM5Palette.accent.opacity(0.55) : XM5Palette.line, lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(CircularModeButtonStyle())
        .onContinuousHover { isHovering = $0 != .ended }
    }
}

private struct ListeningModeButton: View {
    let mode: NoiseControlMode
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(selected ? XM5Palette.accent : (isHovering ? XM5Palette.soft : XM5Palette.raised))
                    Circle()
                        .stroke(selected ? XM5Palette.accent : XM5Palette.line, lineWidth: 1)
                    NoiseControlGlyph(mode: mode)
                        .stroke(
                            selected ? XM5Palette.canvas : (isHovering ? XM5Palette.ink : XM5Palette.muted),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 24, height: 24)
                }
                .frame(width: 52, height: 52)
                .shadow(color: selected ? XM5Palette.accent.opacity(0.18) : .clear, radius: 8, y: 3)

                Text(mode.compactTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(selected ? XM5Palette.accent : (isHovering ? XM5Palette.ink : XM5Palette.muted))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(CircularModeButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .onContinuousHover { isHovering = enabled && $0 != .ended }
        .accessibilityIdentifier("noiseControl.\(mode.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AmbientLevelTrack: View {
    let level: Int
    let onChange: (Int) -> Void
    @State private var isHovering = false

    private var progress: CGFloat {
        CGFloat(level - 1) / 19
    }

    var body: some View {
        GeometryReader { proxy in
            let thumbSize: CGFloat = 16
            let trackWidth = max(1, proxy.size.width - thumbSize)

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(XM5Palette.line)
                    .frame(width: trackWidth, height: 4)
                    .offset(x: thumbSize / 2, y: 5)

                Capsule()
                    .fill(XM5Palette.accent)
                    .frame(width: max(4, trackWidth * progress), height: 4)
                    .offset(x: thumbSize / 2, y: 5)

                Circle()
                    .fill(XM5Palette.ink)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: .black.opacity(0.42), radius: isHovering ? 5 : 3, y: 2)
                    .offset(x: trackWidth * progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let normalized = min(1, max(0, (gesture.location.x - thumbSize / 2) / trackWidth))
                        let newLevel = Int((normalized * 19).rounded()) + 1
                        if newLevel != level { onChange(newLevel) }
                    }
            )
            .onContinuousHover { phase in
                isHovering = phase != .ended
            }
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel("Ambient sound level")
        .accessibilityValue("\(level) of 20")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(20, level + 1))
            case .decrement: onChange(max(1, level - 1))
            @unknown default: break
            }
        }
    }
}

private struct PassiveNoiseField: View {
    let mode: NoiseControlMode?

    var body: some View {
        ZStack {
            if mode == .anc {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<29, id: \.self) { index in
                        let distance = abs(CGFloat(index) - 14) / 14
                        Capsule()
                            .fill(XM5Palette.muted.opacity(0.18 + (distance * 0.38)))
                            .frame(width: 2, height: 3 + (distance * distance * 29))
                    }
                }
                .mask(
                    LinearGradient(
                        colors: [.clear, .white, .white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                Circle()
                    .fill(XM5Palette.accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: XM5Palette.accent.opacity(0.55), radius: 5)
            } else {
                Capsule()
                    .fill(XM5Palette.line)
                    .frame(width: 142, height: 1)

                ZStack {
                    Circle().fill(XM5Palette.canvas)
                    NoiseControlGlyph(mode: mode == .wind ? .ambient : .off)
                        .stroke(
                            XM5Palette.muted.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 18, height: 18)
                }
                .frame(width: 30, height: 30)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        switch mode {
        case .anc: "Noise cancellation on"
        case .off: "Noise control off"
        case .wind: "Wind reduction on"
        case .ambient: "Ambient sound on"
        case nil: "Headphone controls unavailable"
        }
    }
}

struct MenuBarView: View {
    var onSizeChange: ((CGSize) -> Void)? = nil
    @EnvironmentObject private var headphones: SonyHeadphonesController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEqualizerEditor = false
    @State private var screen: PanelScreen = .dashboard

    private var panelSize: CGSize {
        CGSize(width: MenuBarMetrics.displaySize.width,
               height: screen == .dashboard && !headphones.isReady ? 420 : MenuBarMetrics.displaySize.height)
    }

    var body: some View {
        ZStack {
            background
            if screen == .dashboard {
                dashboard
                    .transition(panelTransition(edge: .leading))
            } else {
                settingsPanel
                    .transition(panelTransition(edge: .trailing))
            }
        }
        .frame(
            width: MenuBarMetrics.displaySize.width,
            height: panelSize.height,
            alignment: .top
        )
        .clipped()
        .onChange(of: panelSize, initial: true) { _, size in
            onSizeChange?(size)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingEqualizerEditor) {
            EqualizerEditorView()
                .environmentObject(headphones)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
        .accessibilityIdentifier(screen == .dashboard ? "headphones.dashboard" : "settings.inline")
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            if headphones.isReady {
                hero
                controlDeck
            } else {
                connectionPanel
            }
        }
        .padding(.bottom, MenuBarMetrics.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var isConnecting: Bool {
        headphones.linkState == .opening || headphones.linkState == .handshaking
    }

    private var connectionTitle: String {
        switch headphones.linkState {
        case .opening, .handshaking: "Connecting to your headphones"
        case .controlBusy: "Audio connected. Controls unavailable."
        case .failed: "Couldn't connect"
        default: "Headphones disconnected"
        }
    }

    private var connectionGuidance: String {
        switch headphones.linkState {
        case .opening, .handshaking:
            "Keep your headphones switched on and nearby."
        case .controlBusy:
            "Close Sony Sound Connect on your phone, then try again."
        case .failed:
            "Check that your headphones are on and connected in Bluetooth settings, then try again."
        default:
            "Turn on your headphones to reconnect. If this is your first time, pair them in Bluetooth settings."
        }
    }

    private var connectionPanel: some View {
        VStack(spacing: 0) {
            header
            Image("XM5Hero")
                .resizable()
                .scaledToFit()
                .frame(height: 128)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 10)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 14) {
                    Text(connectionTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(XM5Palette.ink)
                    Text(connectionGuidance)
                        .font(.system(size: 12))
                        .foregroundStyle(XM5Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                    Button {
                        if headphones.isDeviceConnected {
                            headphones.refresh()
                        } else {
                            headphones.connect()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isConnecting {
                                ProgressView().controlSize(.small)
                            }
                            Text(isConnecting ? "Connecting…" : "Connect")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(XM5Palette.canvas)
                        .background(XM5Palette.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                    .accessibilityIdentifier("headphones.connect")

                    Button("Bluetooth settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(XM5Palette.ink)
                    .padding(.vertical, 6)
                    if let seconds = headphones.retrySecondsRemaining {
                        Text("Retrying in \(seconds)s")
                            .font(.system(size: 11))
                            .foregroundStyle(XM5Palette.muted)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, MenuBarMetrics.contentInset)
        .padding(.top, MenuBarMetrics.contentInset)
        .accessibilityIdentifier("headphones.connection")
    }

    private func panelTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var background: some View {
        ZStack {
            XM5Palette.canvas
            RadialGradient(
                colors: [XM5Palette.accent.opacity(0.075), .clear],
                center: UnitPoint(x: 0.86, y: 0.08),
                startRadius: 0,
                endRadius: 300
            )
            LinearGradient(
                colors: [Color.white.opacity(0.022), .clear, Color.black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(XM5Palette.accent.opacity(0.12))
                .frame(width: 153, height: 153)
                .blur(radius: 27)
                .offset(x: 184, y: 27)
                .accessibilityHidden(true)

            Image("XM5Hero")
                .resizable()
                .scaledToFit()
                .frame(width: 165, height: 156)
                .offset(x: 151, y: 61)
                .shadow(color: .black.opacity(0.72), radius: 20, x: 0, y: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer()
                statusReadout
            }
            .padding(.horizontal, MenuBarMetrics.contentInset)
            .padding(.top, MenuBarMetrics.contentInset)
            .padding(.bottom, 52)

        }
        .frame(height: 228)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle().fill(XM5Palette.line).frame(height: 1).padding(.horizontal, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headphones.deviceName)
                    .font(.system(size: 19, weight: .medium))
                    .tracking(-0.25)
                    .foregroundStyle(XM5Palette.ink)
                    .accessibilityIdentifier("menu.title")
                Text("XM5 Control")
                    .font(.system(size: 12))
                    .foregroundStyle(XM5Palette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                HeaderActionButton(symbol: "slider.horizontal.3", label: "Settings") {
                    navigate(to: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
                HeaderActionButton(symbol: "arrow.clockwise", label: "Refresh headphone status") {
                    headphones.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var statusReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(headphones.isReady ? XM5Palette.success : XM5Palette.muted)
                    .frame(width: 6, height: 6)
                    .shadow(color: headphones.isReady ? XM5Palette.success.opacity(0.55) : .clear, radius: 5)
                Text(headphones.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(XM5Palette.ink)
                    .lineLimit(1)
            }

            if let battery = headphones.batteryLevel {
                HStack(spacing: 8) {
                    Image(systemName: headphones.isCharging ? "battery.100percent.bolt" : "battery.\(min(100, max(0, Int((Double(battery) / 25).rounded()) * 25)))percent")
                        .font(.system(size: 18))
                    Text("\(battery)%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(battery <= 15 ? Color.red : XM5Palette.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery \(battery) percent\(headphones.isCharging ? ", charging" : "")")
            } else {
                Label("—", systemImage: "battery.0percent")
                    .font(.system(size: 12))
                    .foregroundStyle(XM5Palette.muted)
            }
        }
    }

    private var controlDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeSection
            modeDetailPanel
            presetSection
            equalizerRow
            connectionMessage
        }
        .padding(.horizontal, MenuBarMetrics.contentInset)
        .padding(.top, 16)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(
                "Listening mode",
                showsProgress: headphones.isApplyingChange
            )
            HStack(spacing: 9) {
                modeButton(.off)
                modeButton(.anc)
                modeButton(.ambient)
            }
            .padding(.horizontal, 8)
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ListeningPreset.allCases) { preset in
                    SceneButton(preset: preset, selected: isPresetSelected(preset)) {
                        headphones.applyPreset(
                            mode: preset.mode,
                            ambientLevel: preset.level,
                            focusOnVoice: preset.focusOnVoice
                        )
                    }
                    .disabled(!headphones.isReady)
                    .opacity(headphones.isReady ? 1 : 0.42)
                    .help(presetDescription(preset))
                    .accessibilityAddTraits(isPresetSelected(preset) ? .isSelected : [])
                }
            }
        }
    }

    private var equalizerRow: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Equalizer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(XM5Palette.ink)
            }
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
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(XM5Palette.accent)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!headphones.isReady)
            .help("Choose a Sony equalizer preset")
            .accessibilityIdentifier("equalizer.preset")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(XM5Palette.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(XM5Palette.line, lineWidth: 0.75))
    }

    private var modeDetailPanel: some View {
        ZStack {
            if headphones.noiseControlMode == .ambient {
                ambientControls
            } else {
                PassiveNoiseField(mode: headphones.noiseControlMode)
            }
        }
        .frame(height: 116)
    }

    private var ambientControls: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ambient sound")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(headphones.ambientLevel)")
                    .font(.system(size: 12))
                    .foregroundStyle(XM5Palette.muted)
                Text("/ 20")
                    .font(.system(size: 12))
                    .foregroundStyle(XM5Palette.muted)
            }

            AmbientLevelTrack(level: headphones.ambientLevel) {
                headphones.setAmbientLevel($0)
            }
            .padding(.top, 14)

            Rectangle()
                .fill(XM5Palette.line)
                .frame(height: 1)
                .padding(.top, 6)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Focus on voice")
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { headphones.focusOnVoice },
                        set: { headphones.setFocusOnVoice($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(XM5Palette.accent)
                .controlSize(.mini)
                .accessibilityLabel("Focus on voice")
            }
            .padding(.top, 6)
        }
        .foregroundStyle(XM5Palette.ink)
        .padding(14)
        .frame(height: 116)
        .background(XM5Palette.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(XM5Palette.line, lineWidth: 0.75))
    }

    @ViewBuilder
    private var connectionMessage: some View {
        if headphones.linkState == .controlBusy {
            VStack(alignment: .leading, spacing: 9) {
                Label("Bluetooth audio is connected, but Sony control is busy.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(XM5Palette.accent)
                HStack {
                    Text(headphones.retrySecondsRemaining.map { "Retrying in \($0)s" } ?? "Waiting to retry")
                        .font(.system(size: 10))
                        .foregroundStyle(XM5Palette.muted)
                    Spacer()
                    Button("Retry now") { headphones.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(XM5Palette.accent)
                }
            }
            .padding(11)
            .background(XM5Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if case .failed(let message) = headphones.linkState {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XM5Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        } else if !headphones.isDeviceConnected {
            VStack(alignment: .leading, spacing: 10) {
                Label("Power on the headphones, then connect them here.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(XM5Palette.muted)
                Button("Connect WH-1000XM5") { headphones.connect() }
                    .buttonStyle(.borderedProminent)
                    .tint(XM5Palette.accent)
                    .foregroundStyle(XM5Palette.canvas)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("headphones.connect")
            }
        }
    }

    private func modeButton(_ mode: NoiseControlMode) -> some View {
        let selected = headphones.noiseControlMode == mode
        return ListeningModeButton(
            mode: mode,
            selected: selected,
            enabled: headphones.isReady
        ) {
            headphones.setNoiseControl(mode)
        }
    }

    private func sectionHeading(
        _ title: String,
        value: String? = nil,
        showsProgress: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(XM5Palette.ink)
            Spacer()
            ProgressView()
                .controlSize(.mini)
                .tint(XM5Palette.accent)
                .frame(width: 12, height: 12)
                .opacity(showsProgress ? 1 : 0)
                .accessibilityHidden(!showsProgress)
                .accessibilityLabel("Applying headphone setting")
            if let value {
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(XM5Palette.accent)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsDeviceCard
                    settingsPreferences
                    settingsDiagnostics
                    Button { NSApp.terminate(nil) } label: {
                        Label("Quit XM5 Control", systemImage: "power")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(XM5Palette.muted)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("app.quit")
                }
                .padding(.horizontal, MenuBarMetrics.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            HeaderActionButton(symbol: "chevron.left", label: "Back to headphone controls") {
                navigate(to: .dashboard)
            }
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 2) {
                Text("CONTROL ROOM")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.55)
                    .foregroundStyle(XM5Palette.accent)
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(-0.35)
                    .foregroundStyle(XM5Palette.ink)
            }
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(XM5Palette.muted)
        }
        .padding(.horizontal, MenuBarMetrics.contentInset)
        .frame(height: 60)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .bottom) { Rectangle().fill(XM5Palette.line).frame(height: 1) }
    }

    private var settingsDeviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Headphones")
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(XM5Palette.accent.opacity(0.11))
                    Image(systemName: "headphones")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(XM5Palette.accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headphones.deviceName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(XM5Palette.ink)
                    Text(headphones.address.isEmpty ? "Bluetooth device not found" : headphones.address.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(XM5Palette.muted)
                }
                Spacer()
                Text(headphones.isReady ? "READY" : "OFFLINE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(headphones.isReady ? XM5Palette.success : XM5Palette.muted)
            }
        }
        .padding(11)
        .background(XM5Palette.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var settingsPreferences: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Behavior")
            VStack(spacing: 0) {
                settingsToggleRow(
                    title: "Automatic reconnection",
                    detail: "Restore Sony controls when the link becomes available",
                    symbol: "arrow.triangle.2.circlepath",
                    isOn: $settings.reconnectAutomatically
                )
                settingsDivider
                settingsToggleRow(
                    title: "Launch at login",
                    detail: "Keep headphone controls ready after startup",
                    symbol: "power",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                settingsDivider
                settingsToggleRow(
                    title: "Global shortcut",
                    detail: "⌥⌘A switches between ANC and Ambient",
                    symbol: "command",
                    isOn: $settings.globalShortcutEnabled
                )
            }
            .background(XM5Palette.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if let error = settings.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(XM5Palette.accent)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var settingsDiagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Diagnostics")
            VStack(spacing: 0) {
                diagnosticRow("Bluetooth audio", headphones.isDeviceConnected ? "Connected" : "Disconnected")
                settingsDivider
                diagnosticRow("Control link", headphones.statusText)
                settingsDivider
                diagnosticRow("Protocol", headphones.controlChannelID.map { "MDR v2 · RFCOMM \($0)" } ?? "MDR v2")
                settingsDivider
                diagnosticRow("Firmware", headphones.firmwareVersion ?? "Unknown")
                settingsDivider
                diagnosticRow(
                    "Last sync",
                    headphones.lastSyncDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
                if let error = headphones.lastErrorMessage {
                    settingsDivider
                    diagnosticRow("Last issue", error, warning: true)
                }
                settingsDivider
                HStack(spacing: 10) {
                    Button { headphones.refresh() } label: {
                        Label("Sync now", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    Button { copyDiagnostics() } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(XM5Palette.accent)
                .frame(height: 38)
                .padding(.horizontal, 10)
            }
            .background(XM5Palette.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func settingsToggleRow(
        title: String,
        detail: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(XM5Palette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(XM5Palette.ink)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(XM5Palette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(XM5Palette.accent)
        }
        .padding(.horizontal, 11)
        .frame(height: 50)
    }

    private func diagnosticRow(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(XM5Palette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(warning ? XM5Palette.accent : XM5Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(XM5Palette.line)
            .frame(height: 1)
            .padding(.leading, 11)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(headphones.diagnosticReport, forType: .string)
    }

    private func navigate(to destination: PanelScreen) {
        guard screen != destination else { return }
        if reduceMotion {
            screen = destination
        } else {
            withAnimation(.smooth(duration: 0.28)) {
                screen = destination
            }
        }
    }

    private func presetDescription(_ preset: ListeningPreset) -> String {
        switch preset {
        case .focus: "Noise cancelling for uninterrupted listening"
        case .office: "Ambient level 8 with voice focus"
        case .aware: "Maximum ambient awareness"
        }
    }

    private func isPresetSelected(_ preset: ListeningPreset) -> Bool {
        guard headphones.noiseControlMode == preset.mode else { return false }
        switch preset {
        case .focus:
            return true
        case .office:
            return headphones.ambientLevel == preset.level && headphones.focusOnVoice
        case .aware:
            return headphones.ambientLevel == preset.level && !headphones.focusOnVoice
        }
    }
}
