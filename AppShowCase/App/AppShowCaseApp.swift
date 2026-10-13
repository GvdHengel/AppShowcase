import AppKit
import SwiftUI

/// Vaste venster-ID's, zodat `openWindow` ze overal kan gebruiken.
enum WindowID {
    static let deviceList = "device-list"
    static let device = "device"
    static let help = "help"
}

@main
struct AppShowCaseApp: App {
    @State private var registry: DeviceRegistry
    @State private var iosDiscovery: IOSDiscovery
    @State private var androidDiscovery: AndroidDiscovery
    @State private var quickTime = QuickTimeMonitor()

    init() {
        let registry = DeviceRegistry()
        _registry = State(initialValue: registry)
        // Start direct: CoreMediaIO-vlag, camera-toestemming en iPhone-detectie.
        _iosDiscovery = State(initialValue: IOSDiscovery(registry: registry))
        // Start direct: adb zoeken en Android-toestellen volgen.
        _androidDiscovery = State(initialValue: AndroidDiscovery(registry: registry))
    }

    var body: some Scene {
        // Overzicht van alle aangesloten toestellen.
        Window("Apparaten", id: WindowID.deviceList) {
            DeviceListView()
                .environment(registry)
                .environment(iosDiscovery)
                .environment(androidDiscovery)
        }
        .defaultSize(width: 340, height: 460)
        .commands { AppCommands() }

        // Eén venster per toestel — makkelijk te kiezen bij "venster delen" in Teams/Zoom.
        WindowGroup("Toestel", id: WindowID.device, for: DeviceID.self) { $deviceID in
            DeviceWindowView(deviceID: deviceID)
                .environment(registry)
                .environment(iosDiscovery)
                .environment(androidDiscovery)
                .environment(quickTime)
        }
        .defaultSize(width: 420, height: 820)

        Window("AppShowCase-hulp", id: WindowID.help) {
            HelpView()
        }
        .defaultSize(width: 560, height: 720)

        Settings {
            SettingsView()
                .environment(androidDiscovery)
        }

        // Altijd bereikbaar via de menubalk.
        MenuBarExtra("AppShowCase", systemImage: "iphone.gen3") {
            MenuBarContent()
                .environment(registry)
        }
    }
}

/// Menu-aanpassingen: Over-venster met bronvermelding en een eigen Help-menu.
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Over AppShowCase") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(replacing: .help) {
            Button("AppShowCase-hulp") {
                openWindow(id: WindowID.help)
            }
            .keyboardShortcut("?", modifiers: .command)
            Button("Apparatenlijst") {
                openWindow(id: WindowID.deviceList)
            }
            Divider()
            Button("AppShowCase op GitHub") {
                if let url = URL(string: "https://github.com/GvdHengel/AppShowcase") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private static var credits: NSAttributedString {
        let text = """
        iPhone- en Android-schermen live op je Mac, in een toestelframe.

        Android-beeld via scrcpy-server van Genymobile (Apache-2.0) en adb (Android SDK Platform-Tools).
        """
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}
