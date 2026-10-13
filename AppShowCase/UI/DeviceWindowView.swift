import SwiftUI

/// Venster voor één toestel: live beeld in een (voorlopig eenvoudig) toestelframe.
struct DeviceWindowView: View {
    let deviceID: DeviceID?

    @Environment(DeviceRegistry.self) private var registry
    @Environment(IOSDiscovery.self) private var iosDiscovery
    @Environment(AndroidDiscovery.self) private var androidDiscovery
    @State private var session: MirrorSession?

    private var device: DeviceInfo? {
        deviceID.flatMap { registry.device(for: $0) }
    }

    var body: some View {
        ZStack {
            Color(white: 0.13)

            if let device, let session {
                PlaceholderBezel(screenAspectRatio: aspectRatio(of: session), platform: device.platform) {
                    VideoDisplayView(videoLayer: session.displayLayer)
                }
                .overlay { MirrorStateOverlay(state: session.state, retry: connect) }
                .padding(24)
            } else if device == nil {
                ContentUnavailableView(
                    "Toestel niet verbonden",
                    systemImage: "cable.connector.slash",
                    description: Text("Sluit het toestel opnieuw aan. Dit venster pakt het automatisch weer op.")
                )
                .foregroundStyle(.white)
            }
        }
        .navigationTitle(device?.name ?? "Toestel")
        .frame(minWidth: 240, minHeight: 300)
        // Opnieuw verbinden zodra het toestel (weer) verschijnt, verdwijnt of bruikbaar wordt.
        .task(id: connectionKey) { connect() }
        .onDisappear { session?.stop() }
    }

    private var connectionKey: String {
        guard let device else { return "geen" }
        return "\(device.id)|\(device.statusMessage ?? "gereed")"
    }

    private func aspectRatio(of session: MirrorSession) -> CGFloat {
        guard let size = session.videoSize, size.height > 0 else { return 9.0 / 19.5 }
        return size.width / size.height
    }

    private func connect() {
        guard let device else {
            session?.stop()
            return
        }
        let current = (session?.deviceID == device.id ? session : nil) ?? MirrorSession(deviceID: device.id)
        session = current

        if device.id.rawID.hasPrefix("demo-") {
            current.markUnavailable("Demo-toestel: geen live beeld.")
            return
        }
        if let statusMessage = device.statusMessage {
            current.markUnavailable(statusMessage)
            return
        }

        switch device.platform {
        case .iOS:
            if let captureDevice = iosDiscovery.captureDevice(for: device.id) {
                current.start(with: IOSCaptureSource(device: captureDevice))
            } else {
                current.markUnavailable("Het toestel is niet meer beschikbaar. Sluit het opnieuw aan.")
            }
        case .android:
            do {
                let source = try androidDiscovery.makeSource(serial: device.id.rawID)
                current.start(with: source)
            } catch {
                current.markUnavailable(error.localizedDescription)
            }
        }
    }
}

/// Status over het beeld heen: verbinden, wachten of fout.
private struct MirrorStateOverlay: View {
    let state: MirrorState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .mirroring:
            EmptyView()
        case .connecting:
            ProgressView("Verbinden…")
                .controlSize(.large)
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        case .waiting(let message):
            messageCard(icon: "lock.iphone", text: message, showRetry: false)
        case .failed(let message):
            messageCard(icon: "exclamationmark.triangle", text: message, showRetry: true)
        }
    }

    private func messageCard(icon: String, text: String, showRetry: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
            Text(text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showRetry {
                Button("Opnieuw proberen", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
