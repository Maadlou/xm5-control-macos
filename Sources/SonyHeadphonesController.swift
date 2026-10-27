import Combine
import Foundation
import OSLog
@preconcurrency import IOBluetooth

@MainActor
final class SonyHeadphonesController: NSObject, ObservableObject {
    enum LinkState: Equatable {
        case searching, disconnected, opening, handshaking, ready, controlBusy
        case failed(String)
    }
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    @Published private(set) var deviceName = "Sony headphones"
    @Published private(set) var address = ""
    @Published private(set) var model: SonyHeadphoneModel?
    @Published private(set) var capabilities: SonyCapabilities?
    @Published private(set) var protocolVersion: UInt32?
    @Published private(set) var equalizerSpecification: EqualizerSpecification?
    @Published private(set) var equalizerUnavailableReason: String?
    @Published private(set) var lastKnownEqualizerLayout: EqualizerLayoutID?
    @Published private(set) var isDeviceConnected = false
    @Published private(set) var linkState: LinkState = .searching
    @Published private(set) var noiseControlMode: NoiseControlMode?
    @Published private(set) var ambientLevel = 10
    @Published private(set) var focusOnVoice = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isApplyingChange = false
    @Published private(set) var equalizerPreset: EqualizerPreset?
    @Published private(set) var customEqualizer = EqualizerSettings.flat
    @Published private(set) var pendingEqualizer: EqualizerSettings?
    @Published private(set) var pendingNoiseControl: SonyNoiseControlState?
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var controlChannelID: Int?
    @Published private(set) var retrySecondsRemaining: Int?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastErrorMessage: String?

    var isReady: Bool { linkState == .ready }
    var displayedAmbientLevel: Int { pendingNoiseControl?.ambientLevel ?? ambientLevel }
    var displayedFocusOnVoice: Bool { pendingNoiseControl?.focusOnVoice ?? focusOnVoice }
    var statusText: String {
        switch linkState {
        case .searching: "Looking for Sony headphones…"
        case .disconnected: "Headphones disconnected"
        case .opening: "Opening Sony control link…"
        case .handshaking: "Syncing controls…"
        case .ready: "Connected"
        case .controlBusy: "Control link busy"
        case .failed(let message): message
        }
    }
    var protocolDescription: String {
        protocolVersion.map { "MDR v\($0) / RFCOMM\(controlChannelID.map { " channel \($0)" } ?? "")" } ?? "Not negotiated"
    }
    var capabilityDescription: String {
        guard let capabilities else { return "Not negotiated" }
        return "Noise \(capabilities.noiseControlType.map { String(format: "0x%02X", $0) } ?? "unavailable"), battery \(capabilities.supportsBattery ? "supported" : "unavailable"), EQ \(equalizerSpecification?.id.rawValue ?? "unavailable")"
    }
    var diagnosticReport: String {
        ["XM5 Control diagnostics", "Device: \(deviceName)", "Model: \(model?.rawValue ?? "Unknown")",
         "Address: \(address.isEmpty ? "Not found" : address)",
         "Bluetooth audio: \(isDeviceConnected ? "Connected" : "Disconnected")", "Sony control: \(statusText)",
         "Protocol: \(protocolDescription)", "Capabilities: \(capabilityDescription)",
         "EQ limitation: \(equalizerUnavailableReason ?? "None")", "Firmware: \(firmwareVersion ?? "Unknown")",
         "Battery: \(batteryLevel.map { "\($0)%" } ?? "Unknown")", "Noise control: \(noiseControlMode?.title ?? "Unknown")",
         "Equalizer: \(equalizerPreset?.title ?? "Unknown")",
         "Last sync: \(lastSyncDate?.formatted(date: .numeric, time: .standard) ?? "Never")",
         "Last error: \(lastErrorMessage ?? "None")"].joined(separator: "\n")
    }

