import SwiftUI

/// Lijst met aangesloten toestellen, gegroepeerd per platform.
struct DeviceListView: View {
    @Environment(DeviceRegistry.self) private var registry
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List {
            ForEach(Platform.allCases, id: \.self) { platform in
                Section(platform.displayName) {
                    let devices = registry.devices(for: platform)
                    if devices.isEmpty {
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
        }
        .listStyle(.sidebar)
        .navigationTitle("Apparaten")
        .modifier(DeveloperToolbar(registry: registry))
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
                if let model = device.model {
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

#Preview {
    DeviceListView()
        .environment(DeviceRegistry())
        .frame(width: 340, height: 460)
}
