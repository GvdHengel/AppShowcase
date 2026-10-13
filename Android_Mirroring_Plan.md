# Android Mirroring — Nieuw Plan & Architectuur
## AppShowCase macOS App

---

## 1. Diagnose: Waarom het groen scherm?

Het groene scherm is een klassiek symptoom van een **YUV → RGB color space conversie mismatch** in de VideoToolbox/AVSampleBufferDisplayLayer pipeline. Er zijn vijf mogelijke oorzaken:

### A. CMVideoFormatDescription klopt niet
Als SPS/PPS niet correct geparsed worden (bijv. verkeerde byte-offset bij scrcpy v3 header), dan maakt VideoToolbox een kapotte decoder context. Output = groen beeld.

### B. CMBlockBuffer dangling pointer
Wanneer `withUnsafeBytes` gebruikt wordt in Swift, is de buffer al vrijgegeven vóór VideoToolbox de data verwerkt. Resultaat: garbage of groen frame.

### C. AVCC Multi-Slice grouping fout
Als NAL units verkeerd samengevoegd worden (bijv. start codes niet vervangen door 4-byte lengteprefix), decodeert VT naar een corrupt frame — zichtbaar als groen.

### D. AVSampleBufferDisplayLayer timing conflict
Zonder expliciete `controlTimebase` houdt de layer frames vast ("future timestamp"). De layer toont dan niets of een groen placeholder.

### E. Scrcpy v3 protocol — verkeerde headerparse
Scrcpy v3 heeft een gewijzigd initialisatieprotocol. Als de 1-byte dummy + 76-byte metadata verkeerd gelezen wordt, raakt de stream uit sync en decodeert alles fout.

---

## 2. Strategie Vergelijking

| Strategie | Latency | Complexiteit | Betrouwbaarheid | Aanbevolen voor |
|---|---|---|---|---|
| **A: Fix ScrcpyClient (H.264)** | ~50ms | Hoog | Hoog (als correct) | Productie |
| **B: MJPEG via ADB screencap** | ~300ms | Laag | Zeer hoog | Fallback / debug |
| **C: Bundel scrcpy binary + parse stdout** | ~60ms | Middel | Hoog | Alternatief |
| **D: ADB + libimobiledevice bridge** | ~80ms | Hoog | Middel | Nee |

**Advies: Implementeer B als werkende fallback, fix A als primaire strategie.**

---

## 3. Strategie A — ScrcpyClient Reparatie (Primair)

### 3.1 Scrcpy v3 Protocol (exact)

```
Socket verbinding: 127.0.0.1:27183

Initialisatie volgorde:
1. Lees 1 byte  → dummy byte, weggooien
2. Lees 64 bytes → device name (UTF-8, null-terminated)
3. Lees 4 bytes  → codec ID (big-endian uint32: 0x68323634 = "h264")
4. Lees 4 bytes  → initial width (big-endian uint32)
5. Lees 4 bytes  → initial height (big-endian uint32)
Total metadata: 1 + 64 + 4 + 4 + 4 = 77 bytes

Per video packet:
Header: 12 bytes
  [0..7]  : PTS (big-endian int64, microseconds) — gebruik voor DTS
  [8..11] : packet size (big-endian uint32)
  
Body: <packet size> bytes van H.264 data (Annex B formaat)
```

### 3.2 Kritieke Fix: CMBlockBuffer zonder dangling pointers

```swift
// ❌ FOUT — buffer kan al freed zijn door Swift ARC
func createBlockBuffer(data: [UInt8]) -> CMBlockBuffer? {
    return data.withUnsafeBytes { ptr in
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(...)  // ptr is invalid buiten closure!
        return blockBuffer
    }
}

// ✅ CORRECT — kopieer data naar heap-owned buffer
func createBlockBufferCopy(from data: [UInt8]) -> CMBlockBuffer? {
    let dataSize = data.count
    
    // Alloceer unmanaged heap memory
    let heapData = UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
    data.withUnsafeBytes { src in
        heapData.initialize(from: src.bindMemory(to: UInt8.self).baseAddress!, count: dataSize)
    }
    
    var blockBuffer: CMBlockBuffer?
    let status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: heapData,
        blockLength: dataSize,
        blockAllocator: kCFAllocatorMalloc,  // Laat CoreMedia de vrijgave regelen
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: dataSize,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    
    guard status == noErr else {
        heapData.deallocate()
        return nil
    }
    return blockBuffer
}
```

### 3.3 NAL Parser met correcte AVCC Multi-Slice grouping

