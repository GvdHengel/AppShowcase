import Foundation
import Testing
@testable import AppShowCase

struct QuickTimeMonitorTests {
    @Test func recognisesQuickTimePlayerOnly() {
        #expect(QuickTimeMonitor.isQuickTime(bundleID: "com.apple.QuickTimePlayerX"))
        #expect(!QuickTimeMonitor.isQuickTime(bundleID: "com.apple.Photos"))
        #expect(!QuickTimeMonitor.isQuickTime(bundleID: nil))
    }
}

struct AndroidQualityTests {
    @Test func defaultsToNormal() throws {
        let defaults = try #require(UserDefaults(suiteName: "AndroidQualityTests-\(UUID().uuidString)"))
        #expect(AndroidQuality.current(defaults) == .normal)
        defaults.set("high", forKey: AppSettingsKey.androidQuality)
        #expect(AndroidQuality.current(defaults) == .high)
        defaults.set("onzin", forKey: AppSettingsKey.androidQuality)
        #expect(AndroidQuality.current(defaults) == .normal)
    }

    @Test func lowQualityIsGentler() {
        #expect(AndroidQuality.low.bitRate < AndroidQuality.normal.bitRate)
        #expect(AndroidQuality.normal.bitRate < AndroidQuality.high.bitRate)
        #expect(AndroidQuality.low.maxFPS == 30)
    }

    @Test func serverArgumentsUseQualityAndScid() {
        let arguments = ScrcpyServer.serverArguments(serial: "HT7A", scid: 0x1234abcd, version: "3.3.1", quality: .low)
        #expect(arguments.prefix(3) == ["-s", "HT7A", "shell"])
        #expect(arguments.contains("3.3.1"))
        #expect(arguments.contains("scid=1234abcd"))
        #expect(arguments.contains("video_bit_rate=4000000"))
        #expect(arguments.contains("max_fps=30"))
        #expect(arguments.contains("control=false"))
        #expect(arguments.contains("tunnel_forward=true"))
    }
}
