import AVFoundation
import Combine
import CoreMediaIO

struct iOSDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    var isConnected: Bool
    let isScreenMirror: Bool
    let captureDevice: AVCaptureDevice
    
    static func == (lhs: iOSDevice, rhs: iOSDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class DeviceManager: ObservableObject {
    @Published var devices: [iOSDevice] = []
    @Published var cameraAuthorized: Bool = false
    
    /// Android device manager (ADB-based)
    let adbManager = ADBManager()
    
    /// Subscriptions for forwarding nested ObservableObject changes
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // CRITICAL: Forward adbManager changes to our objectWillChange.
        // SwiftUI only observes direct @Published properties, not nested ObservableObjects.
        adbManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // CRITICAL: Enable CoreMediaIO DAL plugins BEFORE any device discovery.
        // Without this, the iPhone screen mirroring device won't appear.
        enableCMIODALDevices()
        
        setupNotifications()
        requestAccessThenDiscover()
    }
    
    /// Enable CoreMediaIO DAL devices including screen capture/mirroring devices.
    /// This must be called before AVCaptureDevice discovery to make the
    /// iPhone screen mirroring device (QuickTime protocol) appear.
    private func enableCMIODALDevices() {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &property,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        print("[DeviceManager] 🔧 CMIOHardwarePropertyAllowScreenCaptureDevices → \(status == noErr ? "✅ enabled" : "❌ failed (status: \(status))")")
        
        // Also list ALL CMIO devices for diagnostics
        listAllCMIODevices()
    }
    
    /// Enumerate CoreMediaIO devices directly (bypassing AVFoundation) for diagnostics
    private func listAllCMIODevices() {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var dataSize: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("[DeviceManager] ⚠️ Failed to get CMIO device count: \(status)")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        print("[DeviceManager] 🔍 CMIO direct enumeration: \(deviceCount) device(s) total")
        
        var deviceIDs = [CMIODeviceID](repeating: 0, count: deviceCount)
        var dataUsed: UInt32 = 0
        
        status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            dataSize,
            &dataUsed,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("[DeviceManager] ⚠️ Failed to get CMIO devices: \(status)")
            return
        }
        
        for deviceID in deviceIDs {
            let name = getCMIODeviceName(deviceID)
            print("[DeviceManager]   CMIO device ID=\(deviceID): '\(name)'")
        }
    }
    
    /// Get the name of a CMIO device
    private func getCMIODeviceName(_ deviceID: CMIODeviceID) -> String {
        var nameAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var nameRef: Unmanaged<CFString>?
        let nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var dataUsed: UInt32 = 0
        
        let status = CMIOObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0, nil,
            nameSize,
            &dataUsed,
            &nameRef
        )
        
        guard status == noErr, let ref = nameRef else {
            return "Unknown (status: \(status))"
        }
        return ref.takeUnretainedValue() as String
    }
    
    /// Request camera permission FIRST, then discover devices.
    private func requestAccessThenDiscover() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("[DeviceManager] 📷 Camera auth status: \(currentStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        
        switch currentStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.cameraAuthorized = true
                self.refreshDevices()
            }
            
        case .notDetermined:
            print("[DeviceManager] 📷 Requesting camera access...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print("[DeviceManager] 📷 Camera access: \(granted ? "✅ GRANTED" : "❌ DENIED")")
                DispatchQueue.main.async {
                    self?.cameraAuthorized = granted
                    if granted {
                        // Re-enumerate CMIO devices now that we have permission
                        self?.listAllCMIODevices()
                        self?.refreshDevices()
                    }
                }
            }
            
        case .denied, .restricted:
            print("[DeviceManager] ⚠️ Camera access denied/restricted.")
            DispatchQueue.main.async { self.cameraAuthorized = false }
            
        @unknown default:
            break
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice {
                print("[DeviceManager] 🔌 Connected: '\(device.localizedName)' modelID='\(device.modelID)' mediaType=\(device.activeFormat.mediaType.rawValue)")
            }
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            print("[DeviceManager] ⏏️ Device disconnected")
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
    }
    
    /// Detects connected iOS devices by querying AVFoundation.
    func refreshDevices() {
        print("[DeviceManager] 🔍 refreshDevices()")
        
        // 1. Screen mirroring: .external + .muxed
        let muxedSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        print("[DeviceManager]   (.external, .muxed): \(muxedSession.devices.count)")
        for d in muxedSession.devices {
            print("[DeviceManager]     → '\(d.localizedName)' model='\(d.modelID)' formats=\(d.formats.count)")
        }
        
        // 2. Video devices: .external + .video
        let videoSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        print("[DeviceManager]   (.external, .video): \(videoSession.devices.count)")
        for d in videoSession.devices {
            print("[DeviceManager]     → '\(d.localizedName)' model='\(d.modelID)' formats=\(d.formats.count)")
        }
        
        // 3. All external: .external + nil
        let allSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: nil,
            position: .unspecified
        )
        print("[DeviceManager]   (.external, nil): \(allSession.devices.count)")
        for d in allSession.devices {
            print("[DeviceManager]     → '\(d.localizedName)' model='\(d.modelID)' mediaType='\(d.activeFormat.mediaType.rawValue)' formats=\(d.formats.count)")
        }
        
        // Build list: prefer muxed (screen), then fallback to all external iPhones
        var result: [iOSDevice] = []
        var seenIds = Set<String>()
        
        // Add muxed devices first (screen mirroring)
        for device in muxedSession.devices where isIOSDevice(device) {
            if seenIds.insert(device.uniqueID).inserted {
                result.append(makeDevice(device, isScreenMirror: true))
                print("[DeviceManager]   ✅ SCREEN MIRROR: '\(device.localizedName)'")
            }
        }
        
        // Add remaining external devices (camera fallback)
        for device in allSession.devices where isIOSDevice(device) {
            if seenIds.insert(device.uniqueID).inserted {
                result.append(makeDevice(device, isScreenMirror: false))
                print("[DeviceManager]   ✅ CAMERA: '\(device.localizedName)'")
            }
        }
        
        print("[DeviceManager]   📱 Total: \(result.count) (screen: \(result.filter(\.isScreenMirror).count), camera: \(result.filter { !$0.isScreenMirror }.count))")
        self.devices = result
    }
    
    private func makeDevice(_ device: AVCaptureDevice, isScreenMirror: Bool) -> iOSDevice {
        iOSDevice(
            id: device.uniqueID,
            name: isScreenMirror 
                ? device.localizedName.replacingOccurrences(of: " Camera", with: " Scherm")
                : device.localizedName,
            model: device.modelID.isEmpty ? "iPhone" : device.modelID,
            isConnected: device.isConnected,
            isScreenMirror: isScreenMirror,
            captureDevice: device
        )
    }
    
    private func isIOSDevice(_ device: AVCaptureDevice) -> Bool {
        let lowerModel = device.modelID.lowercased()
        let lowerName = device.localizedName.lowercased()
        
        let hasIOSKeyword = lowerModel.contains("iphone") || lowerModel.contains("ipad") || lowerModel.contains("ios") ||
                            lowerName.contains("iphone") || lowerName.contains("ipad") || lowerName.contains("ios")
                            
        let hasAppleKeyword = lowerModel.contains("apple") || lowerName.contains("apple")
        
        return hasIOSKeyword || hasAppleKeyword
    }
}
