import AVFoundation
import CoreMediaIO
import Observation

/// Vindt via USB aangesloten iPhones/iPads en meldt ze aan de `DeviceRegistry`.
///
/// Werkwijze (lessen uit de prototypes):
/// 1. CoreMediaIO-vlag `AllowScreenCaptureDevices` aanzetten — anders verschijnt het schermdevice niet.
/// 2. Eerst camera-toegang, dan pas ontdekken — zonder toestemming is de lijst leeg.
/// 3. Het scherm is een `.external` device met mediatype `.muxed` (QuickTime-protocol).
@MainActor
@Observable
final class IOSDiscovery {
    enum Authorization: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var authorization: Authorization = .unknown

    @ObservationIgnored private let registry: DeviceRegistry
    @ObservationIgnored private var discoverySession: AVCaptureDevice.DiscoverySession?
    @ObservationIgnored private var devicesObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init(registry: DeviceRegistry) {
        self.registry = registry
        Self.allowScreenCaptureDevices()
        requestAccessThenDiscover()
    }

    /// Het capture-device voor een iOS-toestel uit de registry.
    func captureDevice(for id: DeviceID) -> AVCaptureDevice? {
        guard id.platform == .iOS else { return nil }
        return AVCaptureDevice(uniqueID: id.rawID)
    }

    /// Opnieuw toestemming checken (bijv. nadat de gebruiker Systeeminstellingen heeft aangepast).
    func recheckAuthorization() {
        if authorization != .granted { requestAccessThenDiscover() }
    }

    // MARK: - Toestemming en discovery

    private func requestAccessThenDiscover() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .granted
            startDiscovery()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorization = granted ? .granted : .denied
                    if granted { self?.startDiscovery() }
                }
            }
        default:
            authorization = .denied
        }
    }

    private func startDiscovery() {
        guard discoverySession == nil else { return }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        discoverySession = session

        // De lijst verandert ook vanzelf als het schermdevice (met vertraging) verschijnt.
        devicesObservation = session.observe(\.devices, options: [.initial, .new]) { [weak self] session, _ in
            let infos = session.devices.compactMap(IOSDiscovery.makeInfo)
            Task { @MainActor in self?.registry.replaceDevices(of: .iOS, with: infos) }
        }

        let names = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            notificationTokens.append(token)
        }
    }

    private func refresh() {
        let infos = discoverySession?.devices.compactMap(Self.makeInfo) ?? []
        registry.replaceDevices(of: .iOS, with: infos)
    }

    // MARK: - Hulpfuncties (zonder actor, testbaar)

    nonisolated static func makeInfo(_ device: AVCaptureDevice) -> DeviceInfo? {
        guard device.hasMediaType(.muxed),
              isIOSScreen(modelID: device.modelID, name: device.localizedName, manufacturer: device.manufacturer)
        else { return nil }
        return DeviceInfo(
            id: DeviceID(platform: .iOS, rawID: device.uniqueID),
            name: device.localizedName,
            model: device.modelID
        )
    }

    /// Herkent het schermspiegel-device van een iPhone/iPad/iPod.
    /// Bewust niet breed op "Apple" filteren: dat pakt ook andere Apple-camera's.
    nonisolated static func isIOSScreen(modelID: String, name: String, manufacturer: String) -> Bool {
        let text = "\(modelID) \(name)".lowercased()
        let keywords = ["iphone", "ipad", "ipod", "ios device"]
        return keywords.contains { text.contains($0) }
    }

    /// Zet de CoreMediaIO-vlag die schermcapture-devices (iPhone via USB) zichtbaar maakt.
    nonisolated static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        if status != noErr {
            print("[IOSDiscovery] CoreMediaIO AllowScreenCaptureDevices mislukt: \(status)")
        }
    }
}
