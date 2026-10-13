import AppKit
import SwiftUI

/// Inhoud van het menubalk-menu.
struct MenuBarContent: View {
    @Environment(DeviceRegistry.self) private var registry
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if registry.devices.isEmpty {
            Text("Geen toestellen aangesloten")
        } else {
            ForEach(registry.devices) { device in
                Button {
                    openWindow(id: WindowID.device, value: device.id)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(device.name, systemImage: device.platform.symbolName)
                }
            }
        }

        Divider()

        Button("Toon apparatenlijst") {
            openWindow(id: WindowID.deviceList)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Stop AppShowCase") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
