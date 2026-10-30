import Foundation

struct SonyNoiseControlState: Equatable, Sendable {
    var mode: NoiseControlMode
    var ambientLevel: Int
    var focusOnVoice: Bool
    var adaptiveFields: [UInt8]
}

enum SonyDeviceEvent: Equatable, Sendable {
    case protocolInfo(version: UInt32, supportsTable1: Bool, supportsTable2: Bool)
    case supportedFunctions(Set<UInt8>)
    case noiseControl(SonyNoiseControlState)
    case battery(level: Int, isCharging: Bool)
    case equalizer(preset: EqualizerPreset, settings: EqualizerSettings?)
    case firmware(String)
}

// Payload codecs only. Framing, channel ownership, and session readiness stay in the controller.
enum SonyCommandCodec {
    static func decode(_ payload: [UInt8], capabilities: SonyCapabilities) -> SonyDeviceEvent? {
        guard payload.count >= 2 else { return nil }
        switch payload[0] {
        case 0x01:
            guard payload.count == 8, payload[1] == 0, payload[6] <= 1, payload[7] <= 1 else { return nil }
            let version = payload[2..<6].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return .protocolInfo(version: version, supportsTable1: payload[6] == 0, supportsTable2: payload[7] == 0)
        case 0x07:
            guard payload.count >= 3, payload[1] == 0, payload.count == 3 + Int(payload[2]) * 2 else { return nil }
            return .supportedFunctions(Set(stride(from: 3, to: payload.count, by: 2).map { payload[$0] }))
        case 0x67, 0x69:
            return decodeNoiseControl(payload, capabilities: capabilities).map(SonyDeviceEvent.noiseControl)
        case 0x23, 0x25:
            guard capabilities.supportsBattery, payload.count == 4, payload[1] == 0,
                  payload[2] <= 100, payload[3] <= 1 else { return nil }
            return .battery(level: Int(payload[2]), isCharging: payload[3] == 1)
        case 0x57, 0x59:
            return decodeEqualizer(payload, specification: capabilities.equalizer)
        case 0x05:
            guard payload[1] == 2,
                  let string = String(bytes: payload.dropFirst(2), encoding: .utf8) else { return nil }
            let firmware = string.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            return firmware.isEmpty ? nil : .firmware(firmware)
        default:
            return nil
        }
    }

    static func equalizerQuery(specification: EqualizerSpecification) -> [UInt8] { [0x56, 0x00] }

    static func encodeEqualizer(_ settings: EqualizerSettings, specification: EqualizerSpecification) -> [UInt8]? {
        guard settings.layout == specification.id, settings.isValid else { return nil }
        let values = (settings.clearBass.map { [$0] } ?? []) + settings.bands
        return [0x58, 0x00, 0xA0, UInt8(values.count)] + values.map { UInt8($0 + specification.wireOffset) }
    }

    static func encodePreset(_ preset: EqualizerPreset, specification: EqualizerSpecification) -> [UInt8]? {
        guard specification.presets.contains(where: { $0.rawValue == preset.rawValue }) else { return nil }
        return [0x58, 0x00, preset.rawValue, 0x00]
    }

    private static func decodeEqualizer(_ payload: [UInt8], specification: EqualizerSpecification?) -> SonyDeviceEvent? {
        guard let specification, payload.count >= 4,
              specification.responseSubtypes.contains(payload[1]),
              payload[1] == 0 || payload[0] == 0x59 else { return nil }
        let count = Int(payload[3])
        guard payload.count == 4 + count else { return nil }
        let preset = EqualizerPreset.resolve(rawValue: payload[2], specification: specification)
        if count == 0 { return .equalizer(preset: preset, settings: nil) }
        guard count == specification.valueCount else { return nil }
        let values = payload.dropFirst(4).map { Int($0) - specification.wireOffset }
        guard values.allSatisfy(specification.gainRange.contains) else { return nil }
        let settings = EqualizerSettings(
            layout: specification.id, clearBass: specification.hasClearBass ? values.first : nil,
            bands: specification.hasClearBass ? Array(values.dropFirst()) : values
        )
        return .equalizer(preset: preset, settings: settings)
    }

    static func encodeNoiseControl(_ state: SonyNoiseControlState, capabilities: SonyCapabilities) -> [UInt8]? {
        guard let type = capabilities.noiseControlType, capabilities.supportedModes.contains(state.mode),
              (1...20).contains(state.ambientLevel),
              !state.focusOnVoice || capabilities.supportsFocusOnVoice,
              state.adaptiveFields.count == (type == 0x19 ? 2 : 0) else { return nil }
        var payload: [UInt8] = [0x68, type, 0x01, state.mode == .off ? 0x00 : 0x01]
        if type != 0x21 && type != 0x22 { payload.append(state.mode == .ambient ? 0x01 : 0x00) }
        if type == 0x15 { payload.append(state.mode == .wind ? 0x03 : 0x02) }
        payload += [state.focusOnVoice ? 1 : 0, UInt8(state.ambientLevel)]
        payload += state.adaptiveFields
        return payload
    }

    private static func decodeNoiseControl(_ payload: [UInt8], capabilities: SonyCapabilities) -> SonyNoiseControlState? {
        guard let type = capabilities.noiseControlType, payload[1] == type else { return nil }
        let expectedLength: Int
        switch type {
        case 0x19: expectedLength = 9
        case 0x17: expectedLength = 7
        case 0x15: expectedLength = 8
        case 0x21, 0x22: expectedLength = 6
        default: return nil
        }
        // Only the evidenced 0x19 variant may omit valueChangeStatus.
        let omitsChangeStatus = type == 0x19 && payload.count == 8
        guard payload.count == expectedLength || omitsChangeStatus else { return nil }
        let effectIndex = omitsChangeStatus ? 2 : 3
        let hasANC = type != 0x21 && type != 0x22
        let voiceIndex = effectIndex + 1 + (hasANC ? 1 : 0) + (type == 0x15 ? 1 : 0)
        guard payload[effectIndex] <= 1, payload[voiceIndex] <= 1, payload[voiceIndex + 1] <= 20 else { return nil }
        if hasANC, payload[effectIndex + 1] > 1 { return nil }
        if type == 0x15, ![UInt8(2), 3, 5].contains(payload[effectIndex + 2]) { return nil }
        let mode: NoiseControlMode
        if payload[effectIndex] == 0 { mode = .off }
        else if type == 0x15, [UInt8(3), 5].contains(payload[effectIndex + 2]) { mode = .wind }
        else if !hasANC { mode = .ambient }
        else { mode = payload[effectIndex + 1] == 0 ? .anc : .ambient }
        return SonyNoiseControlState(
            mode: mode, ambientLevel: Int(payload[voiceIndex + 1]), focusOnVoice: payload[voiceIndex] == 1,
            adaptiveFields: type == 0x19 ? Array(payload.suffix(2)) : []
        )
    }
}