    private enum Stage { case idle, opening, protocolInfo, supportFunctions, noiseControl, ready }
    private struct PendingEQ {
        let id = UUID()
        let preset: UInt8
        let settings: EqualizerSettings?
        var readbackIssued = false
    }
    private struct PendingNoise {
        let id = UUID()
        let state: SonyNoiseControlState
        var readbackIssued = false
    }
    private static let sonyUUIDBytes: [UInt8] = [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
        0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
    ]
    private static let logger = Logger(subsystem: "local.xm5control", category: "SonyBluetooth")
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var channelSessionID: UUID?
    private(set) var sessionID = UUID()
    private var refreshTimer: Timer?
    private var stream = SonyFrameStream()
    private var stage: Stage = .idle
    private var sequence: UInt8 = 0
    private var adaptiveFields: [UInt8] = []
    private var reconnectAutomatically = true
    private var retryAttempt = 0
    private var nextRetryDate: Date?
    private var syncPollCount = 0
    private var pendingEQ: PendingEQ?
    private var pendingNoise: PendingNoise?
    private var initialEQRequested = false
    private var cancellations: [String: () -> Void] = [:]
    private var timerTokens: [String: UUID] = [:]
    private var payloadWriter: (([UInt8]) -> Void)?
    private var scheduler: Scheduler = { delay, action in
        let task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
    #if DEBUG
    private var simulatedModel: SonyHeadphoneModel?
    private var simulatedNoise: [UInt8] = []
    private var simulatedEQ: [UInt8] = []
    #endif

    init(writePayload: @escaping ([UInt8]) -> Void, schedule: @escaping Scheduler) {
        payloadWriter = writePayload
        scheduler = schedule
        super.init()
        linkState = .disconnected
    }
    init(startAutomatically: Bool = true, simulatedReady: Bool = false) {
        super.init()
        #if DEBUG
        if simulatedReady { configureSimulation(model: .whXM5); return }
        #endif
        guard startAutomatically else { linkState = .disconnected; return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    // All scheduled actions carry session and operation identities, even if cancellation races.
    private func later(_ key: String, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        cancel(key)
        let session = sessionID, token = UUID()
        timerTokens[key] = token
        cancellations[key] = scheduler(delay) { [weak self] in
            guard let self, self.sessionID == session, self.timerTokens[key] == token else { return }
            self.timerTokens.removeValue(forKey: key)
            self.cancellations.removeValue(forKey: key)
            action()
        }
    }
    private func cancel(_ key: String) {
        timerTokens.removeValue(forKey: key)
        cancellations.removeValue(forKey: key)?()
    }
    private func resetControlState() {
        sessionID = UUID()
        let work = cancellations.values
        cancellations.removeAll(); timerTokens.removeAll()
        for cancel in work { cancel() }
        let oldChannel = channel
        channel = nil; channelSessionID = nil
        oldChannel?.close()
        stage = .idle; stream = SonyFrameStream(); sequence = 0
        capabilities = nil; protocolVersion = nil; equalizerSpecification = nil; equalizerUnavailableReason = nil
        noiseControlMode = nil; ambientLevel = 10; focusOnVoice = false; adaptiveFields = []
        batteryLevel = nil; isCharging = false; firmwareVersion = nil; controlChannelID = nil
        equalizerPreset = nil; customEqualizer = .flat(for: model == .whXM6 ? .xm6TenBand : .xm5SixValue)
        pendingEQ = nil; pendingNoise = nil; pendingEqualizer = nil; pendingNoiseControl = nil
        isApplyingChange = false; initialEQRequested = false
        lastSyncDate = nil; lastErrorMessage = nil; syncPollCount = 0
        nextRetryDate = nil; retrySecondsRemaining = nil
    }
    @discardableResult
    func replaceSession(model: SonyHeadphoneModel, address: String) -> UUID {
        self.model = model
        resetControlState()
        self.address = address
        deviceName = model.displayName
        isDeviceConnected = false
        retryAttempt = 0
        linkState = .disconnected
        return sessionID
    }
    @discardableResult
    func selectDevice(from candidates: [SonyDeviceCandidate]) -> SonyDeviceCandidate? {
        guard let selected = SonyDeviceSelection.select(candidates, currentAddress: address) else {
            resetControlState(); model = nil; address = ""; deviceName = "Sony headphones"
            isDeviceConnected = false
            linkState = .failed("Pair your Sony XM5 or XM6 in System Settings")
            return nil
        }
        if selected.address != address || selected.model != model {
            replaceSession(model: selected.model, address: selected.address)
        } else if isDeviceConnected && !selected.isConnected { resetControlState() }
        deviceName = selected.name
        isDeviceConnected = selected.isConnected
        if !selected.isConnected { linkState = .disconnected }
        return selected
    }
    func beginHandshake(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        isDeviceConnected = true
        stream = SonyFrameStream(); sequence = 0; stage = .protocolInfo; linkState = .handshaking
        later("handshake", after: 8) { [weak self] in self?.fail("Sony control handshake timed out. Try reconnecting the headphones.") }
        send([0x00, 0x00])
    }
    func controlLinkClosed(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        let audioConnected = isDeviceConnected
        resetControlState()
        linkState = audioConnected ? .controlBusy : .disconnected
        if audioConnected {
            lastErrorMessage = "Sony control link closed while Bluetooth audio remained connected"
            scheduleRetry()
        }
    }
    func setReconnectAutomatically(_ enabled: Bool) {
        reconnectAutomatically = enabled
        if !enabled { cancel("retry"); nextRetryDate = nil; retrySecondsRemaining = nil }
        else if payloadWriter == nil, !isSimulation { refresh() }
    }
    private var isSimulation: Bool {
        #if DEBUG
        simulatedModel != nil
        #else
        false
        #endif
    }
    func refresh() {
        cancel("retry"); nextRetryDate = nil; retrySecondsRemaining = nil; retryAttempt = 0
        if payloadWriter == nil, !isSimulation { refresh(shouldOpenLink: true) }
        requestCurrentSettings()
    }
    func refreshEqualizer() {
        guard isReady, let specification = equalizerSpecification else { return }
        send(SonyCommandCodec.equalizerQuery(specification: specification))
    }
    private func poll() {
        retrySecondsRemaining = nextRetryDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) }
        refresh(shouldOpenLink: reconnectAutomatically)
        guard isReady else { return }
        syncPollCount += 1
        if syncPollCount >= 5 { syncPollCount = 0; requestCurrentSettings() }
    }
    private func requestCurrentSettings() {
        guard isReady, let capabilities else { return }
        if let type = capabilities.noiseControlType { send([0x66, type]) }
        if capabilities.supportsBattery { send([0x22, 0x00]) }
        if let specification = equalizerSpecification {
            if !initialEQRequested {
                initialEQRequested = true
                later("initialEQ", after: 3) { [weak self] in
                    guard let self, self.equalizerPreset == nil else { return }
                    self.disableEqualizer("The headphones did not report their EQ layout. Noise control remains available.")
                }
            }
            send(SonyCommandCodec.equalizerQuery(specification: specification))
        }
        if firmwareVersion == nil { send([0x04, 0x02]) }
    }
    private func refresh(shouldOpenLink: Bool) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let candidates = paired.compactMap { device -> SonyDeviceCandidate? in
            guard let name = device.name, let model = SonyHeadphoneModel.recognize(name: name),
                  let address = device.addressString else { return nil }
            return .init(address: address, name: name, model: model, isConnected: device.isConnected())
        }
        guard let selected = selectDevice(from: candidates) else { device = nil; return }
        device = paired.first(where: { $0.addressString == selected.address })
        guard isDeviceConnected else { return }
        if shouldOpenLink, channel == nil, stage == .idle,
           nextRetryDate.map({ $0 <= Date() }) ?? true {
            cancel("retry"); nextRetryDate = nil; retrySecondsRemaining = nil
            openSonyLink()
        }
    }
    func connect() {
        guard !isSimulation, payloadWriter == nil else { refresh(); return }
        if device == nil { refresh(shouldOpenLink: false) }
        guard let device else { return }
        if channel != nil || stage != .idle { resetControlState() }
        linkState = .opening
        let result = device.openConnection()
        isDeviceConnected = device.isConnected()
        guard result == kIOReturnSuccess || isDeviceConnected else {
            fail("Headphones did not respond. Make sure they are powered on."); return
        }
        refresh()
    }

