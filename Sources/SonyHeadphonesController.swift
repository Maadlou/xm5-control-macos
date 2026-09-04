import Combine
import Foundation
import OSLog
@preconcurrency import IOBluetooth

@MainActor
final class SonyHeadphonesController: NSObject, ObservableObject {
    enum LinkState: Equatable {
        case searching, disconnected, opening, handshaking, ready
        case failed(String)
    }

    @Published private(set) var deviceName = "WH-1000XM5"
    @Published private(set) var address = ""
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

    var isReady: Bool { linkState == .ready }
    var statusText: String {
        switch linkState {
        case .searching: "Looking for your XM5…"
        case .disconnected: "Headphones disconnected"
        case .opening: "Opening Sony control link…"
        case .handshaking: "Syncing controls…"
        case .ready: "Connected"
        case .failed(let message): message
        }
    }

    private enum Stage { case idle, protocolInfo, supportFunctions, noiseControl, ready }
    private static let sonyUUIDBytes: [UInt8] = [
        0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
        0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
    ]
    private static let asmByFunction: [(function: UInt8, type: UInt8)] = [
        (0x6D, 0x19), (0x6B, 0x17), (0x68, 0x15), (0x67, 0x22), (0x66, 0x21),
    ]
    private static let logger = Logger(subsystem: "local.xm5control", category: "SonyBluetooth")

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var refreshTimer: Timer?
    private var retryWorkItem: DispatchWorkItem?
    private var ambientWorkItem: DispatchWorkItem?
    private var commandTimeoutWorkItem: DispatchWorkItem?
    private var equalizerWorkItem: DispatchWorkItem?
    private var stream = SonyFrameStream()
    private var stage: Stage = .idle
    private var sequence: UInt8 = 0
    private var asmType: UInt8?
    private var naExtra: [UInt8] = [0, 0]
    private var reconnectAutomatically = true

