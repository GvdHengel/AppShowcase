import SwiftUI
import AVFoundation

struct MirrorView: NSViewRepresentable {
    let session: AVCaptureSession
    @Binding var rotationAngle: Double
    
    func makeNSView(context: Context) -> MirrorNSView {
        let view = MirrorNSView()
        
        // Initialize and attach the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        
        view.layer?.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        
        return view
    }
    
    func updateNSView(_ nsView: MirrorNSView, context: Context) {
        guard let connection = nsView.previewLayer?.connection else { return }
        
        // Safely update the video rotation angle if supported
        if connection.isVideoRotationAngleSupported(CGFloat(rotationAngle)) {
            connection.videoRotationAngle = CGFloat(rotationAngle)
        }
    }
}

/// A base NSView capable of holding our AVCaptureVideoPreviewLayer
class MirrorNSView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        // Ensure the preview layer always matches the view's current bounds
        previewLayer?.frame = bounds
    }
}
