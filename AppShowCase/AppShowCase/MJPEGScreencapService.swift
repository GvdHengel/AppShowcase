import Foundation
import AppKit
import Combine

class MJPEGScreencapService: ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var isRunning = false
    @Published var fps: Double = 0
    
    private var adbPath: String
    private var serial: String
    private var captureTask: Task<Void, Never>?
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    init(adbPath: String, serial: String) {
        self.adbPath = adbPath
        self.serial = serial
    }
    
    func start() {
        isRunning = true
        captureTask = Task { [weak self] in
            await self?.captureLoop()
        }
    }
    
    func stop() {
        isRunning = false
        captureTask?.cancel()
    }
    
    private func captureLoop() async {
        while isRunning && !Task.isCancelled {
            if let image = await captureFrame() {
                await MainActor.run {
                    self.currentFrame = image
                    self.frameCount += 1
                    let elapsed = Date().timeIntervalSince(self.lastFPSUpdate)
                    if elapsed >= 1.0 {
                        self.fps = Double(self.frameCount) / elapsed
                        self.frameCount = 0
                        self.lastFPSUpdate = Date()
                    }
                }
            }
            // ~100ms interval = 10fps
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func captureFrame() async -> NSImage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", serial, "exec-out", "screencap", "-p"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
