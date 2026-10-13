import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var isLocked = false
    @State private var videoSize: CGSize?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $deviceManager.selectedDevice) {
                if deviceManager.devices.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(deviceManager.devices, id: \.uniqueID) { device in
                        Text(device.localizedName)
                            .tag(device as AVCaptureDevice?)
                    }
                }
            }
            .navigationTitle("Devices")
            .frame(minWidth: 200)
        } detail: {
            if !deviceManager.isAuthorized {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Camera Access Required")
                        .font(.title2)
                    Text("Please allow camera access in System Settings to mirror your iPhone via USB.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding()
            } else if let selectedDevice = deviceManager.selectedDevice {
                ZStack {
                    MirrorView(device: selectedDevice, isLocked: $isLocked, videoSize: $videoSize)
                        .edgesIgnoringSafeArea(.all)
                    
                    if isLocked {
                        VStack(spacing: 16) {
                            Image(systemName: "lock.iphone")
                                .font(.system(size: 64))
                            Text("iPhone Locked or Stream Disconnected")
                                .font(.title2)
                            Text("Unlock your iPhone to resume mirroring.")
                                .foregroundColor(.secondary)
                        }
                        .padding(40)
                        .background(.regularMaterial)
                        .cornerRadius(20)
                        .shadow(radius: 20)
                    }
                    
                    // Simple Bezel overlay placeholder
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .padding(20)
                .aspectRatio(videoSize != nil ? (videoSize!.width / videoSize!.height) : 0.46, contentMode: .fit)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "iphone")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Connect an iPhone via USB")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .floatingWindow(true)
    }
}
