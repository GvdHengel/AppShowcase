import AppKit
import SwiftUI

/// Venster voor één toestel: live beeld in een toestelframe, met schermafbeelding, opname en demo-opties.
struct DeviceWindowView: View {
    let deviceID: DeviceID?

    @Environment(DeviceRegistry.self) private var registry
    @Environment(IOSDiscovery.self) private var iosDiscovery
    @Environment(AndroidDiscovery.self) private var androidDiscovery
    @Environment(QuickTimeMonitor.self) private var quickTime
    @AppStorage(AppSettingsKey.copyScreenshotToClipboard) private var copyScreenshotToClipboard = true

    @State private var session: MirrorSession?
    @State private var demoMode: AndroidDemoMode?
    @State private var recorder: FramedRecorder?
    @State private var recordingStarted: Date?
    @State private var toast: Toast?
    @State private var windowReference = WindowReference()
    @State private var isHovering = false

    /// Per toestel onthouden: frame ("auto" of frame-id), achtergrond en altijd bovenop.
    @AppStorage private var frameChoice: String
    @AppStorage private var backgroundChoice: String
    @AppStorage private var floating: Bool

    init(deviceID: DeviceID?) {
        self.deviceID = deviceID
        let key = deviceID?.description ?? "onbekend"
        _frameChoice = AppStorage(wrappedValue: DeviceFrameStyle.automaticID, "frame.\(key)")
        _backgroundChoice = AppStorage(wrappedValue: WindowBackground.dark.rawValue, "background.\(key)")
        _floating = AppStorage(wrappedValue: false, "floating.\(key)")
    }

    private var device: DeviceInfo? {
        deviceID.flatMap { registry.device(for: $0) }
    }

    private var background: WindowBackground {
        WindowBackground(rawValue: backgroundChoice) ?? .dark
    }

    private var padding: CGFloat {
        background == .transparent ? 10 : 24
    }

    private var isMirroring: Bool {
        session?.state == .mirroring
    }

    /// iPhone zonder beeld terwijl QuickTime draait: waarschijnlijk houdt QuickTime het scherm bezet.
    private var showsQuickTimeHint: Bool {
        guard let device, device.platform == .iOS, !device.id.rawID.hasPrefix("demo-"),
              quickTime.isRunning, let state = session?.state else { return false }
        switch state {
        case .failed, .waiting: return true
        case .idle, .connecting, .mirroring: return false
        }
    }

    var body: some View {
        ZStack {
            background.color
                .ignoresSafeArea()

            if let device, let session {
                DeviceFrameView(style: frameStyle(for: device), screenSize: screenSize) {
                    VideoDisplayView(videoLayer: session.displayLayer)
                }
                .overlay {
                    if showsQuickTimeHint {
                        QuickTimeCard(quit: { quickTime.quit() }, retry: connect)
                    } else {
                        MirrorStateOverlay(state: session.state, retry: connect)
                    }
                }
                .padding(padding)
                .contextMenu {
                    captureButtons
                    Divider()
                    displayOptions
                }
            } else if device == nil {
                ContentUnavailableView(
                    "Toestel niet verbonden",
                    systemImage: "cable.connector.slash",
                    description: Text("Sluit het toestel opnieuw aan. Dit venster pakt het automatisch weer op.")
                )
                .foregroundStyle(background == .light ? Color.primary : Color.white)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                toastView
                controlBar
            }
            .padding(.bottom, 12)
        }
        .background(keyboardShortcuts)
        .background(WindowConfigurator(transparent: background == .transparent, floating: floating, reference: windowReference))
        .navigationTitle(device?.name ?? "Toestel")
        .navigationSubtitle(resolutionText)
        .toolbar {
            ToolbarItemGroup {
                captureButtons
                Menu {
                    displayOptions
                } label: {
                    Label("Weergave", systemImage: "iphone.gen3")
                }
                .help("Frame, achtergrond, venster en demo-opties")
            }
        }
        .toolbarBackground(background == .transparent ? .hidden : .automatic, for: .windowToolbar)
        .frame(minWidth: 240, minHeight: 300)
        // Opnieuw verbinden zodra het toestel (weer) verschijnt, verdwijnt of bruikbaar wordt.
        .task(id: connectionKey) { connect() }
        // QuickTime gestopt terwijl we geen beeld hadden: vanzelf opnieuw verbinden.
        .onChange(of: quickTime.isRunning) { _, running in
            guard !running, device?.platform == .iOS, session?.state != .mirroring else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                connect()
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            toast = nil
        }
        .onDisappear {
            stopRecording()
            if let demoMode {
                Task { await demoMode.restoreAll() }
            }
            session?.stop()
        }
    }