```swift
struct NALUnit {
    let type: UInt8     // byte[0] & 0x1F
    let data: [UInt8]   // NAL data ZONDER start code
}

func parseNALUnits(from packet: [UInt8]) -> [NALUnit] {
    var nalUnits: [NALUnit] = []
    var i = 0
    
    while i < packet.count {
        // Zoek start code (0x00 0x00 0x01 of 0x00 0x00 0x00 0x01)
        guard let startOffset = findStartCode(in: packet, from: i) else { break }
        
        let startCodeLen = (startOffset >= 1 && packet[startOffset - 1] == 0x00) ? 4 : 3
        let nalStart = startOffset + 3  // Na de 0x00 0x00 0x01
        
        // Zoek volgende start code voor lengte bepaling
        let nextStart = findStartCode(in: packet, from: nalStart) ?? packet.count
        let nalData = Array(packet[nalStart..<nextStart])
        
        if !nalData.isEmpty {
            let nalType = nalData[0] & 0x1F
            nalUnits.append(NALUnit(type: nalType, data: nalData))
        }
        i = nextStart
    }
    return nalUnits
}

// Converteer NAL units naar AVCC (4-byte length prefix)
func toAVCC(nalData: [UInt8]) -> [UInt8] {
    let length = nalData.count
    return [
        UInt8((length >> 24) & 0xFF),
        UInt8((length >> 16) & 0xFF),
        UInt8((length >> 8) & 0xFF),
        UInt8(length & 0xFF)
    ] + nalData
}
```

### 3.4 CMSampleBuffer met correcte timestamps en attachments

```swift
func createSampleBuffer(avccData: [UInt8], isKeyframe: Bool) -> CMSampleBuffer? {
    guard let blockBuffer = createBlockBufferCopy(from: avccData),
          let formatDesc = currentFormatDescription else { return nil }
    
    // Gebruik INVALID timestamps — laat layer zelf beslissen wanneer te renderen
    var timingInfo = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: .invalid,
        decodeTimeStamp: .invalid
    )
    
    var sampleBuffer: CMSampleBuffer?
    var size = avccData.count
    
    let status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDesc,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timingInfo,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &size,
        sampleBufferOut: &sampleBuffer
    )
    
    guard status == noErr, let sb = sampleBuffer else { return nil }
    
    // Attachments instellen via raw CFDictionary
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true)!
    let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
    
    // DisplayImmediately = true voor alle frames
    CFDictionarySetValue(dict,
        Unmanaged.passRetained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passRetained(kCFBooleanTrue).toOpaque())
    
    // DependsOnOthers = false voor keyframes
    if isKeyframe {
        CFDictionarySetValue(dict,
            Unmanaged.passRetained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque(),
            Unmanaged.passRetained(kCFBooleanFalse).toOpaque())
    }
    
    return sb
}
```

### 3.5 AVSampleBufferDisplayLayer met controlTimebase

```swift
func setupDisplayLayer() {
    displayLayer = AVSampleBufferDisplayLayer()
    displayLayer.videoGravity = .resizeAspect
    
    // CRUCIAAL: Realtime timebase instellen
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(
        allocator: kCFAllocatorDefault,
        sourceClock: CMClockGetHostTimeClock(),
        timebaseOut: &timebase
    )
    
    if let tb = timebase {
        CMTimebaseSetTime(tb, time: CMTime(value: 0, timescale: 1))
        CMTimebaseSetRate(tb, rate: 1.0)
        displayLayer.controlTimebase = tb
    }
    
    // Flush bij nieuwe verbinding
    displayLayer.flush()
    displayLayer.flushAndRemoveImage()
}
```

---

## 4. Strategie B — MJPEG Fallback via ADB Screencap (Direct werkend)

Dit is de **Vysor-achtige aanpak**: eenvoudig, geen H.264 decoding nodig. Vysor v1 gebruikte precies deze methode.

### 4.1 Hoe het werkt

```
adb exec-out screencap -p  →  PNG bytes via stdout  →  NSImage/CGImage  →  SwiftUI Image
```

Polling interval: 100ms = ~10fps (acceptabel voor demo/fallback)

### 4.2 Implementatie: MJPEGScreencapService.swift

```swift
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
```

### 4.3 SwiftUI view voor MJPEG

```swift
struct AndroidMJPEGView: View {
    @ObservedObject var service: MJPEGScreencapService
    
    var body: some View {
        ZStack {
            Color.black
            if let frame = service.currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView("Verbinden...")
                    .foregroundColor(.white)
            }
            
            VStack {
                HStack {
                    Spacer()
                    Text("\(String(format: "%.1f", service.fps)) fps")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                        .padding(8)
                }
                Spacer()
            }
        }
    }
}
```

