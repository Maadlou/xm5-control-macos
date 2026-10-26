import XCTest
@testable import XM5Control

final class SonyCommandCodecTests: XCTestCase {
    private let xm5 = SonyCapabilities.resolve(model: .whXM5, functions: [0x6D])
    private let xm6 = SonyCapabilities.resolve(model: .whXM6, functions: [0x20, 0x57, 0x6D])

    func testEQWireFormatsAndClampingStaySeparate() {
        let old = EqualizerSettings(clearBass: 10, bands: [-10, -4, 0, 6, 10])
        XCTAssertEqual(SonyCommandCodec.encodeEqualizer(old, specification: .xm5), [0x58, 0, 0xA0, 6, 20, 0, 6, 10, 16, 20])
        let flat = EqualizerSettings.flat(for: .xm6TenBand)
        XCTAssertEqual(flat.bands.count, 10)
        XCTAssertNil(flat.clearBass)
        XCTAssertEqual(SonyCommandCodec.encodeEqualizer(flat, specification: .xm6), [0x58, 0, 0xA0, 10] + Array(repeating: 6, count: 10))
        XCTAssertNil(SonyCommandCodec.encodeEqualizer(old, specification: .xm6))
        XCTAssertNil(SonyCommandCodec.encodeEqualizer(flat, specification: .xm5))
        var limited = EqualizerSettings(layout: .xm6TenBand, clearBass: 10, bands: [-20, 20])
        XCTAssertNil(limited.clearBass)
        XCTAssertEqual(limited.bands, [-6, 6, 0, 0, 0, 0, 0, 0, 0, 0])
        limited[band: 0] = 20
        XCTAssertEqual(limited[band: 0], 6)
        XCTAssertEqual(SonyCommandCodec.equalizerQuery(specification: .xm5), [0x56, 0])
        XCTAssertEqual(SonyCommandCodec.equalizerQuery(specification: .xm6), [0x56, 0])
    }

    func testFactoryAndCustomCurvesAndNotificationVariants() {
        for spec in [EqualizerSpecification.xm5, .xm6] {
            let capabilities = spec.id == .xm5SixValue ? xm5 : xm6
            let values = Array(repeating: UInt8(spec.wireOffset), count: spec.valueCount)
            let preset = spec.presets[1]
            for (command, subtype): (UInt8, UInt8) in [(0x57, 0), (0x59, 0)] + (spec.id == .xm6TenBand ? [(0x59, 4)] : []) {
                let packet = [command, subtype, preset.rawValue, UInt8(values.count)] + values
                XCTAssertEqual(SonyCommandCodec.decode(packet, capabilities: capabilities), .equalizer(preset: preset, settings: .flat(for: spec.id)))
            }
        }
        XCTAssertEqual(SonyCommandCodec.decode([0x57, 0, 0xFE, 0], capabilities: xm6),
                       .equalizer(preset: EqualizerPreset.resolve(rawValue: 0xFE, specification: .xm6), settings: nil))
        XCTAssertEqual(EqualizerPreset.resolve(rawValue: 0xFE, specification: .xm6).title, "Unknown (0xFE)")
        XCTAssertEqual(EqualizerPreset.resolve(rawValue: 0xA0, specification: .xm6).title, "Custom")
        XCTAssertEqual(SonyCommandCodec.encodePreset(.heavy, specification: .xm6), [0x58, 0, 0x30, 0])
        XCTAssertNil(SonyCommandCodec.encodePreset(.bright, specification: .xm6))
        XCTAssertNil(SonyCommandCodec.encodePreset(.heavy, specification: .xm5))
        XCTAssertNil(SonyCommandCodec.encodePreset(EqualizerPreset.resolve(rawValue: 0xA1, specification: .xm6), specification: .xm6))
    }

