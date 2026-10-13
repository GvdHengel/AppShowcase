import CoreGraphics
import Testing
@testable import AppShowCase

struct FrameMatcherTests {

    @Test(arguments: [
        (CGSize(width: 1126, height: 2436), "iphone-notch"),      // iPhone Xs (zoals de capture hem levert)
        (CGSize(width: 2436, height: 1126), "iphone-notch"),      // idem, liggend
        (CGSize(width: 1206, height: 2622), "iphone-island"),     // iPhone 16 Pro
        (CGSize(width: 1179, height: 2556), "iphone-island"),     // iPhone 15
        (CGSize(width: 1170, height: 2532), "iphone-notch"),      // iPhone 13/14
        (CGSize(width: 750, height: 1334), "iphone-home"),        // iPhone 8 / SE
        (CGSize(width: 1640, height: 2360), "tablet"),            // iPad Air
    ])
    func iOS(size: CGSize, expected: String) {
        #expect(FrameMatcher.automaticStyle(platform: .iOS, screenSize: size).id == expected)
    }

    @Test(arguments: [
        (CGSize(width: 1080, height: 1920), "android-classic"),   // Pixel 2
        (CGSize(width: 1920, height: 1080), "android-classic"),   // Pixel 2 liggend
        (CGSize(width: 1080, height: 2400), "android-punchhole"), // modern 20:9
        (CGSize(width: 1600, height: 2560), "tablet"),            // Android-tablet
    ])
    func android(size: CGSize, expected: String) {
        #expect(FrameMatcher.automaticStyle(platform: .android, screenSize: size).id == expected)
    }

    @Test func unknownSizeGivesPlatformDefault() {
        #expect(FrameMatcher.automaticStyle(platform: .iOS, screenSize: nil).platform == .iOS)
        #expect(FrameMatcher.automaticStyle(platform: .android, screenSize: nil).platform == .android)
    }
}

struct FrameLayoutTests {

    @Test(arguments: DeviceFrameStyle.all)
    func portraitFitsAndKeepsScreenAspect(style: DeviceFrameStyle) {
        let available = CGSize(width: 400, height: 800)
        let layout = FrameLayout(style: style, screenSize: CGSize(width: 1080, height: 1920), fitting: available)

        #expect(!layout.isLandscape)
        #expect(layout.displaySize.width <= available.width + 0.001)
        #expect(layout.displaySize.height <= available.height + 0.001)
        // Eén van beide zijden vult de ruimte.
        #expect(abs(layout.displaySize.width - available.width) < 0.01 || abs(layout.displaySize.height - available.height) < 0.01)
        // Beeldverhouding van het scherm blijft exact.
        #expect(abs(layout.screenRect.width / layout.screenRect.height - 1080.0 / 1920.0) < 0.0001)
        // Scherm ligt binnen de behuizing.
        #expect(layout.bodyRect.contains(layout.screenRect) || !style.drawsBody)
    }

    @Test(arguments: DeviceFrameStyle.all)
    func landscapeIsRotatedAndFits(style: DeviceFrameStyle) {
        let available = CGSize(width: 900, height: 450)
        let layout = FrameLayout(style: style, screenSize: CGSize(width: 2436, height: 1126), fitting: available)

        #expect(layout.isLandscape)
        #expect(layout.displaySize.width == layout.canvasSize.height)
        #expect(layout.displaySize.height == layout.canvasSize.width)
        #expect(layout.displaySize.width <= available.width + 0.001)
        #expect(layout.displaySize.height <= available.height + 0.001)

        let screen = layout.displayScreenRect
        #expect(abs(screen.width / screen.height - 2436.0 / 1126.0) < 0.0001)
        #expect(screen.minX >= -0.001 && screen.maxX <= layout.displaySize.width + 0.001)
        #expect(screen.minY >= -0.001 && screen.maxY <= layout.displaySize.height + 0.001)
    }

    @Test func rotationPutsTopEdgeOnTheLeft() {
        // Een strook bovenaan het staande canvas (bijv. de notch) komt links te staan.
        let topStrip = CGRect(x: 40, y: 0, width: 20, height: 5)
        let rotated = FrameLayout.rotateToLandscape(topStrip, canvasWidth: 100)
        #expect(rotated == CGRect(x: 0, y: 40, width: 5, height: 20))
    }

    @Test func notchSitsAtTopCenterOfScreen() throws {
        let layout = FrameLayout(style: .iPhoneNotch, screenSize: CGSize(width: 1125, height: 2436), fitting: CGSize(width: 400, height: 800))
        let notch = try #require(layout.cutout)
        #expect(abs(notch.rect.midX - layout.screenRect.midX) < 0.001)
        #expect(notch.rect.minY == layout.screenRect.minY)
    }

    @Test func zeroSpaceDoesNotCrash() {
        let layout = FrameLayout(style: .iPhoneIsland, screenSize: CGSize(width: 1206, height: 2622), fitting: .zero)
        #expect(layout.scale == 0)
    }
}

struct DeviceFrameStyleTests {
    @Test func choicesStartWithOwnPlatformAndEndWithNone() {
        let android = DeviceFrameStyle.choices(for: .android)
        #expect(android.first?.platform == .android)
        #expect(android.last == .none)
        #expect(Set(android.map(\.id)).count == DeviceFrameStyle.all.count)
    }

    @Test func idsAreUnique() {
        #expect(Set(DeviceFrameStyle.all.map(\.id)).count == DeviceFrameStyle.all.count)
    }
}
