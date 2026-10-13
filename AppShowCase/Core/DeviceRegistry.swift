import Foundation
import Observation

/// Centrale lijst van alle aangesloten toestellen (iOS + Android).
///
/// De platform-specifieke discovery (fase 1: iOS, fase 2: Android) meldt
/// zijn actuele lijst via `replaceDevices(of:with:)`; de UI leest alleen.
@MainActor
@Observable
final class DeviceRegistry {
    private(set) var devices: [DeviceInfo] = []

    func device(for id: DeviceID) -> DeviceInfo? {
        devices.first { $0.id == id }
    }

    func devices(for platform: Platform) -> [DeviceInfo] {
        devices.filter { $0.platform == platform }
    }

    /// Vervangt alle toestellen van één platform; andere platforms blijven staan.
    func replaceDevices(of platform: Platform, with newDevices: [DeviceInfo]) {
        let others = devices.filter { $0.platform != platform }
        let incoming = newDevices.filter { $0.platform == platform }
        devices = (others + incoming).sorted {
            ($0.platform.rawValue, $0.name) < ($1.platform.rawValue, $1.name)
        }
    }

    #if DEBUG
    /// Alleen voor ontwikkelen: nep-toestellen om vensters en frames te testen zonder hardware.
    func addDemoDevices() {
        replaceDevices(of: .iOS, with: devices(for: .iOS) + [
            DeviceInfo(id: DeviceID(platform: .iOS, rawID: "demo-ios-\(UUID().uuidString.prefix(4))"),
                       name: "Demo iPhone", model: "iPhone11,2")
        ])
        replaceDevices(of: .android, with: devices(for: .android) + [
            DeviceInfo(id: DeviceID(platform: .android, rawID: "demo-android-\(UUID().uuidString.prefix(4))"),
                       name: "Demo Pixel", model: "Pixel 2")
        ])
    }

    func removeAllDevices() {
        devices = []
    }
    #endif
}
