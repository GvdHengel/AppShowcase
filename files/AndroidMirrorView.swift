import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - NSView met nieuwe macOS 15 renderer API

class AndroidMirrorNSView: NSView {

    // Nieuwe API (macOS 15+): VideoRenderer + RenderSynchronizer
    private let renderer = AVSampleBufferVideoRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()

    // Layer voor weergave
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?

    // Kies de juiste rendering strategie op basis van macOS versie
    private let useNewAPI: Bool

    override init(frame frameRect: NSRect) {
        if #available(macOS 15.0, *) {
            useNewAPI = true
        } else {
            useNewAPI = false
        }
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        if useNewAPI {
            setupNewAPI()
        } else {
            setupLegacyAPI()
        }
    }

    private func setupNewAPI() {
        // Voeg renderer toe aan synchronizer
        synchronizer.addRenderer(renderer)

        // Zet rate op 1.0 (realtime afspelen)
        synchronizer.rate = 1.0

        // Maak een AVSampleBufferDisplayLayer als host voor de renderer
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Gebruik sampleBufferRenderer ipv directe enqueue op de layer
        self.sampleBufferLayer = displayLayer
        layer?.addSublayer(displayLayer)
    }

    private func setupLegacyAPI() {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Stel controlTimebase in voor minimale latency (legacy pad)
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let tb = timebase {
            CMTimebaseSetTime(tb, time: .zero)
            CMTimebaseSetRate(tb, rate: 1.0)
            displayLayer.controlTimebase = tb
        }

        self.sampleBufferLayer = displayLayer
        layer?.addSublayer(displayLayer)
    }

    // MARK: - Frame ontvangen

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if useNewAPI {
            // Nieuwe API: enqueue via renderer
            if renderer.status == .failed {
                renderer.flush()
            }
            renderer.enqueueSampleBuffer(sampleBuffer)
        } else {
            // Legacy API
            guard let displayLayer = sampleBufferLayer else { return }
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            displayLayer.enqueue(sampleBuffer)
        }
    }

    func flushAll() {
        if useNewAPI {
            renderer.flush()
        } else {
            sampleBufferLayer?.flush()
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sampleBufferLayer?.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - SwiftUI wrapper

struct AndroidMirrorView: NSViewRepresentable {
    let client: ScrcpyClient

    func makeNSView(context: Context) -> AndroidMirrorNSView {
        let view = AndroidMirrorNSView()
        // Geef de view door aan de client zodat hij frames kan pushen
        client.mirrorView = view
        return view
    }

    func updateNSView(_ nsView: AndroidMirrorNSView, context: Context) {
        // Client referentie bijwerken als de binding verandert
        client.mirrorView = nsView
    }
}