---

## 5. Strategie C — Bundel scrcpy binary (Meest betrouwbaar)

In plaats van het scrcpy protocol zelf te implementeren, bundel je de **scrcpy binary** (macOS ARM64 build) en laat je die het werk doen.

### 5.1 Aanpak

```
scrcpy binary → V4L2 loopback of named pipe → AVFoundation capture
```

Maar op macOS zonder V4L2: gebruik `--v4l2-sink` niet. In plaats daarvan:

```
scrcpy --no-audio --no-control --record output.mp4 --record-format mkv
```

Of nog beter: **scrcpy met een custom socket output parser** waarbij je de binary opstart en zijn H.264 stream opvangt via een named pipe:

```bash
scrcpy --no-audio --no-control --video-codec=h264 \
       --v4l2-sink=/dev/video0  # Linux only
```

Op macOS: gebruik `--record -` (stdout) en lees de MKV stream in.

**Praktischer**: Gebruik **scrcpy-server.jar alleen** met je eigen socket client, maar fix de protocol parsing (zie Strategie A).

---

## 6. Aanbevolen Implementatiepad

### Fase 1 — Onmiddellijk werkend (week 1)
Implementeer **Strategie B (MJPEG screencap)** als werkende Android mirror. Lage latency-verwachting bij gebruikers, maar het werkt gegarandeerd.

### Fase 2 — Hoge prestaties (week 2-3)
Fix **Strategie A (ScrcpyClient)** met de correcties uit sectie 3:
1. Fix protocol parse (77 bytes ipv 76)
2. Fix CMBlockBuffer met `kCFAllocatorMalloc`
3. Fix AVCC conversie (controleer start code detectie)
4. Fix `controlTimebase` setup
5. Debug met Xcode's GPU Frame Capture om te bevestigen dat VT correct decodeert

### Fase 3 — Kwaliteit (week 4)
- Automatische fallback: probeer scrcpy H.264, val terug op MJPEG
- `@Published var mirrorMode: MirrorMode` (`.h264` / `.mjpeg`)
- UI indicator voor actieve modus + latency statistieken

---

## 7. Debug Tools

### Test scrcpy server verbinding handmatig
```bash
# Terminal 1: start server
/pad/naar/adb -s SERIAL push scrcpy-server /data/local/tmp/scrcpy-server.jar
/pad/naar/adb -s SERIAL forward tcp:27183 localabstract:scrcpy
/pad/naar/adb -s SERIAL shell CLASSPATH=/data/local/tmp/scrcpy-server.jar \
  app_process / com.genymobile.scrcpy.Server 3.1 \
  tunnel_forward=true audio=false control=false video_codec=h264

# Terminal 2: dump raw bytes
nc 127.0.0.1 27183 | xxd | head -20
```

Verwachte eerste bytes:
```
00000000: XX 00 00 00  ...device_name_64_bytes...  68 32 36 34
                                                     ^h264 codec
```

### Xcode: VideoToolbox decoder output checken
```swift
// Voeg toe aan VTDecompressionSession callback:
VTDecompressionSessionCreate(
    allocator: kCFAllocatorDefault,
    formatDescription: formatDesc,
    decoderSpecification: nil,
    imageBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA  // Force BGRA output
    ] as CFDictionary,
    outputCallback: &callbackRecord,
    decompressionSessionOut: &session
)
```

Het forceren van `kCVPixelFormatType_32BGRA` in plaats van de standaard YUV output elimineert color space conversie problemen en lost het groene scherm op.

---

## 8. Samenvatting Wijzigingen per Bestand

| Bestand | Wijziging |
|---|---|
| `ScrcpyClient.swift` | Fix protocol header (77 bytes), fix CMBlockBuffer allocator, fix AVCC grouping |
| `AndroidMirrorView.swift` | Fix controlTimebase setup, voeg flush() toe bij start |
| `ADBManager.swift` | Fix scrcpy server argumenten (tunnel_forward=true) |
| `MJPEGScreencapService.swift` | **Nieuw bestand** — screencap fallback |
| `AndroidMJPEGView.swift` | **Nieuw bestand** — SwiftUI view voor MJPEG |
| `ContentView.swift` | Voeg mode-switcher toe (H.264 ↔ MJPEG) |

---

*Plan versie 1.0 — AppShowCase Android Mirroring*
