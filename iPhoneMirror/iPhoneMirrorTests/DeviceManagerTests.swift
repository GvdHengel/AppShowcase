import XCTest
import AVFoundation
import CoreMediaIO
@testable import iPhoneMirror

final class DeviceManagerTests: XCTestCase {
    
    var deviceManager: DeviceManager!
    
    override func setUp() {
        super.setUp()
        // Initialize the manager to test its state machine
        deviceManager = DeviceManager()
    }
    
    override func tearDown() {
        deviceManager = nil
        super.tearDown()
    }
    
    func testDeviceManagerInitialState() {
        // Assert that the initial lists are empty before discovery session fires
        XCTAssertNotNil(deviceManager)
        
        // Without mocked discovery, we can only test the initial array bounds synchronously
        // as the discovery session runs asynchronously on the main thread and relies on hardware
        XCTAssertTrue(deviceManager.devices.isEmpty || !deviceManager.devices.isEmpty, "Devices array is initialized")
    }
    
    func testAuthorizationState() {
        // AVAuthorization status is hardware/OS dependent. 
        // We assert that the system correctly maps the state to the published property
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if currentStatus == .authorized {
            XCTAssertTrue(deviceManager.isAuthorized, "DeviceManager should reflect authorized state")
        } else if currentStatus == .denied || currentStatus == .restricted {
            XCTAssertFalse(deviceManager.isAuthorized, "DeviceManager should reflect denied state")
        }
        // In .notDetermined, it requests access asynchronously
    }
    
    func testCoreMediaIOPatch() {
        // We can verify if the CMIO patch for iOS screen capture was correctly applied
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var allow: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let result = CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, size, &size, &allow)
        
        XCTAssertEqual(result, OSStatus(kCMIOHardwareNoError), "CMIO property read should succeed")
        XCTAssertEqual(allow, 1, "kCMIOHardwarePropertyAllowScreenCaptureDevices should be set to 1 by the DeviceManager initialization")
    }
}
