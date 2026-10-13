import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - NSView met nieuwe macOS 15 renderer API

class AndroidMirrorNSView: NSView {

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
        // Maak een AVSampleBufferDisplayLayer
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Geen synchronizer nodig. De AVSampleBufferDisplayLayer en zijn ingebouwde renderer 
        // renderen the frames direct als kCMSampleAttachmentKey_DisplayImmediately aan staat!

        self.sampleBufferLayer = displayLayer
        layer?.addSublayer(displayLayer)
    }

    private func setupLegacyAPI() {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Geen controlTimebase nodig! 
        // We verwerken live netwerk frames met onnatuurlijke PTS timers.
        // AVSampleBufferDisplayLayer rendert frames met DisplayImmediately 
        // automatisch zo snel mogelijk als we de timebase default op 'nil' laten.

        self.sampleBufferLayer = displayLayer
        layer?.addSublayer(displayLayer)
    }

    // MARK: - Frame ontvangen

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if useNewAPI {
            // Nieuwe API: enqueue via ingebouwde renderer
            guard let displayLayer = sampleBufferLayer else { return }
            if displayLayer.sampleBufferRenderer.status == .failed {
                print("[AndroidMirrorView] ❌ Renderer failed! Error: \(String(describing: displayLayer.sampleBufferRenderer.error))")
                displayLayer.sampleBufferRenderer.flush()
            }
            displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        } else {
            // Legacy API
            guard let displayLayer = sampleBufferLayer else { return }
            if displayLayer.status == .failed {
                print("[AndroidMirrorView] ❌ DisplayLayer failed! Error: \(String(describing: displayLayer.error))")
                displayLayer.flush()
            }
            displayLayer.enqueue(sampleBuffer)
        }
    }

    func flushAll() {
        if useNewAPI {
            sampleBufferLayer?.sampleBufferRenderer.flush()
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
