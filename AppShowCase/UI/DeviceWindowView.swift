import SwiftUI

/// Venster voor één toestel. In fase 1/2 komt hier het live beeld,
/// in fase 3 het echte toestelframe eromheen.
struct DeviceWindowView: View {
    let deviceID: DeviceID?

    @Environment(DeviceRegistry.self) private var registry

    private var device: DeviceInfo? {
        deviceID.flatMap { registry.device(for: $0) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)

            if let device {
                PlaceholderPhone(device: device)
                    .padding(24)
            } else {
                ContentUnavailableView(
                    "Toestel niet verbonden",
                    systemImage: "cable.connector.slash",
                    description: Text("Sluit het toestel opnieuw aan. Dit venster pakt het automatisch weer op.")
                )
                .foregroundStyle(.white)
            }
        }
        .navigationTitle(device?.name ?? "Toestel")
        .frame(minWidth: 240, minHeight: 420)
    }
}

/// Tijdelijke weergave tot het live beeld (fase 1/2) en de frames (fase 3) er zijn.
private struct PlaceholderPhone: View {
    let device: DeviceInfo

    var body: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .strokeBorder(.gray.opacity(0.6), lineWidth: 10)
            .background(
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(.black)
            )
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: device.platform.symbolName)
                        .font(.system(size: 44))
                    Text(device.name)
                        .font(.headline)
                    Text("Live beeld volgt in fase \(device.platform == .iOS ? 1 : 2)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
    }
}
