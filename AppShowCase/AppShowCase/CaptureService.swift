import AVFoundation
import Combine

class CaptureService: ObservableObject {
    @Published var rotationAngle: Double = 0
    @Published var isRecording: Bool = false
    @Published var errorMessage: String? = nil
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.appshowcase.session")
    
    init() {
        setupErrorHandling()
    }
    
    private func setupErrorHandling() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
                DispatchQueue.main.async {
                    self.errorMessage = "Stream onderbroken: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Requests video access and starts the AVCaptureSession safely on a background thread.
    func startSession(for device: AVCaptureDevice) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.errorMessage = "Geen toegang tot camera. Controleer macOS Privacy Settings."
                }
                return
            }
            
            // Dispatch session configuration and start to serial background queue
            self.sessionQueue.async {
                self.configureSession(with: device)
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }
    
    /// Stops the AVCaptureSession safely on the background thread.
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    private func configureSession(with device: AVCaptureDevice) {
        session.beginConfiguration()
        
        // Remove any old inputs
        for input in session.inputs {
            session.removeInput(input)
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Kon iPhone niet toevoegen als invoer."
                }
                session.commitConfiguration()
                return
            }
        } catch {
            DispatchQueue.main.async {
                // Typical error when the device is locked or "Trust this computer" wasn't clicked
                self.errorMessage = "Invoer geweigerd. Zorg dat de iPhone is ontgrendeld en u de Mac vertrouwt."
            }
            session.commitConfiguration()
            return
        }
        
        // iPhone levert native resolutie via QuickTime protocol; .high volgt het device's activeFormat
        session.sessionPreset = .high
        
        // Deliberately NOT adding AVCaptureAudioDataOutput here to prevent audio echo 
        
        session.commitConfiguration()
        DispatchQueue.main.async {
            self.errorMessage = nil // Clear previous errors if successful
        }
    }
}
