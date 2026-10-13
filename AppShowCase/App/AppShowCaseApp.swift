import SwiftUI

/// Vaste venster-ID's, zodat `openWindow` ze overal kan gebruiken.
enum WindowID {
    static let deviceList = "device-list"
    static let device = "device"
}

@main
struct AppShowCaseApp: App {
    @State private var registry: DeviceRegistry
    @State private var iosDiscovery: IOSDiscovery

    init() {
        let registry = DeviceRegistry()
        _registry = State(initialValue: registry)
        // Start direct: CoreMediaIO-vlag, camera-toestemming en iPhone-detectie.
        _iosDiscovery = State(initialValue: IOSDiscovery(registry: registry))
    }

    var body: some Scene {
        // Overzicht van alle aangesloten toestellen.
        Window("Apparaten", id: WindowID.deviceList) {
            DeviceListView()
                .environment(registry)
                .environment(iosDiscovery)
        }
        .defaultSize(width: 340, height: 460)

        // Eén venster per toestel — makkelijk te kiezen bij "venster delen" in Teams/Zoom.
        WindowGroup("Toestel", id: WindowID.device, for: DeviceID.self) { $deviceID in
            DeviceWindowView(deviceID: deviceID)
                .environment(registry)
                .environment(iosDiscovery)
        }
        .defaultSize(width: 420, height: 820)

        // Altijd bereikbaar via de menubalk.
        MenuBarExtra("AppShowCase", systemImage: "iphone.gen3") {
            MenuBarContent()
                .environment(registry)
        }
    }
}
