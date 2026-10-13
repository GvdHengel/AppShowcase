import AppKit
import SwiftUI

/// Lijst met aangesloten toestellen, gegroepeerd per platform.
struct DeviceListView: View {
    @Environment(DeviceRegistry.self) private var registry
    @Environment(IOSDiscovery.self) private var iosDiscovery
    @Environment(AndroidDiscovery.self) private var androidDiscovery
    @Environment(\.openWindow) private var openWindow
    @AppStorage("autoOpenWindows") private var autoOpenWindows = true

    /// Toestellen die klaar zijn om te tonen (dus niet "Tik op Toestaan" e.d.).
    private var readyDeviceIDs: Set<DeviceID> {
        Set(registry.devices.filter { $0.statusMessage == nil }.map(\.id))
    }

    var body: some View {
        List {
            ForEach(Platform.allCases, id: \.self) { platform in
                Section(platform.displayName) {
                    let devices = registry.devices(for: platform)
                    if platform == .iOS && iosDiscovery.authorization == .denied {
                        CameraAccessRow { iosDiscovery.recheckAuthorization() }
                    } else if platform == .android && androidDiscovery.status == .adbMissing {
                        Label(AndroidSetupError.adbMissing.errorDescription ?? "adb niet gevonden", systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if devices.isEmpty {
                        EmptyPlatformRow(platform: platform)
                    } else {
                        ForEach(devices) { device in
                            DeviceRow(device: device) {
                                openWindow(id: WindowID.device, value: device.id)
                            }
                        }
                    }
                }
            }

            Section("Opties") {
                Toggle("Venster openen bij aansluiten", isOn: $autoOpenWindows)
            }
        }
        .listStyle(.sidebar)
        // Nieuw (of nu pas toegestaan) toestel: meteen een eigen venster openen.
        .onChange(of: readyDeviceIDs) { previous, current in
            guard autoOpenWindows else { return }
            for id in current.subtracting(previous) {
                openWindow(id: WindowID.device, value: id)
            }
        }
        .navigationTitle("Apparaten")
        .modifier(DeveloperToolbar(registry: registry))
        // Na terugkomen uit Systeeminstellingen opnieuw controleren.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            iosDiscovery.recheckAuthorization()
        }
    }
}

/// Uitleg als camera-toegang (nodig voor het iPhone-scherm) geweigerd is.
private struct CameraAccessRow: View {
    let recheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Camera-toegang nodig", systemImage: "camera.fill")
                .foregroundStyle(.orange)
            Text("macOS levert het iPhone-scherm aan als camerabron. Sta AppShowCase toe onder Privacy en beveiliging → Camera.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Systeeminstellingen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Opnieuw controleren", action: recheck)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

/// Ontwikkelaarsmenu met nep-toestellen; bestaat alleen in Debug-builds.
private struct DeveloperToolbar: ViewModifier {
    let registry: DeviceRegistry

    func body(content: Content) -> some View {
        #if DEBUG
        content.toolbar {
            ToolbarItem {
                Menu {
                    Button("Demo-toestellen toevoegen") { registry.addDemoDevices() }
                    Button("Alles wissen", role: .destructive) { registry.removeAllDevices() }
                } label: {
                    Label("Ontwikkelaar", systemImage: "hammer")
                }
                .help("Alleen in Debug-builds: nep-toestellen om vensters te testen")
            }
        }
        #else
        content
        #endif
    }
}

private struct DeviceRow: View {
    let device: DeviceInfo
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.platform.symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                if let statusMessage = device.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let model = device.model, model != device.name {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Toon", action: open)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: open)
    }
}

private struct EmptyPlatformRow: View {
    let platform: Platform

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Geen \(platform.displayName)-toestel")
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var hint: String {
        switch platform {
        case .iOS:
            return "Sluit je iPhone of iPad aan via USB, ontgrendel hem en kies 'Vertrouw'."
        case .android:
            return "Sluit je toestel aan via USB en zet USB-foutopsporing aan in de Ontwikkelaarsopties."
        }
    }
}
