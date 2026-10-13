import AVFoundation

/// Beeldbron voor een via USB aangesloten iPhone/iPad (QuickTime-protocol via AVFoundation).
final class IOSCaptureSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    var frameHandler: (@Sendable (CMSampleBuffer) -> Void)?
    var eventHandler: (@Sendable (SourceEvent) -> Void)?

    private let device: AVCaptureDevice
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "nl.gvdhengel.AppShowCase.ios.session")
    private let videoQueue = DispatchQueue(label: "nl.gvdhengel.AppShowCase.ios.video", qos: .userInteractive)

    /// Alleen gebruikt op `videoQueue`.
    private var lastSize: CGSize = .zero
    private var notificationTokens: [NSObjectProtocol] = []

    init(device: AVCaptureDevice) {
        self.device = device
        super.init()
    }

    func start() {
        let token = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.eventHandler?(.failed("De verbinding met het toestel is onderbroken. \(error?.localizedDescription ?? "")"))
        }
        notificationTokens.append(token)

        sessionQueue.async { [self] in
            configureAndStart()
        }
    }

    func stop() {
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()

        // Sessie zelf vastpakken: de bron kan al vrijgegeven zijn als dit blok draait.
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
    }

    // MARK: - Configuratie (op sessionQueue)

    private func configureAndStart() {
        session.beginConfiguration()

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            eventHandler?(.failed("Kan het scherm van het toestel niet openen. Ontgrendel het toestel en kies 'Vertrouw'.\n(\(error.localizedDescription))"))
            return
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            eventHandler?(.failed("Het toestel kan niet als bron worden toegevoegd. Is het al in gebruik door QuickTime of een andere app?"))
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // BGRA: makkelijk voor latere frame-compositie, screenshot en opname.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            eventHandler?(.failed("Kan geen video-uitvoer aanmaken voor dit toestel."))
            return
        }
        session.addOutput(output)
        // Bewust géén audio-uitvoer: voorkomt echo.

        selectBestFormat()
        session.commitConfiguration()

        session.startRunning()
        eventHandler?(.started)
    }

    /// Kiest het formaat met de hoogste framerate (bij gelijkspel: grootste resolutie).
    private func selectBestFormat() {
        let candidates = device.formats.enumerated().map { index, format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return FormatCandidate(index: index, width: dimensions.width, height: dimensions.height, maxFPS: maxFPS)
        }
        guard let best = FormatSelector.best(candidates) else { return }

        do {
            try device.lockForConfiguration()
            let format = device.formats[best.index]
            device.activeFormat = format
            if let range = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                device.activeVideoMinFrameDuration = range.minFrameDuration
            }
            device.unlockForConfiguration()
        } catch {
            print("[IOSCaptureSource] Formaat kiezen mislukt: \(error)")
        }
    }

    // MARK: - Frames (op videoQueue)

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let image = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let size = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))
            if size != lastSize {
                lastSize = size
                eventHandler?(.videoSizeChanged(size))
            }
        }
        SampleBufferTools.markDisplayImmediately(sampleBuffer)
        frameHandler?(sampleBuffer)
    }
}

/// Een beschikbaar capture-formaat, los van AVFoundation zodat de keuze testbaar is.
struct FormatCandidate: Equatable {
    let index: Int
    let width: Int32
    let height: Int32
    let maxFPS: Double
}

enum FormatSelector {
    static func best(_ candidates: [FormatCandidate]) -> FormatCandidate? {
        candidates.max { a, b in
            (a.maxFPS, Int(a.width) * Int(a.height)) < (b.maxFPS, Int(b.width) * Int(b.height))
        }
    }
}
