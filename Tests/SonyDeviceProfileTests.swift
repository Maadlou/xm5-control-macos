import XCTest
@testable import XM5Control

final class SonyDeviceProfileTests: XCTestCase {
    func testModelRecognitionPreservesLegacyMatching() {
        XCTAssertEqual(SonyHeadphoneModel.recognize(name: "WH-1000XM5"), .whXM5)
        XCTAssertEqual(SonyHeadphoneModel.recognize(name: "wh-1000xm6"), .whXM6)
        XCTAssertEqual(SonyHeadphoneModel.recognize(name: "WF-1000XM5"), .wfXM5)
        XCTAssertEqual(SonyHeadphoneModel.recognize(name: "My 1000XM5"), .legacyXM5)
        for name in ["WH-1000XM60", "WF-1000XM6", "Sony speaker", "My XM6"] {
            XCTAssertNil(SonyHeadphoneModel.recognize(name: name), name)
        }
    }

    func testConnectedCandidateWinsOverPairedDisconnectedCandidate() {
        let xm5 = candidate("A", connected: false)
        let xm6 = candidate("B", connected: true, model: .whXM6)
        XCTAssertEqual(SonyDeviceSelection.select([xm5, xm6], currentAddress: "A"), xm6)
        XCTAssertEqual(SonyDeviceSelection.select([xm6, xm5], currentAddress: nil), xm6)
    }

    func testSelectionIsStableAndDeterministic() {
        let a = candidate("A", connected: true)
        let b = candidate("B", connected: true)
        XCTAssertEqual(SonyDeviceSelection.select([b, a], currentAddress: "B"), b)
        XCTAssertEqual(SonyDeviceSelection.select([b, a], currentAddress: nil), a)
        XCTAssertEqual(SonyDeviceSelection.select([b, a], currentAddress: "missing"), a)
        XCTAssertNil(SonyDeviceSelection.select([], currentAddress: "A"))
        let offA = candidate("A", connected: false)
        let offB = candidate("B", connected: false)
        XCTAssertEqual(SonyDeviceSelection.select([offB, offA], currentAddress: nil), offA)
        XCTAssertEqual(SonyDeviceSelection.select([offA, offB], currentAddress: "B"), offB)
    }

    func testLayoutMetadata() {
        let xm5 = EqualizerSpecification.xm5
        XCTAssertEqual(xm5.bandLabels, ["400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"])
        XCTAssertTrue(xm5.hasClearBass)
        XCTAssertEqual(xm5.gainRange, -10...10)
        XCTAssertEqual(xm5.wireOffset, 10)
        XCTAssertEqual(xm5.presets.map(\.rawValue), [0, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0xA0])
        let xm6 = EqualizerSpecification.xm6
        XCTAssertEqual(xm6.bandLabels, ["31 Hz", "63 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"])
        XCTAssertFalse(xm6.hasClearBass)
        XCTAssertEqual(xm6.gainRange, -6...6)
        XCTAssertEqual(xm6.wireOffset, 6)
        XCTAssertEqual(xm6.presets.map(\.rawValue), [0, 0x30, 0x31, 0x32, 0x33, 0xA0])
        XCTAssertEqual(xm6.responseSubtypes, [0, 4])
    }

    func testXM5OptionalDefaultsArePreservedWithoutInventingNoiseSupport() {
        for model: SonyHeadphoneModel in [.whXM5, .wfXM5, .legacyXM5] {
            let capabilities = SonyCapabilities.resolve(model: model, functions: [])
            XCTAssertNil(capabilities.noiseControlType)
            XCTAssertTrue(capabilities.supportsBattery)
            XCTAssertEqual(capabilities.equalizer?.id, .xm5SixValue)
            XCTAssertTrue(capabilities.supportedModes.isEmpty)
        }
    }

    func testXM6RequiresKnownFunctionsForOptionalFeatures() {
        let unknown = SonyCapabilities.resolve(model: .whXM6, functions: [0xFF])
        XCTAssertNil(unknown.equalizer)
        XCTAssertFalse(unknown.supportsBattery)
        XCTAssertNil(unknown.noiseControlType)
        let known = SonyCapabilities.resolve(model: .whXM6, functions: [0x20, 0x57, 0x6D])
        XCTAssertEqual(known.equalizer?.id, .xm6TenBand)
        XCTAssertTrue(known.supportsBattery)
        XCTAssertEqual(known.noiseControlType, 0x19)
        XCTAssertEqual(known.supportedModes, [.off, .anc, .ambient])
        XCTAssertEqual(known.ambientRange, 1...20)
        XCTAssertTrue(known.supportsFocusOnVoice)
        XCTAssertNotNil(SonyCapabilities.resolve(model: .whXM6, functions: [0x50]).equalizer)
    }

    func testNoiseVariantsAndPriority() {
        for (function, type): (UInt8, UInt8) in [(0x6D, 0x19), (0x6B, 0x17), (0x68, 0x15), (0x67, 0x22), (0x66, 0x21)] {
            let c = SonyCapabilities.resolve(model: .whXM5, functions: [function])
            XCTAssertEqual(c.noiseControlType, type)
            XCTAssertEqual(c.supportedModes.contains(.anc), type != 0x21 && type != 0x22)
            XCTAssertEqual(c.supportedModes.contains(.wind), type == 0x15)
            XCTAssertEqual(c.ambientRange, type == 0x21 ? nil : 1...20)
        }
        XCTAssertEqual(SonyCapabilities.resolve(model: .whXM6, functions: [0x68, 0x6B, 0x6D]).noiseControlType, 0x19)
    }

    private func candidate(_ address: String, connected: Bool, model: SonyHeadphoneModel = .whXM5) -> SonyDeviceCandidate {
        SonyDeviceCandidate(address: address, name: address, model: model, isConnected: connected)
    }
}