    private var currentNoise: SonyNoiseControlState {
        pendingNoiseControl ?? .init(mode: noiseControlMode ?? .off, ambientLevel: max(1, ambientLevel),
                                     focusOnVoice: focusOnVoice, adaptiveFields: adaptiveFields)
    }
    func setNoiseControl(_ mode: NoiseControlMode) {
        var state = currentNoise; state.mode = mode; queueNoise(state)
    }
    func toggleNoiseControl() {
        setNoiseControl((pendingNoiseControl?.mode ?? noiseControlMode) == .anc ? .ambient : .anc)
    }
    func applyPreset(mode: NoiseControlMode, ambientLevel: Int, focusOnVoice: Bool) {
        var state = currentNoise; state.mode = mode; state.ambientLevel = ambientLevel; state.focusOnVoice = focusOnVoice
        queueNoise(state)
    }
    func setAmbientLevel(_ level: Int) {
        guard currentNoise.mode == .ambient, let range = capabilities?.ambientRange else { return }
        var state = currentNoise; state.ambientLevel = min(range.upperBound, max(range.lowerBound, level))
        queueNoise(state, debounce: 0.14)
    }
    func setFocusOnVoice(_ enabled: Bool) {
        guard currentNoise.mode == .ambient, capabilities?.supportsFocusOnVoice == true else { return }
        var state = currentNoise; state.focusOnVoice = enabled; queueNoise(state)
    }
    private func queueNoise(_ state: SonyNoiseControlState, debounce: Double = 0) {
        guard isReady, let capabilities,
              let payload = SonyCommandCodec.encodeNoiseControl(state, capabilities: capabilities) else { return }
        for key in ["noise.debounce", "noise.read", "noise.deadline"] { cancel(key) }
        let pending = PendingNoise(state: state)
        pendingNoise = pending; pendingNoiseControl = state; lastErrorMessage = nil; updateApplying()
        let write: @MainActor () -> Void = { [weak self] in
            guard let self, self.pendingNoise?.id == pending.id, self.send(payload) else { return }
            self.later("noise.read", after: 0.25) { [weak self] in
                guard let self, self.pendingNoise?.id == pending.id, let type = self.capabilities?.noiseControlType else { return }
                self.pendingNoise?.readbackIssued = true
                self.send([0x66, type])
            }
            self.later("noise.deadline", after: 3) { [weak self] in
                guard let self, self.pendingNoise?.id == pending.id else { return }
                self.pendingNoise = nil; self.pendingNoiseControl = nil; self.cancel("noise.read"); self.updateApplying()
                self.lastErrorMessage = "Noise-control change was not confirmed. Sync and try again."
            }
        }
        if debounce == 0 { write() } else { later("noise.debounce", after: debounce, write) }
    }
    func setEqualizerPreset(_ preset: EqualizerPreset) {
        guard isReady, let specification = equalizerSpecification,
              let payload = SonyCommandCodec.encodePreset(preset, specification: specification) else { return }
        queueEQ(payload, preset: preset.rawValue, settings: nil, debounce: 0)
    }
    func setCustomEqualizer(_ settings: EqualizerSettings) {
        guard isReady, let specification = equalizerSpecification,
              let payload = SonyCommandCodec.encodeEqualizer(settings, specification: specification) else { return }
        queueEQ(payload, preset: 0xA0, settings: settings, debounce: 0.12)
    }
    private func queueEQ(_ payload: [UInt8], preset: UInt8, settings: EqualizerSettings?, debounce: Double) {
        for key in ["eq.debounce", "eq.read", "eq.deadline"] { cancel(key) }
        let pending = PendingEQ(preset: preset, settings: settings)
        pendingEQ = pending; pendingEqualizer = settings; lastErrorMessage = nil; updateApplying()
        let write: @MainActor () -> Void = { [weak self] in
            guard let self, self.pendingEQ?.id == pending.id, self.send(payload) else { return }
            self.later("eq.read", after: 0.25) { [weak self] in
                guard let self, self.pendingEQ?.id == pending.id, let specification = self.equalizerSpecification else { return }
                self.pendingEQ?.readbackIssued = true
                self.send(SonyCommandCodec.equalizerQuery(specification: specification))
            }
            self.later("eq.deadline", after: 3) { [weak self] in
                guard let self, self.pendingEQ?.id == pending.id else { return }
                self.pendingEQ = nil; self.pendingEqualizer = nil; self.cancel("eq.read"); self.updateApplying()
                self.lastErrorMessage = "Equalizer change was not confirmed. Sync and try again."
            }
        }
        if debounce == 0 { write() } else { later("eq.debounce", after: debounce, write) }
    }
    private func updateApplying() { isApplyingChange = pendingEQ != nil || pendingNoise != nil }
    private func disableEqualizer(_ reason: String) {
        equalizerSpecification = nil; equalizerUnavailableReason = reason
        pendingEQ = nil; pendingEqualizer = nil
        for key in ["eq.debounce", "eq.read", "eq.deadline", "initialEQ"] { cancel(key) }
        updateApplying()
    }