    func testInvalidEQNeverBecomesAValidCurve() {
        let valid: [UInt8] = [0x57, 0, 0xA0, 10] + Array(repeating: 6, count: 10)
        for packet in [[], [0x57], [0x57, 0], [0x57, 0, 0xA0], Array(valid.dropLast()), valid + [6],
                       [0x57, 4, 0xA0, 0], [0x59, 3, 0xA0, 0],
                       [0x57, 0, 0xA0, 10] + Array(repeating: 13, count: 10)] {
            XCTAssertNil(SonyCommandCodec.decode(packet, capabilities: xm6), "\(packet)")
        }
        XCTAssertNil(SonyCommandCodec.decode(valid, capabilities: xm5))
        XCTAssertNil(SonyCommandCodec.decode([0x57, 0, 0xA0, 6, 10, 10, 10, 10, 10, 10], capabilities: xm6))
        XCTAssertNil(SonyCommandCodec.decode(valid, capabilities: .resolve(model: .whXM6, functions: [0x6D])))
        var invalid = EqualizerSettings.flat(for: .xm6TenBand)
        invalid.bands = [0]
        XCTAssertNil(SonyCommandCodec.encodeEqualizer(invalid, specification: .xm6))
    }

    func testNoiseVariantsRoundTripAndPreserveAdaptiveFields() throws {
        for (function, type): (UInt8, UInt8) in [(0x6D, 0x19), (0x6B, 0x17), (0x68, 0x15), (0x67, 0x22), (0x66, 0x21)] {
            let c = SonyCapabilities.resolve(model: .whXM5, functions: [function])
            let state = SonyNoiseControlState(mode: .ambient, ambientLevel: 8, focusOnVoice: type != 0x21,
                                             adaptiveFields: type == 0x19 ? [1, 2] : [])
            let encoded = try XCTUnwrap(SonyCommandCodec.encodeNoiseControl(state, capabilities: c))
            XCTAssertEqual(encoded[0...1], [0x68, type])
            for command: UInt8 in [0x67, 0x69] {
                var response = encoded
                response[0] = command
                XCTAssertEqual(SonyCommandCodec.decode(response, capabilities: c), .noiseControl(state))
                if type == 0x19 {
                    response.remove(at: 2)
                    XCTAssertEqual(SonyCommandCodec.decode(response, capabilities: c), .noiseControl(state))
                }
            }
        }
        for mode in [NoiseControlMode.off, .anc, .ambient] {
            let state = SonyNoiseControlState(mode: mode, ambientLevel: 20, focusOnVoice: false, adaptiveFields: [0, 0])
            let packet = try XCTUnwrap(SonyCommandCodec.encodeNoiseControl(state, capabilities: xm6))
            XCTAssertEqual(SonyCommandCodec.decode([0x67] + packet.dropFirst(), capabilities: xm6), .noiseControl(state))
        }
        let windCapabilities = SonyCapabilities.resolve(model: .whXM5, functions: [0x68])
        let wind = SonyNoiseControlState(mode: .wind, ambientLevel: 10, focusOnVoice: false, adaptiveFields: [])
        let packet = try XCTUnwrap(SonyCommandCodec.encodeNoiseControl(wind, capabilities: windCapabilities))
        XCTAssertEqual(packet, [0x68, 0x15, 1, 1, 0, 3, 0, 10])
        XCTAssertEqual(SonyCommandCodec.decode([0x69] + packet.dropFirst(), capabilities: windCapabilities), .noiseControl(wind))
        XCTAssertNil(SonyCommandCodec.encodeNoiseControl(wind, capabilities: xm6))
    }

    func testMalformedNoiseAndUnsupportedModeAreRejected() {
        for packet: [UInt8] in [[0x67, 0x19], [0x67, 0x19, 1, 1, 1, 1, 8],
                               [0x67, 0x19, 1, 1, 1, 1, 21, 0, 0],
                               [0x67, 0x19, 1, 1, 1, 2, 8, 0, 0],
                               [0x67, 0x17, 1, 1, 1, 1, 8],
                               [0x67, 0x19, 1, 1, 1, 1, 8, 0, 0, 0]] {
            XCTAssertNil(SonyCommandCodec.decode(packet, capabilities: xm6))
        }
        let noANC = SonyCapabilities.resolve(model: .whXM5, functions: [0x67])
        XCTAssertNil(SonyCommandCodec.encodeNoiseControl(.init(mode: .anc, ambientLevel: 10, focusOnVoice: false, adaptiveFields: []), capabilities: noANC))
    }

