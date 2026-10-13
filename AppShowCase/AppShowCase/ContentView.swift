import SwiftUI
import AVFoundation

enum MirrorStatus: String {
    case searching = "Zoeken…"
    case found = "Gevonden"
    case connecting = "Koppelen…"
    case mirroring = "Gespiegeld"
    case error = "Fout"
}

/// Represents either an iOS or Android device selection
enum SelectedDevice: Hashable {
    case ios(String)       // iOSDevice id
    case android(String)   // AndroidDevice id
}

struct ContentView: View {
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var captureService = CaptureService()
    @StateObject private var scrcpyClient = ScrcpyClient()
    
    @State private var selectedDevice: SelectedDevice?
    @State private var mirrorStatus: MirrorStatus = .searching
    @State private var androidRotationAngle: Double = 0
    @State private var showAndroidHelp = false
    
    enum MirrorMode: String, CaseIterable {
        case h264 = "H.264 (Snel)"
        case mjpeg = "MJPEG (Stabiel)"
    }
    @State private var mirrorMode: MirrorMode = .h264
    @State private var mjpegService: MJPEGScreencapService?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDevice) {
                if !deviceManager.cameraAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Camera-toegang vereist", systemImage: "camera.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("AppShowCase heeft camera-toegang nodig om je iPhone te detecteren. Open Systeeminstellingen → Privacy en beveiliging → Camera.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Open Systeeminstellingen") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8)
                } else {
                    // MARK: - iOS Devices Section
                    Section("iOS") {
                        if deviceManager.devices.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Geen iOS-apparaat", systemImage: "iphone.slash")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Sluit je iPhone/iPad aan via USB.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(deviceManager.devices) { device in
                                HStack {
                                    Label(device.name, systemImage: device.isScreenMirror ? "rectangle.on.rectangle" : "iphone")
                                    Spacer()
                                    if device.isScreenMirror {
                                        Text("Scherm")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    Circle()
                                        .fill(device.isConnected ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                }
                                .tag(SelectedDevice.ios(device.id))
                            }
                        }
                    }
                    
                    // MARK: - Android Devices Section
                    Section("Android") {
                        if deviceManager.adbManager.devices.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Geen Android-apparaat", systemImage: "iphone.slash")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Sluit je Android-toestel aan via USB.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    showAndroidHelp = true
                                } label: {
                                    Label("USB Debugging inschakelen?", systemImage: "questionmark.circle")
                                        .font(.caption2)
                                }
                                .buttonStyle(.link)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(deviceManager.adbManager.devices) { device in
                                HStack {
                                    Label(device.name, systemImage: "phone")
                                    Spacer()
                                    Text("Scherm")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(4)
                                    Circle()
                                        .fill(device.isConnected ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                }
                                .tag(SelectedDevice.android(device.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Apparaten")
            .frame(minWidth: 200)
        } detail: {
            ZStack {
                if let error = captureService.errorMessage ?? scrcpyClient.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Probeer opnieuw") {
                            retryConnection()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if let selected = selectedDevice {
                    switch selected {
                    case .ios(let id):
                        if deviceManager.devices.contains(where: { $0.id == id }) {
                            MirrorView(
                                session: captureService.session,
                                rotationAngle: $captureService.rotationAngle
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                                    .allowsHitTesting(false)
                                    .padding(4)
                            )
                        }
                        
                    case .android(let id):
                        if let device = deviceManager.adbManager.devices.first(where: { $0.id == id }) {
                            if mirrorMode == .h264 {
                                AndroidMirrorView(client: scrcpyClient)
                                .rotationEffect(.degrees(androidRotationAngle))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                        .allowsHitTesting(false)
                                        .padding(4)
                                )
                            } else {
                                if let service = mjpegService {
                                    AndroidMJPEGView(service: service)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                                .allowsHitTesting(false)
                                                .padding(4)
                                        )
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Selecteer een apparaat in de zijbalk om te spiegelen")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 600)
            .toolbar {
                // Status indicator
                ToolbarItem(placement: .status) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(mirrorStatus.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    if case .android = selectedDevice {
                        Picker("Modus", selection: $mirrorMode) {
                            ForEach(MirrorMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if case .android = selectedDevice {
                            androidRotationAngle = (androidRotationAngle + 90).truncatingRemainder(dividingBy: 360)
                        } else {
                            captureService.rotationAngle = (captureService.rotationAngle + 90).truncatingRemainder(dividingBy: 360)
                        }
                    }) {
                        Label("Roteer", systemImage: "rotate.right")
                    }
                    .disabled(selectedDevice == nil)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        takeScreenshot()
                    }) {
                        Label("Screenshot", systemImage: "camera")
                    }
                    .disabled(selectedDevice == nil)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        captureService.isRecording.toggle()
                    }) {
                        Label(
                            captureService.isRecording ? "Stop opname" : "Start opname",
                            systemImage: captureService.isRecording ? "record.circle.fill" : "record.circle"
                        )
                    }
                    .disabled(selectedDevice == nil)
                }
            }
        }
        .onChange(of: selectedDevice) { _, newDevice in
            handleDeviceSelection(newDevice)
        }
        .onChange(of: captureService.errorMessage) { _, error in
            if error != nil {
                mirrorStatus = .error
            } else if selectedDevice != nil {
                mirrorStatus = .mirroring
            }
        }
        .onChange(of: scrcpyClient.errorMessage) { _, error in
            if error != nil {
                mirrorStatus = .error
            } else if selectedDevice != nil, scrcpyClient.isConnected {
                mirrorStatus = .mirroring
            }
        }
        .onChange(of: deviceManager.devices) { _, devices in
            if selectedDevice == nil {
                mirrorStatus = (devices.isEmpty && deviceManager.adbManager.devices.isEmpty) ? .searching : .found
            }
        }
        .onChange(of: deviceManager.adbManager.devices) { _, devices in
            if selectedDevice == nil {
                mirrorStatus = (devices.isEmpty && deviceManager.devices.isEmpty) ? .searching : .found
            }
        }
        .popover(isPresented: $showAndroidHelp) {
            androidHelpView
        }
    }
    
    // MARK: - Device Selection Handler
    
    private func handleDeviceSelection(_ newDevice: SelectedDevice?) {
        print("[ContentView] 🖱 handleDeviceSelection: \(String(describing: newDevice))")
        
        captureService.stopSession()
        captureService.errorMessage = nil
        scrcpyClient.disconnect()
        scrcpyClient.errorMessage = nil
        mjpegService?.stop()
        mjpegService = nil
        
        guard let device = newDevice else {
            mirrorStatus = .searching
            return
        }
        
        mirrorStatus = .connecting
        
        switch device {
        case .ios(let id):
            print("[ContentView] 📱 iOS device selected: \(id)")
            if let iosDevice = deviceManager.devices.first(where: { $0.id == id }) {
                print("[ContentView] ✅ Found iOS device: \(iosDevice.name)")
                captureService.startSession(for: iosDevice.captureDevice)
            } else {
                print("[ContentView] ❌ iOS device not found in list")
            }
            
        case .android(let id):
            print("[ContentView] 📱 Android device selected: \(id)")
            print("[ContentView] 📋 Available Android devices: \(deviceManager.adbManager.devices.map { "\($0.name) (\($0.id))" })")
            if let androidDevice = deviceManager.adbManager.devices.first(where: { $0.id == id }) {
                print("[ContentView] ✅ Found Android device: \(androidDevice.name), starting scrcpy...")
                
                // Init and start MJPEG fallback service
                if let adbPath = deviceManager.adbManager.adbPath {
                    let service = MJPEGScreencapService(adbPath: adbPath, serial: androidDevice.serialNumber)
                    self.mjpegService = service
                    service.start()
                }
                
                // Start the scrcpy server on the Android device, then connect
                deviceManager.adbManager.startScrcpyServer(serial: androidDevice.serialNumber) { result in
                    switch result {
                    case .success(let port):
                        print("[ContentView] ✅ Scrcpy server started on port \(port), connecting client...")
                        self.scrcpyClient.connect(port: port)
                    case .failure(let error):
                        print("[ContentView] ❌ Scrcpy server failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.scrcpyClient.errorMessage = error.localizedDescription
                            self.mirrorStatus = .error
                        }
                    }
                }
            } else {
                print("[ContentView] ❌ Android device '\(id)' not found in list!")
            }
        }
    }
    
    private func retryConnection() {
        if let current = selectedDevice {
            selectedDevice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedDevice = current
            }
        }
    }
    
    private var statusColor: Color {
        switch mirrorStatus {
        case .searching: return .gray
        case .found: return .blue
        case .connecting: return .orange
        case .mirroring: return .green
        case .error: return .red
        }
    }
    
    private func takeScreenshot() {
        print("Screenshot actie. Implementeer via bitmapImageRepForCachingDisplay(in:) op de MirrorView NSView.")
    }
    
    // MARK: - Android Help Popover
    
    private var androidHelpView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("USB Debugging inschakelen")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                helpStep(number: 1, text: "Open Instellingen op je Android-toestel")
                helpStep(number: 2, text: "Ga naar 'Over telefoon' (of 'Over tablet')")
                helpStep(number: 3, text: "Tik 7x op 'Build-nummer' om Ontwikkelaarsopties te activeren")
                helpStep(number: 4, text: "Ga terug en open 'Ontwikkelaarsopties'")
                helpStep(number: 5, text: "Schakel 'USB-foutopsporing' in")
                helpStep(number: 6, text: "Sluit het toestel aan via USB en kies 'Toestaan' in de pop-up")
            }
            
            Text("Na het inschakelen verschijnt je Android-toestel automatisch in de zijbalk.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 350)
    }
    
    private func helpStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.caption)
        }
    }
}
