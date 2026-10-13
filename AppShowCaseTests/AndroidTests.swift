import Foundation
import Testing
@testable import AppShowCase

// MARK: - scrcpy-protocol

struct ScrcpyStreamParserTests {

    private static func be32(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt32($0)) }
    }

    private static func be64(_ value: UInt64) -> [UInt8] {
        [56, 48, 40, 32, 24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt64($0)) }
    }

    private static func header(config: Bool = false, key: Bool = false, pts: UInt64 = 0, size: Int) -> [UInt8] {
        var flags = pts
        if config { flags |= 1 << 63 }
        if key { flags |= 1 << 62 }
        return be64(flags) + be32(UInt32(size))
    }

    static let sps: [UInt8] = [0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1F]
    static let pps: [UInt8] = [0, 0, 0, 1, 0x68, 0xCE, 0x3C, 0x80]
    static let idr: [UInt8] = [0, 0, 0, 1, 0x65, 0x88, 0x84, 0x00, 0x33]

    /// Een complete stream zoals scrcpy 3.x hem stuurt.
    static var stream: [UInt8] {
        var name = Array("Pixel 2".utf8)
        name += [UInt8](repeating: 0, count: 64 - name.count)
        let config = sps + pps
        return [0] + name
            + be32(ScrcpyStreamParser.codecH264) + be32(1080) + be32(1920)
            + header(config: true, size: config.count) + config
            + header(key: true, pts: 16_666, size: idr.count) + idr
    }

    static let expected: [ScrcpyStreamParser.Event] = [
        .dummyByte,
        .deviceName("Pixel 2"),
        .codecMeta(codecID: ScrcpyStreamParser.codecH264, width: 1080, height: 1920),
        .packet(ScrcpyPacket(isConfig: true, isKeyFrame: false, pts: 0, payload: sps + pps)),
        .packet(ScrcpyPacket(isConfig: false, isKeyFrame: true, pts: 16_666, payload: idr)),
    ]

    @Test func parsesCompleteStreamInOneGo() throws {
        var parser = ScrcpyStreamParser()
        #expect(try parser.feed(Data(Self.stream)) == Self.expected)
    }

    @Test func parsesStreamByteByByte() throws {
        var parser = ScrcpyStreamParser()
        var events: [ScrcpyStreamParser.Event] = []
        for byte in Self.stream {
            events += try parser.feed(Data([byte]))
        }
        #expect(events == Self.expected)
    }

    @Test func parsesStreamInRandomChunks() throws {
        var parser = ScrcpyStreamParser()
        var events: [ScrcpyStreamParser.Event] = []
        var remaining = Self.stream[...]
        var generator = SystemRandomNumberGenerator()
        while !remaining.isEmpty {
            let size = min(remaining.count, Int.random(in: 1...17, using: &generator))
            events += try parser.feed(Data(remaining.prefix(size)))
            remaining = remaining.dropFirst(size)
        }
        #expect(events == Self.expected)
    }

    @Test func rejectsAbsurdPacketSize() {
        var parser = ScrcpyStreamParser(expectDummyByte: false, expectDeviceMeta: false, expectCodecMeta: false)
        let bad = Self.header(size: Int(UInt32.max))
        #expect(throws: ScrcpyStreamParser.ParseError.self) {
            _ = try parser.feed(Data(bad))
        }
    }
}

// MARK: - H.264 Annex B

struct AnnexBTests {

    @Test func splitsThreeAndFourByteStartCodes() {
        let data: [UInt8] = [0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB, 0, 0, 0, 1, 0x65, 0xCC, 0xDD]
        let units = AnnexB.split(data).map { Array($0) }
        #expect(units == [[0x67, 0xAA], [0x68, 0xBB], [0x65, 0xCC, 0xDD]])
        #expect(AnnexB.split(data).map { AnnexB.nalType($0) } == [7, 8, 5])
    }

