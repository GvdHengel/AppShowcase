import Foundation
import Testing
@testable import AppShowCase

@MainActor
struct DeviceRegistryTests {

    private func device(_ platform: Platform, _ id: String, _ name: String) -> DeviceInfo {
        DeviceInfo(id: DeviceID(platform: platform, rawID: id), name: name, model: nil)
    }

    @Test func replaceKeepsOtherPlatform() {
        let registry = DeviceRegistry()
        registry.replaceDevices(of: .iOS, with: [device(.iOS, "a", "iPhone Xs")])
        registry.replaceDevices(of: .android, with: [device(.android, "b", "Pixel 2")])

        registry.replaceDevices(of: .android, with: [])

        #expect(registry.devices.map(\.name) == ["iPhone Xs"])
    }

    @Test func ignoresDevicesOfWrongPlatform() {
        let registry = DeviceRegistry()
        registry.replaceDevices(of: .iOS, with: [device(.android, "x", "Verkeerd")])
        #expect(registry.devices.isEmpty)
    }

    @Test func lookupByID() {
        let registry = DeviceRegistry()
        let pixel = device(.android, "serial123", "Pixel 2")
        registry.replaceDevices(of: .android, with: [pixel])
        #expect(registry.device(for: pixel.id)?.name == "Pixel 2")
    }

    @Test func deviceIDRoundTripsThroughJSON() throws {
        let id = DeviceID(platform: .iOS, rawID: "00008030-ABC")
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(DeviceID.self, from: data) == id)
    }
}
