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

enum EqualizerPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0x00
    case bright = 0x10
    case excited = 0x11
    case mellow = 0x12
    case relaxed = 0x13
    case vocal = 0x14
    case trebleBoost = 0x15
    case bassBoost = 0x16
    case speech = 0x17
    case manual = 0xA0

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .bright: "Bright"
        case .excited: "Excited"
        case .mellow: "Mellow"
        case .relaxed: "Relaxed"
        case .vocal: "Vocal"
        case .trebleBoost: "Treble Boost"
        case .bassBoost: "Bass Boost"
        case .speech: "Speech"
        case .manual: "Manual"
        }
    }

    static var selectableCases: [Self] { allCases.filter { $0 != .manual } }
}

struct EqualizerSettings: Codable, Equatable, Sendable {
    static let bandLabels = ["400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"]
    static let flat = EqualizerSettings(clearBass: 0, bands: [0, 0, 0, 0, 0])

    var clearBass: Int
    var bands: [Int]

    init(clearBass: Int, bands: [Int]) {
        self.clearBass = Self.clamp(clearBass)
        self.bands = (0..<5).map { index in
            Self.clamp(index < bands.count ? bands[index] : 0)
        }
    }

    subscript(band index: Int) -> Int {
        get { bands[index] }
        set { bands[index] = Self.clamp(newValue) }
    }

    var sonySetPayload: [UInt8] {
        [0x58, 0x00, EqualizerPreset.manual.rawValue, 0x06]
            + ([clearBass] + bands).map { UInt8(Self.clamp($0) + 10) }
    }

    init?(sonyPayload: [UInt8]) {
        guard sonyPayload.count >= 10,
              sonyPayload[1] == 0x00,
              sonyPayload[2] == EqualizerPreset.manual.rawValue,
              sonyPayload[3] >= 0x06 else { return nil }
        self.init(
            clearBass: Int(sonyPayload[4]) - 10,
            bands: sonyPayload[5..<10].map { Int($0) - 10 }
        )
    }

    private static func clamp(_ value: Int) -> Int { max(-10, min(10, value)) }
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
