import Foundation

enum SonyHeadphoneModel: String, Codable, Sendable {
    case whXM5, whXM6, wfXM5, legacyXM5

    var displayName: String {
        switch self {
        case .whXM5: "WH-1000XM5"
        case .whXM6: "WH-1000XM6"
        case .wfXM5: "WF-1000XM5"
        case .legacyXM5: "Sony XM5"
        }
    }

    static func recognize(name: String) -> Self? {
        let upper = name.uppercased()
        for (token, model): (String, Self) in [
            ("WH-1000XM5", .whXM5), ("WH-1000XM6", .whXM6), ("WF-1000XM5", .wfXM5),
        ] {
            if upper.range(of: "(?<![A-Z0-9])\(token)(?![A-Z0-9])", options: .regularExpression) != nil {
                return model
            }
        }
        // Keep names accepted by the original XM5 client, including prefix-free names.
        return upper.contains("1000XM5") ? .legacyXM5 : nil
    }
}

struct SonyDeviceCandidate: Equatable, Sendable {
    let address: String
    let name: String
    let model: SonyHeadphoneModel
    let isConnected: Bool
}

enum SonyDeviceSelection {
    static func select(_ candidates: [SonyDeviceCandidate], currentAddress: String?) -> SonyDeviceCandidate? {
        let connected = candidates.filter(\.isConnected)
        let eligible = connected.isEmpty ? candidates : connected
        return eligible.first(where: { $0.address == currentAddress })
            ?? eligible.min(by: { $0.address < $1.address })
    }
}

enum EqualizerLayoutID: String, Codable, Sendable {
    case xm5SixValue, xm6TenBand

    var specification: EqualizerSpecification {
        switch self {
        case .xm5SixValue: .xm5
        case .xm6TenBand: .xm6
        }
    }
}

struct EqualizerSpecification: Equatable, Sendable {
    let id: EqualizerLayoutID
    let bandLabels: [String]
    let gainRange: ClosedRange<Int>
    let wireOffset: Int
    let hasClearBass: Bool
    let presets: [EqualizerPreset]
    let responseSubtypes: Set<UInt8>

    var valueCount: Int { bandLabels.count + (hasClearBass ? 1 : 0) }

    static let xm5 = EqualizerSpecification(
        id: .xm5SixValue,
        bandLabels: ["400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"],
        gainRange: -10...10, wireOffset: 10, hasClearBass: true,
        presets: [.off, .bright, .excited, .mellow, .relaxed, .vocal, .trebleBoost, .bassBoost, .speech, .manual],
        responseSubtypes: [0x00]
    )

    static let xm6 = EqualizerSpecification(
        id: .xm6TenBand,
        bandLabels: ["31 Hz", "63 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"],
        gainRange: -6...6, wireOffset: 6, hasClearBass: false,
        presets: [.off, .heavy, .clear, .hard, .soft, .custom], responseSubtypes: [0x00, 0x04]
    )
}

struct SonyCapabilities: Equatable, Sendable {
    let noiseControlType: UInt8?
    let supportedModes: Set<NoiseControlMode>
    let ambientRange: ClosedRange<Int>?
    let supportsFocusOnVoice: Bool
    let supportsBattery: Bool
    let equalizer: EqualizerSpecification?

    static func resolve(model: SonyHeadphoneModel, functions: Set<UInt8>) -> Self {
        let variants: [(UInt8, UInt8)] = [(0x6D, 0x19), (0x6B, 0x17), (0x68, 0x15), (0x67, 0x22), (0x66, 0x21)]
        let type = variants.first(where: { functions.contains($0.0) })?.1
        var modes: Set<NoiseControlMode> = []
        if let type {
            modes = [.off, .ambient]
            if type != 0x21 && type != 0x22 { modes.insert(.anc) }
            if type == 0x15 { modes.insert(.wind) }
        }
        let hasLevels = type != nil && type != 0x21
        let legacyDefaults = model != .whXM6
        return Self(
            noiseControlType: type, supportedModes: modes,
            ambientRange: hasLevels ? 1...20 : nil, supportsFocusOnVoice: hasLevels,
            supportsBattery: legacyDefaults || functions.contains(0x20),
            equalizer: legacyDefaults ? .xm5 : (!functions.isDisjoint(with: [0x50, 0x57]) ? .xm6 : nil)
        )
    }
}