    // MARK: - Knoppen en menu's

    @ViewBuilder
    private var captureButtons: some View {
        Button(action: takeScreenshot) {
            Label("Schermafbeelding", systemImage: "camera")
        }
        .disabled(!isMirroring)
        .help("Schermafbeelding mét frame (⇧⌘S) — bewaard in Afbeeldingen/AppShowCase en gekopieerd")

        Button(action: toggleRecording) {
            Label(recorder == nil ? "Opnemen" : "Stop opname",
                  systemImage: recorder == nil ? "record.circle" : "stop.circle.fill")
        }
        .disabled(recorder == nil && !isMirroring)
        .help("Opname mét frame (⇧⌘R) — bewaard in Films/AppShowCase")
    }

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

        Section("Venster") {
            Toggle("Altijd bovenop", isOn: $floating)
            Menu("Venstergrootte") {
                ForEach(WindowSizePreset.allCases) { preset in
                    Button(preset.name) { resize(to: preset) }
                }
            }
            .disabled(session?.videoSize == nil)
        }

        if let demoMode {
            Section("Android-demo") {
                Toggle("Scherm aan houden", isOn: Binding(
                    get: { demoMode.stayAwake },
                    set: { value in Task { await demoMode.setStayAwake(value) } }
                ))
                Toggle("Aanrakingen tonen", isOn: Binding(
                    get: { demoMode.showTouches },
                    set: { value in Task { await demoMode.setShowTouches(value) } }
                ))
                Toggle("Schone statusbalk (9:41, vol)", isOn: Binding(
                    get: { demoMode.cleanStatusBar },
                    set: { value in Task { await demoMode.setCleanStatusBar(value) } }
                ))
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 10) {
                Text(toast.text)
                    .lineLimit(2)
                if let url = toast.url {
                    Button("Toon in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .transition(.opacity)
        }
    }

    /// Zwevende balk onderin: tijdens een opname altijd zichtbaar (timer + stop),
    /// anders alleen als de muis boven het venster is. Komt niet in de opname zelf terecht.
    @ViewBuilder
    private var controlBar: some View {
        if let recordingStarted {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: recordingStarted, by: 1)) { context in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 9, height: 9)
                        Text(Self.elapsed(since: recordingStarted, now: context.date))
                            .monospacedDigit()
                    }
                }
                Button(action: stopRecording) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .font(.callout)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .help("Opname loopt — Stop of ⇧⌘R")
            .transition(.opacity)
        } else if isHovering && isMirroring {
            HStack(spacing: 2) {
                Button(action: takeScreenshot) {
                    Image(systemName: "camera")
                        .frame(width: 30, height: 26)
                }
                .help("Schermafbeelding mét frame (⇧⌘S)")
                Button(action: startRecording) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 26)
                }
                .help("Opname mét frame starten (⇧⌘R)")
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .transition(.opacity)
        }
    }

    /// Sneltoetsen die altijd werken, ook als de knoppen in de werkbalk zijn weggevallen.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("", action: takeScreenshot)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!isMirroring)
            Button("", action: toggleRecording)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(recorder == nil && !isMirroring)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Frame en maat

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

    private func resize(to preset: WindowSizePreset) {
        guard let window = windowReference.window, let device, let videoSize = session?.videoSize else { return }
        let style = frameStyle(for: device)
        let probe = FrameLayout(style: style, screenSize: videoSize, fitting: CGSize(width: 100_000, height: 100_000))
        let probeScreen = probe.displayScreenRect
        let probeLong = max(probeScreen.width, probeScreen.height)
        guard probeLong > 0 else { return }

        let target = preset.screenLongSide(
            pixelLongSide: max(videoSize.width, videoSize.height),
            backingScale: window.backingScaleFactor
        )
        let factor = target / probeLong
        window.setContentSize(CGSize(
            width: (probe.displaySize.width * factor + 2 * padding).rounded(),
            height: (probe.displaySize.height * factor + 2 * padding).rounded()
        ))
    }

    // MARK: - Schermafbeelding en opname

    private func takeScreenshot() {
        guard let device, let pixelBuffer = session?.frameTap.latestPixelBuffer else {
            toast = Toast(text: ScreenshotError.noImage.localizedDescription)
            return
        }
        do {
            let url = try ScreenshotService.capture(
                pixelBuffer: pixelBuffer,
                style: frameStyle(for: device),
                background: background,
                deviceName: device.name,
                copyToClipboard: copyScreenshotToClipboard
            )
            toast = Toast(
                text: copyScreenshotToClipboard ? "Schermafbeelding bewaard en gekopieerd" : "Schermafbeelding bewaard",
                url: url
            )
        } catch {
            toast = Toast(text: error.localizedDescription)
        }
    }

    private func toggleRecording() {
        if recorder == nil {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private func startRecording() {
        guard let device, let session, let pixelBuffer = session.frameTap.latestPixelBuffer else {
            toast = Toast(text: RecorderError.noImage.localizedDescription)
            return
        }
        let style = frameStyle(for: device)
        // Video kent geen transparantie: dan op zwart.
        let backgroundColor = background == .transparent ? Color.black : background.color
        let screenSize = PixelBufferConverter.visibleImage(pixelBuffer).extent.size
        let natural = FramedCanvas.naturalOutputSize(style: style, screenSize: screenSize,
                                                     paddingFraction: 0.05, maxLongSide: 2160)
        let outputSize = natural.size
        let outputPadding = natural.padding

        guard let initialLayers = RecordingLayers.make(
            style: style, background: backgroundColor, outputSize: outputSize,
            padding: outputPadding, screenSize: screenSize
        ) else {
            toast = Toast(text: RecorderError.cannotRecord.localizedDescription)
            return
        }

        do {
            let name = "\(OutputFolders.safeName(device.name)) \(OutputFolders.timestamp()).mov"
            let url = try OutputFolders.fileURL(in: .moviesDirectory, fileName: name)
            let newRecorder = try FramedRecorder(
                url: url,
                outputSize: outputSize,
                initialLayers: initialLayers,
                makeLayers: { size in
                    RecordingLayers.make(style: style, background: backgroundColor, outputSize: outputSize,
                                         padding: outputPadding, screenSize: size)
                }
            )
            session.frameTap.setConsumer { [weak newRecorder] pixelBuffer in
                newRecorder?.append(pixelBuffer)
            }
            recorder = newRecorder
            recordingStarted = Date()
        } catch {
            toast = Toast(text: error.localizedDescription)
        }
    }

    private func stopRecording() {
        guard let current = recorder else { return }
        session?.frameTap.setConsumer(nil)
        recorder = nil
        recordingStarted = nil

        current.finish { result in
            Task { @MainActor in
                switch result {
                case .success(let url):
                    toast = Toast(text: "Opname bewaard", url: url)
                case .failure(let error):
                    toast = Toast(text: error.localizedDescription)
                }
            }
        }
    }

    nonisolated static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Verbinden

    private var connectionKey: String {
        guard let device else { return "geen" }
        return "\(device.id)|\(device.statusMessage ?? "gereed")"
    }

    private func connect() {
        guard let device else {
            stopRecording()
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
            if demoMode?.serial != device.id.rawID {
                demoMode = androidDiscovery.makeDemoMode(serial: device.id.rawID)
            }
            do {
                let source = try androidDiscovery.makeSource(serial: device.id.rawID)
                current.start(with: source)
            } catch {
                current.markUnavailable(error.localizedDescription)
            }
        }
    }
}

/// Korte melding onderin het venster.
private struct Toast: Equatable {
    let id = UUID()
    let text: String
    var url: URL? = nil
}

/// Uitleg als QuickTime Player waarschijnlijk het iPhone-scherm bezet houdt.
private struct QuickTimeCard: View {
    let quit: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 30))
            Text("QuickTime Player is geopend")
                .font(.headline)
            Text("QuickTime kan het scherm van je iPhone bezet houden. Sluit QuickTime; dit venster verbindt daarna vanzelf opnieuw.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Sluit QuickTime", action: quit)
                    .buttonStyle(.borderedProminent)
                Button("Opnieuw proberen", action: retry)
            }
        }
        .padding(18)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