    @Test func keepsMultipleSlicesOfOneFrame() {
        // Twee slices van één frame (zoals veel Qualcomm-encoders doen) moeten samen blijven.
        let data: [UInt8] = [0, 0, 0, 1, 0x65, 0x11, 0, 0, 0, 1, 0x65, 0x22]
        let avcc = AnnexB.toAVCC(AnnexB.split(data))
        #expect(avcc == [0, 0, 0, 2, 0x65, 0x11, 0, 0, 0, 2, 0x65, 0x22])
    }

    @Test func dataWithoutStartCodeGivesNoUnits() {
        #expect(AnnexB.split([0x65, 0x11, 0x22]).isEmpty)
    }
}

// MARK: - adb

struct ADBDeviceListParserTests {

    static let output = """
    * daemon not running; starting now at tcp:5037
    * daemon started successfully
    List of devices attached
    HT7A1A234567           device usb:336592896X product:walleye model:Pixel_2 device:walleye transport_id:1
    R58M12ABCDE            unauthorized usb:336592897X transport_id:2
    emulator-5554          offline transport_id:3
    0123456789ABCDEF       no permissions (missing udev rules?); see [http://developer.android.com/tools/device.html] usb:1-1 transport_id:4

    """

    @Test func parsesAllDevices() {
        let entries = ADBDeviceListParser.parse(Self.output)
        #expect(entries.map(\.serial) == ["HT7A1A234567", "R58M12ABCDE", "emulator-5554", "0123456789ABCDEF"])
        #expect(entries.map(\.state) == ["device", "unauthorized", "offline", "no permissions"])
    }

    @Test func readyDeviceGetsReadableNameAndNoMessage() throws {
        let pixel = try #require(ADBDeviceListParser.parse(Self.output).first)
        #expect(pixel.displayName == "Pixel 2")
        #expect(pixel.isReady)
        #expect(pixel.deviceInfo.statusMessage == nil)
        #expect(pixel.deviceInfo.id == DeviceID(platform: .android, rawID: "HT7A1A234567"))
    }

    @Test func unauthorizedDeviceExplainsWhatToDo() throws {
        let entry = try #require(ADBDeviceListParser.parse(Self.output).dropFirst().first)
        #expect(entry.displayName == "R58M12ABCDE")
        #expect(entry.statusMessage?.contains("Toestaan") == true)
    }

    @Test func emptyOutputGivesNoDevices() {
        #expect(ADBDeviceListParser.parse("List of devices attached\n\n").isEmpty)
    }
}

struct ADBLocatorTests {

    @Test func prefersInstalledADBOverBundled() {
        let found = ADBLocator.locate(
            environment: [:],
            home: "/Users/test",
            bundledPath: "/App/Resources/adb",
            isExecutable: { $0 == "/opt/homebrew/bin/adb" || $0 == "/App/Resources/adb" }
        )
        #expect(found == "/opt/homebrew/bin/adb")
    }

    @Test func androidHomeComesFirst() {
        let found = ADBLocator.locate(
            environment: ["ANDROID_HOME": "/sdk"],
            home: "/Users/test",
            bundledPath: nil,
            isExecutable: { _ in true }
        )
        #expect(found == "/sdk/platform-tools/adb")
    }

    @Test func fallsBackToBundled() {
        let found = ADBLocator.locate(
            environment: [:],
            home: "/Users/test",
            bundledPath: "/App/Resources/adb",
            isExecutable: { $0 == "/App/Resources/adb" }
        )
        #expect(found == "/App/Resources/adb")
    }

    @Test func nothingFound() {
        #expect(ADBLocator.locate(environment: [:], home: "/x", bundledPath: nil, isExecutable: { _ in false }) == nil)
    }
}

struct ScrcpyServerTests {
    @Test func parsesForwardPort() {
        #expect(ScrcpyServer.parseForwardPort("52341\n") == 52341)
        #expect(ScrcpyServer.parseForwardPort("error: device offline") == nil)
    }
}
