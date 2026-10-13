import AppKit
import AVFoundation
import SwiftUI

/// Toont een `AVSampleBufferDisplayLayer` in SwiftUI.
struct VideoDisplayView: NSViewRepresentable {
    let videoLayer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> VideoLayerHostView {
        VideoLayerHostView(videoLayer: videoLayer)
    }

    func updateNSView(_ view: VideoLayerHostView, context: Context) {
        view.setVideoLayer(videoLayer)
    }
}

final class VideoLayerHostView: NSView {
    private var videoLayer: AVSampleBufferDisplayLayer

    init(videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) wordt niet gebruikt")
    }

    func setVideoLayer(_ newLayer: AVSampleBufferDisplayLayer) {
        guard newLayer !== videoLayer else { return }
        videoLayer.removeFromSuperlayer()
        videoLayer = newLayer
        layer?.addSublayer(newLayer)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
