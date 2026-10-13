import CoreGraphics
import Foundation
import Testing
@testable import AppShowCase

struct FramedCanvasTests {

    @Test func naturalSizeKeepsScreenAtFullResolution() {
        let screen = CGSize(width: 1080, height: 1920)
        let natural = FramedCanvas.naturalOutputSize(style: .androidClassic, screenSize: screen,
                                                     paddingFraction: 0.05, maxLongSide: 10_000)
        let canvas = FramedCanvas(style: .androidClassic, screenSize: screen,
                                  outputSize: natural.size, padding: natural.padding)
        // Het scherm staat (op afronding na) op ware pixelgrootte.
        #expect(abs(canvas.screenRect.width - 1080) < 2)
        #expect(abs(canvas.screenRect.height - 1920) < 4)
        // Even maten (vereist voor H.264).
        #expect(Int(natural.size.width) % 2 == 0)
        #expect(Int(natural.size.height) % 2 == 0)
    }

    @Test func naturalSizeIsCappedAtMaxLongSide() {
        let natural = FramedCanvas.naturalOutputSize(style: .iPhoneNotch, screenSize: CGSize(width: 1125, height: 2436),
                                                     paddingFraction: 0.05, maxLongSide: 2160)
        #expect(max(natural.size.width, natural.size.height) <= 2160)
    }

    @Test func screenRectLiesInsideOutputWithPadding() {
        let canvas = FramedCanvas(style: .iPhoneIsland, screenSize: CGSize(width: 1206, height: 2622),
                                  outputSize: CGSize(width: 1400, height: 2800), padding: 60)
        let rect = canvas.screenRect
        #expect(rect.minX >= 60 && rect.minY >= 60)
        #expect(rect.maxX <= 1340 && rect.maxY <= 2740)
        // Gecentreerd in de breedte.
        #expect(abs(rect.midX - 700) < 0.5)
    }

    @Test func landscapeScreenRectIsLandscape() {
        let canvas = FramedCanvas(style: .androidClassic, screenSize: CGSize(width: 1920, height: 1080),
                                  outputSize: CGSize(width: 2400, height: 1400), padding: 40)
        #expect(canvas.screenRect.width > canvas.screenRect.height)
    }
}

struct PixelBufferConverterTests {

    @Test func paddedBufferIsCroppedRightAndBottom() {
        // Gecodeerd 1088×1920, zichtbaar 1080×1920: rechts 8 px opvulling.
        let rect = PixelBufferConverter.visibleRect(bufferSize: CGSize(width: 1088, height: 1920),
                                                    cleanSize: CGSize(width: 1080, height: 1920))
        #expect(rect == CGRect(x: 0, y: 0, width: 1080, height: 1920))

        // Onder opvulling: in Core Image (oorsprong linksonder) begint het zichtbare deel hoger.
        let tall = PixelBufferConverter.visibleRect(bufferSize: CGSize(width: 1920, height: 1088),
                                                    cleanSize: CGSize(width: 1920, height: 1080))
        #expect(tall == CGRect(x: 0, y: 8, width: 1920, height: 1080))
    }

    @Test func missingOrInvalidCleanRectUsesWholeBuffer() {
        let size = CGSize(width: 1126, height: 2436)
        #expect(PixelBufferConverter.visibleRect(bufferSize: size, cleanSize: .zero) == CGRect(origin: .zero, size: size))
        #expect(PixelBufferConverter.visibleRect(bufferSize: size, cleanSize: CGSize(width: 2000, height: 3000))
                == CGRect(origin: .zero, size: size))
    }
}

struct AndroidDemoModeTests {

    @Test func demoBroadcastIsBuiltFromPairs() {
        #expect(AndroidDemoMode.demo(["command", "clock", "hhmm", "0941"]) == [
            "am", "broadcast", "-a", "com.android.systemui.demo",
            "-e", "command", "clock", "-e", "hhmm", "0941",
        ])
    }

    @Test func cleanStatusBarEnablesDemoModeFirst() {
        let commands = AndroidDemoMode.cleanStatusBarCommands
        #expect(commands.first == ["settings", "put", "global", "sysui_demo_allowed", "1"])
        #expect(commands.contains(AndroidDemoMode.demo(["command", "enter"])))
        #expect(commands.contains { $0.contains("0941") })
    }

    @Test func exitCommandLeavesDemoMode() {
        #expect(AndroidDemoMode.exitDemoCommand.suffix(2) == ["command", "exit"])
    }

    @Test(arguments: [("null", "0"), ("", "0"), ("7\n", "7"), ("1", "1")])
    func settingValuesAreNormalised(raw: String, expected: String) {
        #expect(AndroidDemoMode.normalized(raw) == expected)
    }
}

@MainActor
struct OutputAndUITests {

    @Test func unsafeCharactersAreRemovedFromFileNames() {
        #expect(OutputFolders.safeName("iPhone van Gerbrant") == "iPhone van Gerbrant")
        #expect(OutputFolders.safeName("a/b:c") == "a-b-c")
        #expect(OutputFolders.safeName("   ") == "Toestel")
    }

    @Test func timestampIsReadable() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 13
        components.hour = 19; components.minute = 5; components.second = 12
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(OutputFolders.timestamp(date) == "2026-10-13 om 19.05.12")
    }

    @Test func elapsedTimeFormatting() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(DeviceWindowView.elapsed(since: start, now: start.addingTimeInterval(5)) == "0:05")
        #expect(DeviceWindowView.elapsed(since: start, now: start.addingTimeInterval(125)) == "2:05")
    }

    @Test func actualSizeUsesBackingScale() {
        #expect(WindowSizePreset.actual.screenLongSide(pixelLongSide: 2436, backingScale: 2) == 1218)
        #expect(WindowSizePreset.medium.screenLongSide(pixelLongSide: 2436, backingScale: 2) == 680)
    }
}