    init(startAutomatically: Bool = true, simulatedReady: Bool = false) {
        super.init()
        #if DEBUG
        if simulatedReady {
            address = "80:99:E7:FB:0A:59"
            isDeviceConnected = true
            linkState = .ready
            noiseControlMode = .ambient
            ambientLevel = 12
            batteryLevel = 78
            equalizerPreset = .bassBoost
            stage = .ready
            asmType = 0x19
            return
        }
        #endif
        guard startAutomatically else {
            linkState = .disconnected
            return
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func setReconnectAutomatically(_ enabled: Bool) {
        reconnectAutomatically = enabled
        if enabled {
            refresh()
        } else {
            retryWorkItem?.cancel()
            retryWorkItem = nil
        }
    }

    func refresh() {
        refresh(shouldOpenLink: true)
        requestCurrentSettings()
    }

    func refreshEqualizer() {
        guard stage == .ready else { return }
        send([0x56, 0x00])
    }

    private func poll() {
        refresh(shouldOpenLink: reconnectAutomatically)
    }

    private func requestCurrentSettings() {
        guard stage == .ready, let asmType else { return }
        send([0x66, asmType])
        send([0x22, 0x00])
        send([0x56, 0x00])
    }

    private func refresh(shouldOpenLink: Bool) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let match = paired.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("1000XM5") }) else {
            device = nil
            address = ""
            isDeviceConnected = false
            linkState = .failed("Pair your Sony XM5 in System Settings")
            return
        }
        device = match
        deviceName = match.name ?? "Sony XM5"
        address = match.addressString ?? ""
        isDeviceConnected = match.isConnected()
        guard isDeviceConnected else {
            closeSonyLink()
            linkState = .disconnected
            return
        }
        if shouldOpenLink, channel == nil, stage == .idle { openSonyLink() }
    }

    func connect() {
        guard let device else {
            refresh()
            return
        }
        linkState = .opening
        let result = device.openConnection()
        isDeviceConnected = device.isConnected()
        if result != kIOReturnSuccess, !isDeviceConnected {
            fail("Headphones did not respond. Make sure they are powered on.")
            return
        }
        stage = .idle
        refresh()
    }

    func setNoiseControl(_ mode: NoiseControlMode) {
        sendNoiseControl(mode)
    }

    func toggleNoiseControl() {
        guard isReady else { return }
        sendNoiseControl(noiseControlMode == .anc ? .ambient : .anc)
    }

    func setEqualizerPreset(_ preset: EqualizerPreset) {
        guard stage == .ready else { return }
        equalizerWorkItem?.cancel()
        beginApplyingChange()
        send([0x58, 0x00, preset.rawValue, 0x00])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Task { @MainActor in self?.send([0x56, 0x00]) }
        }
    }

    func setCustomEqualizer(_ settings: EqualizerSettings) {
        guard stage == .ready else { return }
        customEqualizer = settings
        equalizerPreset = .manual
        equalizerWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.beginApplyingChange()
                self.send(settings.sonySetPayload)
            }
        }
        equalizerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    func applyPreset(mode: NoiseControlMode, ambientLevel level: Int, focusOnVoice focus: Bool) {
        ambientWorkItem?.cancel()
        ambientLevel = max(1, min(20, level))
        focusOnVoice = focus
        sendNoiseControl(mode)
    }

    private func sendNoiseControl(_ mode: NoiseControlMode) {
        guard stage == .ready, let asmType else { return }
        let noNoiseCancelling = asmType == 0x21 || asmType == 0x22
        let hasWindMode = asmType == 0x15
        let hasExtraAmbientFields = asmType == 0x19
        var payload: [UInt8] = [0x68, asmType, 0x01, mode == .off ? 0x00 : 0x01]
        if !noNoiseCancelling { payload.append(mode == .ambient ? 0x01 : 0x00) }
        if hasWindMode { payload.append(mode == .wind ? 0x03 : 0x02) }
        payload += [focusOnVoice ? 1 : 0, UInt8(max(1, min(20, ambientLevel)))]
        if hasExtraAmbientFields { payload += naExtra }
        beginApplyingChange()
        send(payload)
    }

    func setAmbientLevel(_ level: Int) {
        ambientLevel = max(1, min(20, level))
        ambientWorkItem?.cancel()
        guard noiseControlMode == .ambient else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.sendNoiseControl(.ambient) }
        }
        ambientWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    func setFocusOnVoice(_ enabled: Bool) {
        focusOnVoice = enabled
        if noiseControlMode == .ambient { sendNoiseControl(.ambient) }
    }

    private func beginApplyingChange() {
        isApplyingChange = true
        commandTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.isApplyingChange = false }
        }
        commandTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func openSonyLink() {
        guard let device else { return }
        stage = .protocolInfo
        linkState = .opening
        let uuid = Self.sonyUUIDBytes.withUnsafeBytes {
            IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: Self.sonyUUIDBytes.count)
        }
        guard let record = device.getServiceRecord(for: uuid) else {
            fail("Sony control service is unavailable")
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            fail("Could not resolve Sony control channel")
            return
        }
        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&openedChannel, withChannelID: channelID, delegate: self)
        channel = openedChannel
        guard result == kIOReturnSuccess else {
            fail("Sony control link failed (\(result))")
            return
        }
        Self.logger.info("Opening RFCOMM channel \(channelID)")
    }

    private func closeSonyLink() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        channel?.close()
        channel = nil
        stage = .idle
        asmType = nil
        noiseControlMode = nil
        batteryLevel = nil
        isCharging = false
        isApplyingChange = false
        equalizerPreset = nil
        equalizerWorkItem?.cancel()
        equalizerWorkItem = nil
    }

    private func beginHandshake() {
        sequence = 0
        stream = SonyFrameStream()
        stage = .protocolInfo
        linkState = .handshaking
        send([0x00, 0x00])
    }

    private func send(_ payload: [UInt8], type: UInt8 = 0x0C, sequence explicitSequence: UInt8? = nil) {
        guard let channel else { return }
        let frameSequence: UInt8
        if let explicitSequence {
            frameSequence = explicitSequence
        } else {
            frameSequence = sequence
            sequence = 1 - sequence
        }
        let data = SonyFrameCodec.encode(type: type, sequence: frameSequence, payload: payload)
        let result = data.withUnsafeBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(data.count))
        }
        if result != kIOReturnSuccess { fail("Could not send to headphones (\(result))") }
    }

    private func receive(_ data: Data) {
        for frame in stream.append(data) {
            if frame.type == 0x01 { continue }
            if frame.type == 0x0C || frame.type == 0x0E {
                send([], type: 0x01, sequence: 1 - frame.sequence)
            }
            if frame.type == 0x0C, !frame.payload.isEmpty { dispatch(frame.payload) }
        }
    }

    private func dispatch(_ payload: [UInt8]) {
        switch (payload[0], stage) {
        case (0x01, .protocolInfo):
            stage = .supportFunctions
            send([0x06, 0x00])
        case (0x07, .supportFunctions):
            let count = payload.count > 2 ? Int(payload[2]) : 0
            let functions = Set((0..<count).compactMap { index -> UInt8? in
                let position = 3 + index * 2
                return position < payload.count ? payload[position] : nil
            })
            guard let supported = Self.asmByFunction.first(where: { functions.contains($0.function) }) else {
                fail("This XM5 did not report ANC support")
                return
            }
            asmType = supported.type
            stage = .noiseControl
            send([0x66, supported.type])
        case (0x67, _), (0x69, _):
            parseNoiseControl(payload)
        case (0x23, _), (0x25, _):
            parseBattery(payload)
        case (0x57, _), (0x59, _):
            parseEqualizer(payload)
        default:
            break
        }
    }

    private func parseNoiseControl(_ payload: [UInt8]) {
        guard let asmType, (6...9).contains(payload.count), payload[1] == asmType else { return }
        let noNoiseCancelling = asmType == 0x21 || asmType == 0x22
        let hasWindMode = asmType == 0x15
        let hasExtraAmbientFields = asmType == 0x19
        let mode: NoiseControlMode
        if payload[3] == 0x00 {
            mode = .off
        } else if hasWindMode, payload.count > 5, payload[5] == 0x03 || payload[5] == 0x05 {
            mode = .wind
        } else if noNoiseCancelling {
            mode = .ambient
        } else {
            mode = payload[4] == 0x00 ? .anc : .ambient
        }
        let index = payload.count - (hasExtraAmbientFields ? 4 : 2)
        focusOnVoice = payload[index] == 0x01
        let level = Int(payload[index + 1])
        ambientLevel = (0...20).contains(level) ? level : 10
        if hasExtraAmbientFields { naExtra = [payload[index + 2], payload[index + 3]] }
        noiseControlMode = mode
        stage = .ready
        linkState = .ready
        isApplyingChange = false
        commandTimeoutWorkItem?.cancel()
        commandTimeoutWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        Self.logger.info("Sony handshake ready; mode=\(mode.rawValue, privacy: .public)")
        if batteryLevel == nil { send([0x22, 0x00]) }
        if equalizerPreset == nil { send([0x56, 0x00]) }
    }

    private func parseBattery(_ payload: [UInt8]) {
        guard payload.count >= 4, payload[1] == 0x00 else { return }
        let level = Int(payload[2])
        guard (0...100).contains(level) else { return }
        batteryLevel = level
        isCharging = payload[3] == 0x01
        Self.logger.info("Battery ready; level=\(level, privacy: .public)")
    }

    private func parseEqualizer(_ payload: [UInt8]) {
        guard payload.count >= 3, payload[1] == 0x00 else { return }
        equalizerPreset = EqualizerPreset(rawValue: payload[2])
        if let settings = EqualizerSettings(sonyPayload: payload) {
            customEqualizer = settings
        }
        isApplyingChange = false
        commandTimeoutWorkItem?.cancel()
        commandTimeoutWorkItem = nil
        if let equalizerPreset {
            Self.logger.info("Equalizer ready; preset=\(equalizerPreset.title, privacy: .public)")
        }
    }

    private func fail(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        channel?.close()
        channel = nil
        stage = .idle
        linkState = .failed(message)
        isApplyingChange = false
        retryWorkItem?.cancel()
        guard reconnectAutomatically else { return }
        let workItem = DispatchWorkItem { [weak self] in Task { @MainActor in self?.poll() } }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    @objc nonisolated
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel, status error: IOReturn) {
        Task { @MainActor in
            guard error == kIOReturnSuccess else {
                fail("Sony control link failed (\(error))")
                return
            }
            channel = rfcommChannel
            beginHandshake()
        }
    }

    @objc nonisolated
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let copied = Data(bytes: dataPointer, count: dataLength)
        Task { @MainActor in receive(copied) }
    }

    @objc nonisolated
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        Task { @MainActor in
            channel = nil
            stage = .idle
            noiseControlMode = nil
            linkState = isDeviceConnected ? .failed("Sony control link closed") : .disconnected
        }
    }
}
