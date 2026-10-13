import SwiftUI

/// Venster voor één toestel: live beeld in een toestelframe.
struct DeviceWindowView: View {
    let deviceID: DeviceID?

    @Environment(DeviceRegistry.self) private var registry
    @Environment(IOSDiscovery.self) private var iosDiscovery
    @Environment(AndroidDiscovery.self) private var androidDiscovery
    @State private var session: MirrorSession?

    /// Per toestel onthouden: gekozen frame ("auto" of een frame-id) en achtergrond.
    @AppStorage private var frameChoice: String
    @AppStorage private var backgroundChoice: String

    init(deviceID: DeviceID?) {
        self.deviceID = deviceID
        let key = deviceID?.description ?? "onbekend"
        _frameChoice = AppStorage(wrappedValue: DeviceFrameStyle.automaticID, "frame.\(key)")
        _backgroundChoice = AppStorage(wrappedValue: WindowBackground.dark.rawValue, "background.\(key)")
    }

    private var device: DeviceInfo? {
        deviceID.flatMap { registry.device(for: $0) }
    }

    private var background: WindowBackground {
        WindowBackground(rawValue: backgroundChoice) ?? .dark
    }

    var body: some View {
        ZStack {
            background.color
                .ignoresSafeArea()

            if let device, let session {
                DeviceFrameView(style: frameStyle(for: device), screenSize: screenSize) {
                    VideoDisplayView(videoLayer: session.displayLayer)
                }
                .overlay { MirrorStateOverlay(state: session.state, retry: connect) }
                .padding(background == .transparent ? 10 : 24)
                .contextMenu { displayOptions }
            } else if device == nil {
                ContentUnavailableView(
                    "Toestel niet verbonden",
                    systemImage: "cable.connector.slash",
                    description: Text("Sluit het toestel opnieuw aan. Dit venster pakt het automatisch weer op.")
                )
                .foregroundStyle(background == .light ? Color.primary : Color.white)
            }
        }
        .background(WindowConfigurator(transparent: background == .transparent))
        .navigationTitle(device?.name ?? "Toestel")
        .navigationSubtitle(resolutionText)
        .toolbar {
            ToolbarItem {
                Menu {
                    displayOptions
                } label: {
                    Label("Weergave", systemImage: "iphone.gen3")
                }
                .help("Toestelframe en achtergrond")
            }
        }
        .toolbarBackground(background == .transparent ? .hidden : .automatic, for: .windowToolbar)
        .frame(minWidth: 240, minHeight: 300)
        // Opnieuw verbinden zodra het toestel (weer) verschijnt, verdwijnt of bruikbaar wordt.
        .task(id: connectionKey) { connect() }
        .onDisappear { session?.stop() }
    }

    // MARK: - Weergave-opties (toolbar én rechtermuisklik)

    @ViewBuilder
    private var displayOptions: some View {
        Picker("Toestelframe", selection: $frameChoice) {
            Text("Automatisch (\(automaticStyle.name))").tag(DeviceFrameStyle.automaticID)
            ForEach(DeviceFrameStyle.choices(for: device?.platform)) { style in
                Text(style.name).tag(style.id)
            }
        }
        .pickerStyle(.inline)

        Picker("Achtergrond", selection: $backgroundChoice) {
            ForEach(WindowBackground.allCases) { option in
                Text(option.name).tag(option.rawValue)
            }
        }
        .pickerStyle(.inline)
    }

    private var automaticStyle: DeviceFrameStyle {
        FrameMatcher.automaticStyle(platform: device?.platform ?? .iOS, screenSize: session?.videoSize)
    }

    private func frameStyle(for device: DeviceInfo) -> DeviceFrameStyle {
        if frameChoice != DeviceFrameStyle.automaticID, let chosen = DeviceFrameStyle.style(id: frameChoice) {
            return chosen
        }
        return automaticStyle
    }

    /// Tot het eerste frame binnen is: een gangbare staande telefoonverhouding.
    private var screenSize: CGSize {
        session?.videoSize ?? CGSize(width: 9, height: 19.5)
    }

    /// Bijv. "1080 × 1920" — handig om te controleren of de beeldverhouding klopt.
    private var resolutionText: String {
        guard let size = session?.videoSize else { return "" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    // MARK: - Verbinden

    private var connectionKey: String {
        guard let device else { return "geen" }
        return "\(device.id)|\(device.statusMessage ?? "gereed")"
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