    func testHandshakeAndSupportedFunctionValidation() {
        XCTAssertEqual(SonyCommandCodec.decode([1, 0, 0, 0, 0, 2, 0, 1], capabilities: xm6),
                       .protocolInfo(version: 2, supportsTable1: true, supportsTable2: false))
        XCTAssertEqual(SonyCommandCodec.decode([1, 0, 0, 0, 0, 3, 0, 0], capabilities: xm6),
                       .protocolInfo(version: 3, supportsTable1: true, supportsTable2: true))
        XCTAssertEqual(SonyCommandCodec.decode([7, 0, 2, 0x6D, 1, 0x57, 2], capabilities: xm6), .supportedFunctions([0x6D, 0x57]))
        XCTAssertEqual(SonyCommandCodec.decode([7, 0, 0], capabilities: xm6), .supportedFunctions([]))
        for packet: [UInt8] in [[1, 0], [1, 0, 0, 0, 0, 2, 0], [1, 0, 0, 0, 0, 2, 2, 0],
                               [7, 0, 2, 0x6D, 1], [7, 0, 1, 0x6D], [7, 1, 0], [7, 0, 0, 0]] {
            XCTAssertNil(SonyCommandCodec.decode(packet, capabilities: xm6))
        }
    }

    func testBatteryChargingFirmwareAndPartialCapabilities() {
        XCTAssertEqual(SonyCommandCodec.decode([0x23, 0, 78, 1], capabilities: xm6), .battery(level: 78, isCharging: true))
        XCTAssertEqual(SonyCommandCodec.decode([0x25, 0, 0, 0], capabilities: xm6), .battery(level: 0, isCharging: false))
        XCTAssertEqual(SonyCommandCodec.decode([0x05, 0x02] + Array("3.0.0\0\n".utf8), capabilities: xm6), .firmware("3.0.0"))
        for packet: [UInt8] in [[0x23, 0, 101, 0], [0x23, 0, 50], [0x23, 0, 50, 2],
                               [0x25, 1, 50, 0], [5, 2], [5, 2, 0], [5, 2, 0xFF]] {
            XCTAssertNil(SonyCommandCodec.decode(packet, capabilities: xm6))
        }
        let partial = SonyCapabilities.resolve(model: .whXM6, functions: [0x6D, 0x20])
        XCTAssertNotNil(SonyCommandCodec.decode([0x23, 0, 78, 0], capabilities: partial))
        XCTAssertNotNil(SonyCommandCodec.decode([0x67, 0x19, 1, 1, 1, 0, 8, 0, 0], capabilities: partial))
        XCTAssertNil(SonyCommandCodec.decode([0x23, 0, 78, 0], capabilities: .resolve(model: .whXM6, functions: [])))
    }

    func testSettingsCodableRejectsMalformedValuesRatherThanNormalizing() throws {
        for layout in [EqualizerLayoutID.xm5SixValue, .xm6TenBand] {
            let settings = EqualizerSettings.flat(for: layout)
            XCTAssertEqual(try JSONDecoder().decode(EqualizerSettings.self, from: JSONEncoder().encode(settings)), settings)
        }
        for json in [#"{"layout":"xm6TenBand","bands":[0]}"#,
                     #"{"layout":"xm5SixValue","clearBass":30,"bands":[0,0,0,0,0]}"#,
                     #"{"layout":"xm6TenBand","clearBass":0,"bands":[0,0,0,0,0,0,0,0,0,0]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(EqualizerSettings.self, from: Data(json.utf8)))
        }
    }
}