    func handleIncomingPayload(_ payload: [UInt8], sessionID: UUID) {
        guard self.sessionID == sessionID, stage != .idle, stage != .opening else { return }
        let decodingCapabilities = capabilities ?? .resolve(model: model ?? .whXM5, functions: [])
        guard let event = SonyCommandCodec.decode(payload, capabilities: decodingCapabilities) else {
            if isReady, [UInt8(0x57), 0x59].contains(payload.first ?? 0), equalizerSpecification != nil {
                disableEqualizer("Unsupported or invalid EQ response. Noise control remains available.")
            }
            return
        }
        switch event {
        case .protocolInfo(let version, let table1, _):
            guard stage == .protocolInfo else { return }
            guard version == 2, table1 else { fail("Unsupported Sony protocol or command table."); return }
            protocolVersion = version; stage = .supportFunctions; send([0x06, 0x00])
        case .supportedFunctions(let functions):
            guard stage == .supportFunctions, let model else { return }
            let capabilities = SonyCapabilities.resolve(model: model, functions: functions)
            self.capabilities = capabilities
            equalizerSpecification = capabilities.equalizer
            if let specification = capabilities.equalizer { lastKnownEqualizerLayout = specification.id }
            else { equalizerUnavailableReason = "Equalizer is not advertised by this device." }
            guard let type = capabilities.noiseControlType else { fail("This device did not report a supported noise-control function."); return }
            stage = .noiseControl; send([0x66, type])
        case .noiseControl(let state):
            guard stage == .noiseControl || stage == .ready else { return }
            let firstSync = stage == .noiseControl
            noiseControlMode = state.mode; ambientLevel = state.ambientLevel; focusOnVoice = state.focusOnVoice
            adaptiveFields = state.adaptiveFields
            stage = .ready; linkState = .ready; lastSyncDate = Date()
            if firstSync {
                cancel("handshake"); cancel("retry"); retryAttempt = 0; nextRetryDate = nil; retrySecondsRemaining = nil
                lastErrorMessage = nil
            }
            if payload.first == 0x67, let pending = pendingNoise, pending.readbackIssued,
               state.mode == pending.state.mode,
               (state.mode != .ambient || (state.ambientLevel == pending.state.ambientLevel && state.focusOnVoice == pending.state.focusOnVoice)) {
                pendingNoise = nil; pendingNoiseControl = nil; cancel("noise.read"); cancel("noise.deadline"); updateApplying()
            }
            if firstSync { requestCurrentSettings() }
        case .battery(let level, let charging):
            batteryLevel = level; isCharging = charging; lastSyncDate = Date()
        case .equalizer(let preset, let settings):
            guard isReady, equalizerSpecification != nil else { return }
            cancel("initialEQ")
            equalizerPreset = preset
            if let settings { customEqualizer = settings }
            lastSyncDate = Date()
            if payload.first == 0x57, let pending = pendingEQ, pending.readbackIssued,
               preset.rawValue == pending.preset, pending.settings == nil || settings == pending.settings {
                pendingEQ = nil; pendingEqualizer = nil; cancel("eq.read"); cancel("eq.deadline"); updateApplying()
            }
        case .firmware(let version): firmwareVersion = version; lastSyncDate = Date()
        }
    }
    private func openSonyLink() {
        guard let device else { return }
        stage = .opening; linkState = .opening
        later("handshake", after: 8) { [weak self] in self?.fail("Sony control link opening timed out. Reconnect Bluetooth and try again.") }
        let uuid = Self.sonyUUIDBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: Self.sonyUUIDBytes.count) }
        guard let record = device.getServiceRecord(for: uuid) else { fail("Sony control service is unavailable. Reconnect Bluetooth and try again."); return }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { fail("Could not resolve Sony control channel"); return }
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        channel = opened; channelSessionID = sessionID
        guard result == kIOReturnSuccess else { fail("Sony control channel is busy (\(result))", busy: true); return }
        controlChannelID = Int(channelID)
    }
    @discardableResult
    private func send(_ payload: [UInt8], type: UInt8 = 0x0C, sequence explicitSequence: UInt8? = nil) -> Bool {
        if type == 0x0C {
            if let payloadWriter { payloadWriter(payload); return true }
            #if DEBUG
            if isSimulation { simulate(payload); return true }
            #endif
        }
        guard let channel, channelSessionID == sessionID else { return false }
        let frameSequence = explicitSequence ?? sequence
        if explicitSequence == nil { sequence = 1 - sequence }
        let data = SonyFrameCodec.encode(type: type, sequence: frameSequence, payload: payload)
        let result = data.withUnsafeBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(data.count))
        }
        if result != kIOReturnSuccess { fail("Could not send to headphones (\(result))"); return false }
        return true
    }
    private func receive(_ data: Data, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        for frame in stream.append(data) {
            if frame.type == 0x01 { continue } // An ACK never confirms a device setting.
            if frame.type == 0x0C || frame.type == 0x0E { send([], type: 0x01, sequence: 1 - frame.sequence) }
            if frame.type == 0x0C { handleIncomingPayload(frame.payload, sessionID: sessionID) }
        }
    }
    private func fail(_ message: String, busy: Bool = false) {
        Self.logger.error("\(message, privacy: .public)")
        resetControlState()
        linkState = busy ? .controlBusy : .failed(message); lastErrorMessage = message
        scheduleRetry()
    }
    private func scheduleRetry() {
        guard reconnectAutomatically, isDeviceConnected, payloadWriter == nil, !isSimulation else { return }
        let delay = ReconnectBackoff.delay(forAttempt: retryAttempt); retryAttempt += 1
        nextRetryDate = Date().addingTimeInterval(delay); retrySecondsRemaining = Int(delay)
        later("retry", after: delay) { [weak self] in
            self?.nextRetryDate = nil; self?.retrySecondsRemaining = nil
            self?.refresh(shouldOpenLink: true)
        }
    }

    @objc nonisolated
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel, status error: IOReturn) {
        Task { @MainActor in
            guard channel === rfcommChannel, channelSessionID == sessionID else { rfcommChannel.close(); return }
            guard error == kIOReturnSuccess else { fail("Sony control channel is busy (\(error))", busy: true); return }
            beginHandshake(sessionID: sessionID)
        }
    }
    @objc nonisolated
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let copied = Data(bytes: dataPointer, count: dataLength)
        Task { @MainActor in
            guard channel === rfcommChannel, channelSessionID == sessionID else { return }
            receive(copied, sessionID: sessionID)
        }
    }
    @objc nonisolated
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        Task { @MainActor in
            guard channel === rfcommChannel, channelSessionID == sessionID else { return }
            controlLinkClosed(sessionID: sessionID)
        }
    }

    #if DEBUG
    private func configureSimulation(model: SonyHeadphoneModel) {
        simulatedModel = model
        let id = replaceSession(model: model, address: "00:00:00:00:00:01")
        simulatedNoise = [0x67, 0x19, 1, 1, 1, 0, 12, 0, 0]
        let spec: EqualizerSpecification = model == .whXM6 ? .xm6 : .xm5
        simulatedEQ = [0x57, 0, model == .whXM6 ? 0x30 : 0x16, UInt8(spec.valueCount)] + Array(repeating: UInt8(spec.wireOffset), count: spec.valueCount)
        beginHandshake(sessionID: id)
    }
    private func simulate(_ payload: [UInt8]) {
        guard let command = payload.first else { return }
        let response: [UInt8]
        switch command {
        case 0: response = [1,0,0,0,0,2,0,1]
        case 6: response = [7,0,3,0x6D,0,0x20,0,0x57,0]
        case 0x66: response = simulatedNoise
        case 0x68: simulatedNoise = [0x67] + payload.dropFirst(); return
        case 0x22: response = [0x23,0,78,0]
        case 0x56: response = simulatedEQ
        case 0x58:
            if payload.count > 4 { simulatedEQ = [0x57] + payload.dropFirst() }
            else { simulatedEQ[2] = payload[2] }
            return
        case 4: response = [5,2] + Array("3.0.0".utf8)
        default: return
        }
        // Mirror asynchronous device delivery rather than reentering handshake transitions.
        later("simulation.\(command)", after: 0.01) { [weak self] in
            guard let self else { return }
            self.handleIncomingPayload(response, sessionID: self.sessionID)
        }
    }
    #endif
}
