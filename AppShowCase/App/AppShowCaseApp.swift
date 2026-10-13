import SwiftUI

/// Vaste venster-ID's, zodat `openWindow` ze overal kan gebruiken.
enum WindowID {
    static let deviceList = "device-list"
    static let device = "device"
}

@main
struct AppShowCaseApp: App {
    @State private var registry = DeviceRegistry()

    var body: some Scene {
        // Overzicht van alle aangesloten toestellen.
        Window("Apparaten", id: WindowID.deviceList) {
            DeviceListView()
                .environment(registry)
        }
        .defaultSize(width: 340, height: 460)

        // Eén venster per toestel — makkelijk te kiezen bij "venster delen" in Teams/Zoom.
        WindowGroup("Toestel", id: WindowID.device, for: DeviceID.self) { $deviceID in
            DeviceWindowView(deviceID: deviceID)
                .environment(registry)
        }
        .defaultSize(width: 420, height: 820)

        // Altijd bereikbaar via de menubalk.
        MenuBarExtra("AppShowCase", systemImage: "iphone.gen3") {
            MenuBarContent()
                .environment(registry)
        }
    }
}
