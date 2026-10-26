import Foundation
import XCTest
@testable import XM5Control

final class SonyProtocolTests: XCTestCase {
    func testReconnectBackoffCapsAtThirtySeconds() {
        XCTAssertEqual((0...6).map(ReconnectBackoff.delay), [2, 4, 8, 15, 30, 30, 30])
    }

    func testFrameRoundTripIncludingEscapedBytes() {
        let payload: [UInt8] = [0x68, 0x3C, 0x3D, 0x3E, 0x01]
        let encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 1, payload: payload)
        XCTAssertEqual(SonyFrameCodec.decode(encoded), SonyFrame(type: 0x0C, sequence: 1, payload: payload))
    }

    func testStreamReassemblesSplitFrames() {
        let encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 0, payload: [0x00, 0x00])
        var stream = SonyFrameStream()
        XCTAssertTrue(stream.append(encoded.prefix(3)).isEmpty)
        XCTAssertEqual(stream.append(encoded.dropFirst(3)).first?.payload, [0x00, 0x00])
    }

    func testRejectsBadChecksum() {
        var encoded = SonyFrameCodec.encode(type: 0x0C, sequence: 0, payload: [0x06, 0x00])
        encoded[encoded.count - 2] ^= 0x01
        XCTAssertNil(SonyFrameCodec.decode(encoded))
    }

    func testEqualizerPresetProtocolValues() {
        let presets: [EqualizerPreset] = [.off, .bright, .excited, .mellow, .relaxed, .vocal,
                                         .trebleBoost, .bassBoost, .speech, .manual]
        XCTAssertEqual(presets.map(\.rawValue), [0x00, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0xA0])
        XCTAssertEqual(EqualizerPreset.selectableCases, Array(presets.dropLast()))
        XCTAssertFalse(EqualizerPreset.selectableCases.contains(.manual))
    }

    func testCustomEqualizerPayloadRoundTripAndClamping() throws {
        let settings = EqualizerSettings(clearBass: 12, bands: [-12, -4, 0, 6, 14])
        XCTAssertEqual(settings, EqualizerSettings(clearBass: 10, bands: [-10, -4, 0, 6, 10]))
        let encoded = try XCTUnwrap(SonyCommandCodec.encodeEqualizer(settings, specification: .xm5))
        XCTAssertEqual(encoded, [0x58, 0x00, 0xA0, 0x06, 20, 0, 6, 10, 16, 20])

        let response = [UInt8(0x57)] + Array(encoded.dropFirst())
        XCTAssertEqual(SonyCommandCodec.decode(response, capabilities: .resolve(model: .whXM5, functions: [])),
                       .equalizer(preset: .manual, settings: settings))
    }
}
