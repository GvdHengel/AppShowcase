import AppKit
import AVFoundation
import Observation

/// Toestand van het spiegelen, zoals getoond in het toestelvenster.
enum MirrorState: Equatable {
    case idle
    case connecting
    case mirroring
    /// Tijdelijk geen beeld (bijv. toestel vergrendeld); herstelt vanzelf zodra er frames komen.
    case waiting(String)
    /// Echte fout; de gebruiker kan opnieuw proberen.
    case failed(String)
}

/// Verbindt één beeldbron met één weergave-layer, voor één toestelvenster.
@MainActor
@Observable
final class MirrorSession {
    let deviceID: DeviceID
    private(set) var state: MirrorState = .idle
    /// Pixelafmetingen van het laatste frame; bepaalt beeldverhouding en staand/liggend.
    private(set) var videoSize: CGSize?

    /// De layer waarop frames getoond worden. Thread-safe genoeg om vanaf de bron-queue te vullen.
    @ObservationIgnored let displayLayer = AVSampleBufferDisplayLayer()
    /// Laatste frame (schermafbeelding) en doorgifte naar de opname.
    @ObservationIgnored let frameTap = FrameTap()
    @ObservationIgnored private var source: FrameSource?
    @ObservationIgnored private var noSignalTask: Task<Void, Never>?

    /// Na zoveel seconden zonder eerste frame tonen we een hint.
    private let noSignalDelay: Duration = .seconds(6)

    init(deviceID: DeviceID) {
        self.deviceID = deviceID
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
    }

    func start(with newSource: FrameSource) {
        stop()
        source = newSource
        state = .connecting

        let sink = DisplayLayerSink(layer: displayLayer)
        let tap = frameTap
        newSource.frameHandler = { sampleBuffer in
            MirrorSession.enqueue(sampleBuffer, on: sink.layer)
            tap.receive(sampleBuffer)
        }
        newSource.eventHandler = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        newSource.start()
        scheduleNoSignalHint()
    }

    func stop() {
        noSignalTask?.cancel()
        noSignalTask = nil
        if let source {
            source.frameHandler = nil
            source.eventHandler = nil
            source.stop()
        }
        source = nil
        frameTap.clear()
        clearDisplay()
        state = .idle
    }

    /// Voor toestellen zonder (nog) ondersteunde bron, zoals demo-toestellen.
    func markUnavailable(_ reason: String) {
        stop()
        state = .waiting(reason)
    }

    // MARK: - Intern

    private func handle(_ event: SourceEvent) {
        switch event {
        case .started:
            break // we wachten op het eerste frame
        case .videoSizeChanged(let size):
            videoSize = size
            state = .mirroring
            noSignalTask?.cancel()
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func scheduleNoSignalHint() {
        noSignalTask?.cancel()
        let delay = noSignalDelay
        noSignalTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.state == .connecting else { return }
            self.state = .waiting("Nog geen beeld. Ontgrendel het toestel en controleer de USB-kabel.")
        }
    }

    private func clearDisplay() {
        if #available(macOS 15.0, *) {
            displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        } else {
            displayLayer.flushAndRemoveImage()
        }
    }

    nonisolated static func enqueue(_ sampleBuffer: CMSampleBuffer, on layer: AVSampleBufferDisplayLayer) {
        if #available(macOS 15.0, *) {
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sampleBuffer)
        } else {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sampleBuffer)
        }
    }
}

/// `AVSampleBufferDisplayLayer` mag vanaf een achtergrond-queue gevuld worden, maar is niet als
/// `Sendable` gemarkeerd. Dit doosje maakt die (gedocumenteerde) uitzondering expliciet.
private final class DisplayLayerSink: @unchecked Sendable {
    let layer: AVSampleBufferDisplayLayer

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }
}
