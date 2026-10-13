import Foundation
import AVFoundation
import CoreMediaIO
import Combine

class DeviceManager: NSObject, ObservableObject {
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDevice: AVCaptureDevice?
    @Published var isAuthorized = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private let discoverySession: AVCaptureDevice.DiscoverySession
    
    override init() {
        // Probeer CoreMediaIO screen capture in te schakelen VOOR DiscoverySession
        DeviceManager.enableCoreMediaIOScreenCapture()
        
        self.discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        
        super.init()
        checkPermissions()
        setupDeviceObservation()
    }
    
    private static func enableCoreMediaIOScreenCapture() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        // Check of de property überhaupt beschikbaar is
        guard CMIOObjectHasProperty(CMIOObjectID(kCMIOObjectSystemObject), &prop) else {
            print("CMIO AllowScreenCaptureDevices property not available on this system.")
            return
        }
        
        var allow: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        let result = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, size, &allow
        )
        
        if result == OSStatus(kCMIOHardwareNoError) {
            print("Successfully enabled CMIO screen capture devices.")
        } else {
            print("CMIO property set returned error \(result) — continuing without it.")
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted {
                        // Herstart de scan na toestemming
                        self.updateDevices(self.discoverySession.devices)
                    }
                }
            }
        default:
            self.isAuthorized = false
        }
    }
    
    private func setupDeviceObservation() {
        // Initiële scan
        updateDevices(discoverySession.devices)
        
        // KVO publisher observation
        discoverySession.publisher(for: \.devices)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDevices in
                self?.updateDevices(newDevices)
            }
            .store(in: &cancellables)
    }
    
    private func updateDevices(_ newDevices: [AVCaptureDevice]) {
        self.devices = newDevices
        
        if self.selectedDevice == nil, let first = newDevices.first {
            self.selectedDevice = first
        } else if let selected = self.selectedDevice, !newDevices.contains(selected) {
            self.selectedDevice = newDevices.first
        }
    }
}
