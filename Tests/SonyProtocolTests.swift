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
        XCTAssertEqual(EqualizerPreset.off.rawValue, 0x00)
        XCTAssertEqual(EqualizerPreset.bassBoost.rawValue, 0x16)
        XCTAssertEqual(EqualizerPreset.manual.rawValue, 0xA0)
        XCTAssertFalse(EqualizerPreset.selectableCases.contains(.manual))
    }

    func testCustomEqualizerPayloadRoundTripAndClamping() {
        let settings = EqualizerSettings(clearBass: 12, bands: [-12, -4, 0, 6, 14])
        XCTAssertEqual(settings, EqualizerSettings(clearBass: 10, bands: [-10, -4, 0, 6, 10]))
        XCTAssertEqual(settings.sonySetPayload, [0x58, 0x00, 0xA0, 0x06, 20, 0, 6, 10, 16, 20])

        let response = [UInt8(0x57)] + Array(settings.sonySetPayload.dropFirst())
        XCTAssertEqual(EqualizerSettings(sonyPayload: response), settings)
    }
}
