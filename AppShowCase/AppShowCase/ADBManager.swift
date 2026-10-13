import Foundation
import Combine

// MARK: - Android Device Model

struct AndroidDevice: Identifiable, Hashable {
    let id: String           // ADB serial number
    var name: String         // Model name (ro.product.model)
    let serialNumber: String
    var isConnected: Bool
    
    static func == (lhs: AndroidDevice, rhs: AndroidDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ADB Manager

class ADBManager: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    
    private var trackProcess: Process?
    private var trackPipe: Pipe?
    private var isTracking = false
    private let queue = DispatchQueue(label: "com.appshowcase.adb", qos: .userInitiated)
    private let scrcpyQueue = DispatchQueue(label: "com.appshowcase.scrcpy", qos: .userInitiated)
    
    /// Path to the bundled adb binary
    var adbPath: String? {
        // Try standard Bundle lookup first
        if let path = Bundle.main.path(forResource: "adb", ofType: nil) {
            return path
        }
        // Fallback: look directly in the Resources directory
        if let resourceURL = Bundle.main.resourceURL {
            let directPath = resourceURL.appendingPathComponent("adb").path
            if FileManager.default.fileExists(atPath: directPath) {
                return directPath
            }
            // Also try inside a Resources subdirectory (folder reference)
            let subDirPath = resourceURL.appendingPathComponent("Resources/adb").path
            if FileManager.default.fileExists(atPath: subDirPath) {
                return subDirPath
            }
        }
        print("[ADBManager] ❌ adb not found. Bundle resource URL: \(Bundle.main.resourceURL?.path ?? "nil")")
        return nil
    }
    
    /// Path to the bundled scrcpy-server
    var scrcpyServerPath: String? {
        if let path = Bundle.main.path(forResource: "scrcpy-server", ofType: nil) {
            return path
        }
        if let resourceURL = Bundle.main.resourceURL {
            let directPath = resourceURL.appendingPathComponent("scrcpy-server").path
            if FileManager.default.fileExists(atPath: directPath) {
                return directPath
            }
            let subDirPath = resourceURL.appendingPathComponent("Resources/scrcpy-server").path
            if FileManager.default.fileExists(atPath: subDirPath) {
                return subDirPath
            }
        }
        print("[ADBManager] ❌ scrcpy-server not found. Bundle resource URL: \(Bundle.main.resourceURL?.path ?? "nil")")
        return nil
    }
    
    init() {
        // Log bundle info for debugging
        print("[ADBManager] 📦 Bundle path: \(Bundle.main.bundlePath)")
        if let resourceURL = Bundle.main.resourceURL {
            print("[ADBManager] 📦 Resource URL: \(resourceURL.path)")
            // List files in Resources for debugging
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourceURL.path) {
                let relevant = contents.filter { $0.contains("adb") || $0.contains("scrcpy") || $0 == "Resources" }
                print("[ADBManager] 📦 Relevant resources: \(relevant)")
            }
        }
        
        guard let adb = adbPath else {
            print("[ADBManager] ❌ adb binary not found in app bundle")
            return
        }
        
        // Ensure adb is executable (Xcode may strip +x during copy)
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: adb) {
            print("[ADBManager] ✅ adb binary found and executable: \(adb)")
        } else {
            print("[ADBManager] ⚠️ adb found but not executable, setting +x: \(adb)")
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb)
        }
        
        if let server = scrcpyServerPath {
            print("[ADBManager] ✅ scrcpy-server found: \(server)")
        } else {
            print("[ADBManager] ⚠️ scrcpy-server not found in app bundle")
        }
        
        startTracking()
    }
    
    deinit {
        stopTracking()
    }
    
    // MARK: - Device Tracking (adb track-devices)
    
    /// Start continuous device tracking using `adb track-devices`.
    /// This is more efficient than polling: ADB sends updates only when devices change.
    func startTracking() {
        guard !isTracking else { return }
        guard let adb = adbPath else { return }
        
        isTracking = true
        print("[ADBManager] 🔍 Starting adb track-devices...")
        
        // First do an initial scan
        queue.async { [weak self] in
            self?.refreshDevicesSync()
        }
        
        // Then start the continuous tracker
        queue.async { [weak self] in
            self?.runTrackDevices(adbPath: adb)
        }
    }
    
    func stopTracking() {
        isTracking = false
        trackProcess?.terminate()
        trackProcess = nil
        print("[ADBManager] ⏹ Stopped tracking")
    }
    
    /// Run `adb track-devices` which keeps a persistent connection to the ADB server.
    /// The server pushes updates whenever devices connect/disconnect.
    private func runTrackDevices(adbPath: String) {
        while isTracking {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["track-devices"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            trackProcess = process
            trackPipe = pipe
            
            do {
                try process.run()
            } catch {
                print("[ADBManager] ❌ Failed to start adb track-devices: \(error)")
                Thread.sleep(forTimeInterval: 3)
                continue
            }
            
            let handle = pipe.fileHandleForReading
            
            // Read data in chunks; each chunk from track-devices indicates a state change
            while isTracking && process.isRunning {
                let data = handle.availableData
                if data.isEmpty {
                    // EOF — process ended
                    break
                }
                
                // Parse the track-devices output
                if let output = String(data: data, encoding: .utf8) {
                    print("[ADBManager] 📡 track-devices update: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                
                // Refresh full device list on any change
                refreshDevicesSync()
            }
            
            process.waitUntilExit()
            
            if isTracking {
                print("[ADBManager] ⚠️ adb track-devices ended, restarting in 2s...")
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }
    
    // MARK: - Device Enumeration
    
    /// Synchronously refresh the device list using `adb devices -l`
    private func refreshDevicesSync() {
        guard adbPath != nil else { return }
        
        let output = runADBCommand(arguments: ["devices", "-l"])
        guard let output = output else { return }
        
        var newDevices: [AndroidDevice] = []
        
        // Parse output: each line after "List of devices attached" is a device
        // Format: SERIAL_NUMBER    device usb:XXX product:YYY model:ZZZ device:AAA transport_id:N
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip header and empty lines
            guard !trimmed.isEmpty,
                  !trimmed.starts(with: "List of"),
                  !trimmed.starts(with: "*") else { continue }
            
            // ADB output uses tabs between fields — split and filter empty strings
            let parts = trimmed.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            
            let serial = parts[0]
            let status = parts[1]
            
            // Only include authorized ("device") devices
            guard status == "device" else {
                print("[ADBManager]   ⚠️ '\(serial)' status: \(status) (not yet authorized)")
                continue
            }
            
            // Extract model name from the properties
            var modelName = serial // Fallback
            for part in parts {
                if part.starts(with: "model:") {
                    modelName = String(part.dropFirst(6)).replacingOccurrences(of: "_", with: " ")
                }
            }
            
            let device = AndroidDevice(
                id: serial,
                name: modelName,
                serialNumber: serial,
                isConnected: true
            )
            newDevices.append(device)
            print("[ADBManager]   ✅ Android: '\(device.name)' serial=\(serial)")
        }
        
        print("[ADBManager]   📱 Android total: \(newDevices.count)")
        
        DispatchQueue.main.async { [weak self] in
            self?.devices = newDevices
        }
    }
    
    // MARK: - Scrcpy Server Management
    
    /// Push the scrcpy-server to the Android device and start it.
    /// Returns the local port number for the video stream socket.
    func startScrcpyServer(serial: String, completion: @escaping (Result<UInt16, Error>) -> Void) {
        guard let adb = adbPath, let server = scrcpyServerPath else {
            completion(.failure(ADBError.binaryNotFound))
            return
        }
        
        scrcpyQueue.async { [weak self] in
            guard let self = self else { return }
            
            let localPort: UInt16 = 27183
            
            // 0. Kill any old scrcpy-server process on the device
            print("[ADBManager] 🧹 Cleaning up old scrcpy instances...")
            _ = self.runADBCommand(arguments: ["-s", serial, "shell", "pkill", "-f", "scrcpy"])
            // Remove old tunnels
            _ = self.runADBCommand(arguments: ["-s", serial, "forward", "--remove-all"])
            _ = self.runADBCommand(arguments: ["-s", serial, "reverse", "--remove-all"])
            // Give the old server time to die
            Thread.sleep(forTimeInterval: 0.5)
            
            // 1. Push scrcpy-server to device
            print("[ADBManager] 📤 Pushing scrcpy-server to device \(serial)...")
            let pushResult = self.runADBCommand(arguments: [
                "-s", serial,
                "push", server, "/data/local/tmp/scrcpy-server.jar"
            ])
            
            if pushResult == nil {
                completion(.failure(ADBError.pushFailed))
                return
            }
            print("[ADBManager] ✅ scrcpy-server pushed successfully")
            
            // 2. Set up forward tunnel: our local port → device's abstract socket
            // With tunnel_forward=true, the server LISTENS on localabstract:scrcpy
            // and we connect through adb forward
            print("[ADBManager] 🔗 Setting up adb forward tunnel on port \(localPort)...")
            let forwardResult = self.runADBCommand(arguments: [
                "-s", serial,
                "forward", "tcp:\(localPort)", "localabstract:scrcpy"
            ])
            
            if forwardResult == nil {
                print("[ADBManager] ❌ adb forward failed")
                completion(.failure(ADBError.tunnelFailed))
                return
            }
            print("[ADBManager] ✅ Forward tunnel established")
            
            // 3. Start the scrcpy server on the device
            print("[ADBManager] 🚀 Starting scrcpy server on device...")
            let serverProcess = Process()
            serverProcess.executableURL = URL(fileURLWithPath: adb)
            serverProcess.arguments = [
                "-s", serial,
                "shell",
                "CLASSPATH=/data/local/tmp/scrcpy-server.jar",
                "app_process", "/",
                "com.genymobile.scrcpy.Server",
                "3.1",              // server version
                "scid=-1",          // random scid
                "tunnel_forward=true",
                "audio=false",
                "control=false",
                "clipboard_autosync=false",
                "send_device_meta=false",
                "send_frame_meta=false",
                "send_dummy_byte=false",
                "video_codec=h264",
                "max_size=1080", // 1080 max size to prevent memory overload on older devices
                "max_fps=60",
                "video_bit_rate=8000000" // Lower down to 8 Mbps just to test stability
            ]
            
            let serverPipe = Pipe()
            serverProcess.standardOutput = serverPipe
            serverProcess.standardError = serverPipe
            
            do {
                try serverProcess.run()
            } catch {
                print("[ADBManager] ❌ Failed to start scrcpy server: \(error)")
                completion(.failure(ADBError.serverStartFailed))
                return
            }
            
            // Give the server time to start and bind its socket
            Thread.sleep(forTimeInterval: 2.0)
            
            // Read any initial output for diagnostics
            let serverData = serverPipe.fileHandleForReading.availableData
            let serverOutput = String(data: serverData, encoding: .utf8) ?? ""
            if !serverOutput.isEmpty {
                print("[ADBManager] 📋 Server output: \(serverOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            
            // Check if server crashed
            if serverOutput.contains("ERROR") || !serverProcess.isRunning {
                print("[ADBManager] ❌ Scrcpy server failed to start")
                completion(.failure(ADBError.serverStartFailed))
                return
            }
            
            print("[ADBManager] ✅ Scrcpy server started, video stream on port \(localPort)")
            completion(.success(localPort))
        }
    }
    
    /// Stop the scrcpy server and clean up tunnels for a device
    func stopScrcpyServer(serial: String) {
        scrcpyQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("[ADBManager] 🛑 Stopping scrcpy for \(serial)...")
            
            // Remove reverse tunnel
            _ = self.runADBCommand(arguments: ["-s", serial, "reverse", "--remove", "localabstract:scrcpy"])
            
            // Also try removing forward tunnel
            _ = self.runADBCommand(arguments: ["-s", serial, "forward", "--remove", "tcp:27183"])
            
            print("[ADBManager] ✅ Cleanup complete for \(serial)")
        }
    }
    
    // MARK: - ADB Cleanup
    
    /// Kill the ADB server when the app exits to prevent zombie processes
    func killADBServer() {
        guard adbPath != nil else { return }
        
        print("[ADBManager] 🧹 Killing ADB server...")
        stopTracking()
        _ = runADBCommand(arguments: ["kill-server"])
        print("[ADBManager] ✅ ADB server killed")
    }
    
    // MARK: - Helpers
    
    /// Run an ADB command synchronously and return stdout as String
    @discardableResult
    private func runADBCommand(arguments: [String]) -> String? {
        guard let adb = adbPath else {
            print("[ADBManager] ❌ adbPath is nil, cannot run: adb \(arguments.joined(separator: " "))")
            return nil
        }
        
        print("[ADBManager] 🔧 Running: adb \(arguments.joined(separator: " "))")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[ADBManager] ❌ Process launch failed: adb \(arguments.joined(separator: " ")): \(error)")
            return nil
        }
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[ADBManager] 📋 stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            print("[ADBManager] ⚠️ Exit code \(exitCode) for: adb \(arguments.joined(separator: " "))")
            print("[ADBManager] 📋 stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            // Still return stdout even on non-zero exit (adb sometimes does this)
        }
        
        return stdout
    }
}

// MARK: - Error Types

enum ADBError: LocalizedError {
    case binaryNotFound
    case pushFailed
    case tunnelFailed
    case serverStartFailed
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "ADB of scrcpy-server binary niet gevonden in de app bundle."
        case .pushFailed: return "Kan scrcpy-server niet naar het Android-apparaat pushen."
        case .tunnelFailed: return "Kan geen ADB-tunnel opzetten."
        case .serverStartFailed: return "Kan de scrcpy-server niet starten op het Android-apparaat."
        case .connectionFailed: return "Kan geen verbinding maken met de videostream."
        }
    }
}
