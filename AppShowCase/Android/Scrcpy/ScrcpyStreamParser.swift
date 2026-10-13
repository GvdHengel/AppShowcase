import Foundation

/// Eén videopakket van de scrcpy-server.
struct ScrcpyPacket: Equatable {
    /// Config-pakket: bevat SPS/PPS (codec-parameters), geen beeld.
    let isConfig: Bool
    let isKeyFrame: Bool
    /// Presentatietijd in microseconden (0 voor config-pakketten).
    let pts: UInt64
    /// H.264 in Annex B-formaat (NAL-units met start codes).
    let payload: [UInt8]
}

/// Incrementele parser voor de videostream van scrcpy 3.x (forward-tunnel).
///
/// Volgorde op de socket:
/// 1. 1 dummy-byte (alleen bij forward-tunnel)
/// 2. 64 bytes toestelnaam (UTF-8, met nullen aangevuld)
/// 3. 12 bytes codec-meta: codec-id, breedte, hoogte (u32 big-endian)
/// 4. per pakket 12 bytes header + payload:
///    - u64 big-endian: bit 63 = config, bit 62 = keyframe, rest = PTS (µs)
///    - u32 big-endian: lengte payload
///
/// Let op: scrcpy 4.x gebruikt een ander formaat (sessie-pakketten). Zie CLAUDE.md.
struct ScrcpyStreamParser {
    static let codecH264: UInt32 = 0x6832_3634 // "h264"
    static let deviceNameLength = 64
    static let maxPacketSize = 1 << 26 // 64 MB; alles daarboven is een kapotte stream

    enum Event: Equatable {
        case dummyByte
        case deviceName(String)
        case codecMeta(codecID: UInt32, width: UInt32, height: UInt32)
        case packet(ScrcpyPacket)
    }

    enum ParseError: Error, Equatable {
        case packetTooLarge(Int)
    }

    private enum Stage {
        case dummyByte
        case deviceName
        case codecMeta
        case frameHeader
        case frameBody(isConfig: Bool, isKeyFrame: Bool, pts: UInt64, size: Int)
    }

    private static let configFlag: UInt64 = 1 << 63
    private static let keyFrameFlag: UInt64 = 1 << 62
    private static let ptsMask: UInt64 = keyFrameFlag - 1

    private let expectDeviceMeta: Bool
    private let expectCodecMeta: Bool
    private var stage: Stage
    private var buffer: [UInt8] = []
    private var readIndex = 0

    init(expectDummyByte: Bool = true, expectDeviceMeta: Bool = true, expectCodecMeta: Bool = true) {
        self.expectDeviceMeta = expectDeviceMeta
        self.expectCodecMeta = expectCodecMeta
        if expectDummyByte {
            stage = .dummyByte
        } else if expectDeviceMeta {
            stage = .deviceName
        } else if expectCodecMeta {
            stage = .codecMeta
        } else {
            stage = .frameHeader
        }
    }

    /// Voeg ontvangen bytes toe en krijg alle complete gebeurtenissen terug.
    mutating func feed(_ data: Data) throws -> [Event] {
        buffer.append(contentsOf: data)
        var events: [Event] = []
        while let event = try nextEvent() {
            events.append(event)
        }
        compact()
        return events
    }

    // MARK: - Intern

    private var available: Int { buffer.count - readIndex }

    private mutating func nextEvent() throws -> Event? {
        switch stage {
        case .dummyByte:
            guard available >= 1 else { return nil }
            readIndex += 1
            stage = expectDeviceMeta ? .deviceName : (expectCodecMeta ? .codecMeta : .frameHeader)
            return .dummyByte

        case .deviceName:
            let length = Self.deviceNameLength
            guard available >= length else { return nil }
            let nameBytes = buffer[readIndex..<(readIndex + length)].prefix { $0 != 0 }
            readIndex += length
            stage = expectCodecMeta ? .codecMeta : .frameHeader
            return .deviceName(String(decoding: nameBytes, as: UTF8.self))

        case .codecMeta:
            guard available >= 12 else { return nil }
            let codec = readUInt32(at: readIndex)
            let width = readUInt32(at: readIndex + 4)
            let height = readUInt32(at: readIndex + 8)
            readIndex += 12
            stage = .frameHeader
            return .codecMeta(codecID: codec, width: width, height: height)

        case .frameHeader:
            guard available >= 12 else { return nil }
            let ptsAndFlags = readUInt64(at: readIndex)
            let size = Int(readUInt32(at: readIndex + 8))
            guard size <= Self.maxPacketSize else { throw ParseError.packetTooLarge(size) }
            readIndex += 12
            let isConfig = ptsAndFlags & Self.configFlag != 0
            stage = .frameBody(
                isConfig: isConfig,
                isKeyFrame: ptsAndFlags & Self.keyFrameFlag != 0,
                pts: isConfig ? 0 : ptsAndFlags & Self.ptsMask,
                size: size
            )
            return try nextEvent()

        case let .frameBody(isConfig, isKeyFrame, pts, size):
            guard available >= size else { return nil }
            let payload = Array(buffer[readIndex..<(readIndex + size)])
            readIndex += size
            stage = .frameHeader
            return .packet(ScrcpyPacket(isConfig: isConfig, isKeyFrame: isKeyFrame, pts: pts, payload: payload))
        }
    }

    private func readUInt32(at index: Int) -> UInt32 {
        buffer[index..<(index + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func readUInt64(at index: Int) -> UInt64 {
        buffer[index..<(index + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    /// Verwijdert verwerkte bytes zonder bij elk pakket de hele buffer te kopiëren.
    private mutating func compact() {
        if readIndex == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            readIndex = 0
        } else if readIndex > 1 << 20 {
            buffer.removeFirst(readIndex)
            readIndex = 0
        }
    }
}
