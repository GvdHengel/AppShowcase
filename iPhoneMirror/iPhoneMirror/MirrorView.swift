import SwiftUI
import AVFoundation

struct MirrorView: NSViewRepresentable {
    var device: AVCaptureDevice?
    @Binding var isLocked: Bool
    @Binding var videoSize: CGSize?
    
    func makeNSView(context: Context) -> CustomVideoView {
        let view = CustomVideoView()
        view.onStateChange = { locked in
            DispatchQueue.main.async {
                self.isLocked = locked
            }
        }
        view.onVideoSizeChange = { size in
            DispatchQueue.main.async {
                self.videoSize = size
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: CustomVideoView, context: Context) {
        nsView.updateDevice(device)
    }
}

class CustomVideoView: NSView {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentDevice: AVCaptureDevice?
    
    var onStateChange: ((Bool) -> Void)?
    var onVideoSizeChange: ((CGSize?) -> Void)?
    
    // Retry logic
    private var retryCount = 0
    private var retryTimer: Timer?
    private let maxRetries = 5
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateDevice(_ device: AVCaptureDevice?) {
        guard device != currentDevice else { return }
        currentDevice = device
        
        stopSession()
        
        if let newDevice = device {
            retryCount = 0
            onStateChange?(false)
            startSession(with: newDevice)
        } else {
            onVideoSizeChange?(nil)
        }
    }
    
    private func startSession(with device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                // Konfigureer de hoogst mogelijke framerate (doelbewust voor 60FPS mirroring)
                do {
                    try device.lockForConfiguration()
                    if let highestFormat = device.formats.max(by: { 
                        let fps1 = $0.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })?.maxFrameRate ?? 0
                        let fps2 = $1.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })?.maxFrameRate ?? 0
                        return fps1 < fps2
                    }) {
                        device.activeFormat = highestFormat
                        
                        // Forceer min/max duration voor zo hoog mogelijke framerate (voorkom drops)
                        if let bestRange = highestFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                            device.activeVideoMinFrameDuration = bestRange.minFrameDuration
                            device.activeVideoMaxFrameDuration = bestRange.minFrameDuration
                        }
                        
                        let dimensions = CMVideoFormatDescriptionGetDimensions(highestFormat.formatDescription)
                        let size = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                        self.onVideoSizeChange?(size)
                    }
                    device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for frame rate configuration: \(error)")
                }
                
                session.addInput(input)
            } else {
                print("Cannot add input")
                scheduleRetry(with: device)
                return
            }
            
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspect
            layer.frame = self.bounds
            self.layer?.addSublayer(layer)
            self.previewLayer = layer
            self.captureSession = session
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sessionRuntimeError),
                name: AVCaptureSession.runtimeErrorNotification,
                object: session
            )
            
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.retryCount = 0
                self?.onStateChange?(false)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
            
            retryTimer?.invalidate()
            
        } catch {
            print("Error creating capture input: \(error)")
            scheduleRetry(with: device)
        }
    }
    
    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("Session runtime error: \(error.localizedDescription)")
        if let device = currentDevice {
            scheduleRetry(with: device)
        }
    }
    
    private func scheduleRetry(with device: AVCaptureDevice) {
        guard retryCount < maxRetries else {
            print("Max retries (\(maxRetries)) reached for device.")
            onStateChange?(true)
            return
        }
        
        retryCount += 1
        let delay: TimeInterval = 2.0
        print("Retrying connection in \(delay) seconds... (Attempt \(retryCount)/\(maxRetries))")
        
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.stopSession()
            self?.startSession(with: device)
        }
    }
    
    private func stopSession() {
        retryTimer?.invalidate()
        if let session = captureSession {
            NotificationCenter.default.removeObserver(self)
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        captureSession = nil
    }
    
    override func layout() {
        super.layout()
        previewLayer?.frame = self.bounds
    }
}
