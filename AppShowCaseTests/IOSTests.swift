import Testing
@testable import AppShowCase

struct IOSScreenRecognitionTests {

    @Test(arguments: [
        ("iOS Device", "iPhone van Gerbrant"),
        ("iPhone11,2", "iPhone"),
        ("iPad13,1", "iPad"),
        ("iOS Device", "Mijn toestel"),
    ])
    func recognisesIOSScreens(modelID: String, name: String) {
        #expect(IOSDiscovery.isIOSScreen(modelID: modelID, name: name, manufacturer: "Apple Inc."))
    }

    @Test(arguments: [
        ("UVC Camera VendorID_1452", "Studio Display Camera"),
        ("Elgato Cam Link", "Cam Link 4K"),
    ])
    func ignoresOtherCaptureDevices(modelID: String, name: String) {
        #expect(!IOSDiscovery.isIOSScreen(modelID: modelID, name: name, manufacturer: "Apple Inc."))
    }
}

struct FormatSelectorTests {

    @Test func prefersHighestFrameRate() {
        let formats = [
            FormatCandidate(index: 0, width: 1125, height: 2436, maxFPS: 30),
            FormatCandidate(index: 1, width: 886, height: 1920, maxFPS: 60),
        ]
        #expect(FormatSelector.best(formats)?.index == 1)
    }

    @Test func prefersLargerResolutionAtEqualFrameRate() {
        let formats = [
            FormatCandidate(index: 0, width: 886, height: 1920, maxFPS: 60),
            FormatCandidate(index: 1, width: 1125, height: 2436, maxFPS: 60),
        ]
        #expect(FormatSelector.best(formats)?.index == 1)
    }

    @Test func emptyListGivesNil() {
        #expect(FormatSelector.best([]) == nil)
    }
}
