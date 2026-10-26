import Foundation

enum ReconnectBackoff {
    private static let delays: [TimeInterval] = [2, 4, 8, 15, 30]

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        delays[min(max(0, attempt), delays.count - 1)]
    }
}

enum NoiseControlMode: String, CaseIterable, Identifiable, Sendable {
    case off, anc, ambient, wind

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .anc: "Noise Cancelling"
        case .ambient: "Ambient"
        case .wind: "Wind"
        }
    }

    var compactTitle: String {
        switch self {
        case .off: "Off"
        case .anc: "ANC"
        case .ambient: "Ambient"
        case .wind: "Wind"
        }
    }

    var symbol: String {
        switch self {
        case .off: "speaker.slash"
        case .anc: "waveform"
        case .ambient: "ear"
        case .wind: "wind"
        }
    }
}

struct EqualizerPreset: Equatable, Identifiable, Sendable {
    let rawValue: UInt8
    let title: String
    var id: UInt8 { rawValue }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }

    static let off = Self(rawValue: 0x00, title: "Off")
    static let bright = Self(rawValue: 0x10, title: "Bright")
    static let excited = Self(rawValue: 0x11, title: "Excited")
    static let mellow = Self(rawValue: 0x12, title: "Mellow")
    static let relaxed = Self(rawValue: 0x13, title: "Relaxed")
    static let vocal = Self(rawValue: 0x14, title: "Vocal")
    static let trebleBoost = Self(rawValue: 0x15, title: "Treble Boost")
    static let bassBoost = Self(rawValue: 0x16, title: "Bass Boost")
    static let speech = Self(rawValue: 0x17, title: "Speech")
    static let heavy = Self(rawValue: 0x30, title: "Heavy")
    static let clear = Self(rawValue: 0x31, title: "Clear")
    static let hard = Self(rawValue: 0x32, title: "Hard")
    static let soft = Self(rawValue: 0x33, title: "Soft")
    static let manual = Self(rawValue: 0xA0, title: "Manual")
    static let custom = Self(rawValue: 0xA0, title: "Custom")

    // Legacy XM5 menu; model-aware menus are introduced in Task 6.
    static let selectableCases: [Self] = [.off, .bright, .excited, .mellow, .relaxed, .vocal, .trebleBoost, .bassBoost, .speech]

    static func resolve(rawValue: UInt8, specification: EqualizerSpecification) -> Self {
        specification.presets.first(where: { $0.rawValue == rawValue })
            ?? Self(rawValue: rawValue, title: String(format: "Unknown (0x%02X)", rawValue))
    }
}

struct EqualizerSettings: Codable, Equatable, Sendable {
    static let bandLabels = EqualizerSpecification.xm5.bandLabels
    static let flat = flat(for: .xm5SixValue)

    let layout: EqualizerLayoutID
    var clearBass: Int?
    var bands: [Int]

    init(layout: EqualizerLayoutID, clearBass: Int?, bands: [Int]) {
        let specification = layout.specification
        self.layout = layout
        self.clearBass = specification.hasClearBass ? Self.clamp(clearBass ?? 0, to: specification.gainRange) : nil
        self.bands = specification.bandLabels.indices.map { index in
            Self.clamp(index < bands.count ? bands[index] : 0, to: specification.gainRange)
        }
    }

    init(clearBass: Int, bands: [Int]) {
        self.init(layout: .xm5SixValue, clearBass: clearBass, bands: bands)
    }

    static func flat(for layout: EqualizerLayoutID) -> Self {
        Self(layout: layout, clearBass: nil, bands: [])
    }

    subscript(band index: Int) -> Int {
        get { bands[index] }
        set { bands[index] = Self.clamp(newValue, to: layout.specification.gainRange) }
    }

    var isValid: Bool {
        let specification = layout.specification
        return bands.count == specification.bandLabels.count
            && bands.allSatisfy(specification.gainRange.contains)
            && (specification.hasClearBass
                ? clearBass.map(specification.gainRange.contains) == true
                : clearBass == nil)
    }

    private enum CodingKeys: String, CodingKey { case layout, clearBass, bands }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decode(EqualizerLayoutID.self, forKey: .layout)
        clearBass = try container.decodeIfPresent(Int.self, forKey: .clearBass)
        bands = try container.decode([Int].self, forKey: .bands)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid EQ layout or gains"))
        }
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }
}

struct SonyFrame: Equatable, Sendable {
    let type: UInt8
    let sequence: UInt8
    let payload: [UInt8]
}

enum SonyFrameCodec {
    static let header: UInt8 = 0x3E
    static let trailer: UInt8 = 0x3C
    static let escape: UInt8 = 0x3D
    private static let escapeMask: UInt8 = 0xEF

    static func encode(type: UInt8, sequence: UInt8, payload: [UInt8]) -> Data {
        let count = UInt32(payload.count)
        var body: [UInt8] = [
            type, sequence,
            UInt8((count >> 24) & 0xFF), UInt8((count >> 16) & 0xFF),
            UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF),
        ]
        body.append(contentsOf: payload)
        body.append(body.reduce(0, &+))

        var encoded = [header]
        for byte in body {
            if byte == header || byte == trailer || byte == escape {
                encoded += [escape, byte & escapeMask]
            } else {
                encoded.append(byte)
            }
        }
        encoded.append(trailer)
        return Data(encoded)
    }

    static func decode(_ data: Data) -> SonyFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 9, bytes.first == header, bytes.last == trailer else { return nil }
        var raw: [UInt8] = []
        var index = 1
        while index < bytes.count - 1 {
            var byte = bytes[index]
            if byte == escape {
                index += 1
                guard index < bytes.count - 1 else { return nil }
                byte = bytes[index] | ~escapeMask
            }
            raw.append(byte)
            index += 1
        }
        guard raw.count >= 7, raw.last == raw.dropLast().reduce(0, &+) else { return nil }
        let length = Int(UInt32(raw[2]) << 24 | UInt32(raw[3]) << 16 | UInt32(raw[4]) << 8 | UInt32(raw[5]))
        guard length == raw.count - 7 else { return nil }
        return SonyFrame(type: raw[0], sequence: raw[1], payload: Array(raw[6..<(6 + length)]))
    }
}

struct SonyFrameStream: Sendable {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [SonyFrame] {
        buffer.append(data)
        var frames: [SonyFrame] = []
        while let start = buffer.firstIndex(of: SonyFrameCodec.header) {
            if start > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start) }
            guard let end = buffer.dropFirst().firstIndex(of: SonyFrameCodec.trailer) else { break }
            let packet = Data(buffer[buffer.startIndex...end])
            buffer.removeSubrange(buffer.startIndex...end)
            if let frame = SonyFrameCodec.decode(packet) { frames.append(frame) }
        }
        return frames
    }
}
