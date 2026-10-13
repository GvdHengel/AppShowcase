Je bent een expert macOS Swift developer. Bouw een volledige macOS-app in Swift/SwiftUI genaamd "AppShowCase" die aangesloten iOS- en Android-apparaten via USB kan spiegelen op de Mac, vergelijkbaar met de app Bezel van Nonstrict.

## Tech Stack
- macOS 14+ (Sonoma minimaal)
- Swift 5.9 + SwiftUI voor UI
- AVFoundation voor iOS USB-apparaatdetectie en video capture
- CoreMediaIO voor het activeren van screen capture devices (iOS)
- AVCaptureVideoPreviewLayer voor hardware-accelerated iOS rendering
- VideoToolbox voor hardware-accelerated H.264 decoding (Android)
  - `AVSampleBufferDisplayLayer` via AVCC Multi-Slice grouping voor Android Frame Rendering
- Gebundelde `adb` binary + `scrcpy-server` voor Android-communicatie
- Xcode project (geen SPM dependencies nodig)

## Vereisten
- iPhone 17 / iPad compatibel (iOS 26)
- Android-apparaten met USB Debugging ingeschakeld
- MacBook Apple Silicon (M1/M4) geoptimaliseerd
- Minimale latency via USB
- App Sandbox uitgeschakeld (vereist voor CoreMediaIO property + ADB binary execution)

## Projectstructuur
AppShowCase/
├── AppShowCaseApp.swift        // App entry point, NSStatusItem menubar, ADB cleanup
├── ContentView.swift           // NavigationSplitView met iOS/Android secties
├── DeviceManager.swift         // iOS apparaatdetectie (AVFoundation + CoreMediaIO)
├── ADBManager.swift            // Android apparaatdetectie (ADB) + scrcpy server management
├── CaptureService.swift        // AVCaptureSession beheer voor iOS-mirroring
├── ScrcpyClient.swift          // TCP socket, NAL parser, VideoToolbox H.264 decoding
├── MirrorView.swift            // NSViewRepresentable + AVCaptureVideoPreviewLayer (iOS)
├── AndroidMirrorView.swift     // NSViewRepresentable + AVSampleBufferDisplayLayer (Android)
├── AppShowcase.entitlements    // Camera + USB + Network permissies
├── Info.plist                  // NSCameraUsageDescription, NSMicrophoneUsageDescription
├── Assets.xcassets/            // App icon en assets
└── Resources/
    ├── adb                     // Gebundelde ADB binary (Universal: x86_64 + arm64)
    └── scrcpy-server           // scrcpy-server v3.1 JAR (~90KB)

---

## iOS Mirroring

### Stap 1: CoreMediaIO Activatie & Apparaatdetectie (DeviceManager.swift)
Implementeer als ObservableObject:

#### CoreMediaIO Property (CRUCIAAL)
- Stel `kCMIOHardwarePropertyAllowScreenCaptureDevices` in op `1` via `CMIOObjectSetPropertyData`
- Dit moet EERST gebeuren, anders ziet AVFoundation de iPhone/iPad niet als capture device
- Scope: `kCMIOObjectPropertyScopeGlobal`, Element: `kCMIOObjectPropertyElementMain`

#### Apparaatdetectie via AVFoundation
- Gebruik `AVCaptureDevice.DiscoverySession` met deviceType `.external`
- MediaType: `.muxed` voor screen mirroring (NIET `.video` — dat vindt alleen camera's)
- Additioneel `.video` session voor camera-fallback
- Combineer met `.external` + `nil` session voor volledige dekking
- Detectie via `AVCaptureDeviceWasConnected` / `AVCaptureDeviceWasDisconnected` notificaties
- Apparaatfilter (`isIOSDevice`): check of naam/model "iphone", "ipad", "ios" of "apple" bevat
- Publiceer als `@Published var devices: [iOSDevice]`

#### iOSDevice struct
```swift
struct iOSDevice: Identifiable, Hashable {
    let id: String              // uniqueID
    let name: String            // localizedName
    let model: String           // modelID
    var isConnected: Bool
    let isScreenMirror: Bool    // true = muxed (scherm), false = video (camera)
    let captureDevice: AVCaptureDevice
}
```

#### Permissie-check
- Check `AVCaptureDevice.authorizationStatus(for: .video)` bij init
- Request access als `.notDetermined`
- Update `@Published var cameraAuthorized: Bool` op main thread

### Stap 2: iOS Video Mirroring (MirrorView.swift + CaptureService.swift)

#### CaptureService (ObservableObject)
- `AVCaptureSession` met preset `.high`
- Start/stop op serial background queue (`com.appshowcase.session`)
- Input: `AVCaptureDeviceInput` van geselecteerd iOS device
- Error handling via `AVCaptureSession.runtimeErrorNotification`

#### MirrorView (NSViewRepresentable)
- Custom `MirrorNSView` met `AVCaptureVideoPreviewLayer`
- Video gravity: `.resizeAspect`
- Rotatie via `connection.videoRotationAngle`
- Layout: previewLayer.frame volgt bounds

---

## Android Mirroring

### Stap 3: ADB Apparaatdetectie (ADBManager.swift)
Implementeer als ObservableObject:

#### Gebundelde binaries
- `adb` binary via `Bundle.main.path(forResource: "adb", ofType: nil)`
- `scrcpy-server` via `Bundle.main.path(forResource: "scrcpy-server", ofType: nil)`

#### Apparaatdetectie via `adb track-devices`
- Continu commando (NIET polling) — ADB pusht updates bij wijzigingen
- Parse `adb devices -l` output voor apparaatnaam en serienummer
- Alleen "device" status (geautoriseerde apparaten) tonen
- Model naam ophalen uit `model:` veld in de output
- Automatisch herstarten bij onverwachte disconnect

#### AndroidDevice struct
```swift
struct AndroidDevice: Identifiable, Hashable {
    let id: String           // ADB serial number
    var name: String         // Model naam (ro.product.model)
    let serialNumber: String
    var isConnected: Bool
}
```

#### Scrcpy Server Management
1. `adb push scrcpy-server /data/local/tmp/scrcpy-server.jar`
2. `adb reverse localabstract:scrcpy tcp:27183` (fallback: `adb forward`)
3. `adb shell CLASSPATH=... app_process / com.genymobile.scrcpy.Server 3.1`
   - Parameters: `tunnel_forward=true`, `audio=false`, `control=false`, `video_codec=h264`, `max_fps=60`, `video_bit_rate=8000000`

#### Cleanup
- `stopScrcpyServer()`: verwijder reverse/forward tunnels
- `killADBServer()`: bij app-exit om zombie processen te voorkomen
- `applicationWillTerminate` in AppDelegate roept cleanup aan

### Stap 4: H.264 Video Decoding (ScrcpyClient.swift)

#### Socket verbinding
- `CFStreamCreatePairWithSocketToHost` naar `127.0.0.1:27183`
- **Scrcpy v3 Protocol Initialisatie**: Eerst `1 byte` dummy lezen, dan `76 bytes` metadata (64 bytes device name + 4 bytes codec 'h264' + 4 bytes initial width + 4 bytes initial height).

#### Packet Parser & AVCC Multi-Slice Grouping (CRUCIAAL)
- Lees telkens een `12-byte header`. De laatste 4 bytes (big-endian) vormen de `packetSize`.
- Lees exact `packetSize` videodata via de socket (fragmenteren over chuncks van max 65536).
- Scan het pakket op NAL start codes (`0x00 0x00 0x00 0x01` of `0x00 0x00 0x01`).
- Filter de NAL types via `byte[0] & 0x1F`:
  - Type 7 = SPS (Sequence Parameter Set) → Opslaan in Array[UInt8] voor format descriptions.
  - Type 8 = PPS (Picture Parameter Set) → Opslaan in Array[UInt8].
  - Type 5 = IDR frame (keyframe)
  - Type 1 = Non-IDR frame (P/B frame)
- SPS + PPS → `CMVideoFormatDescriptionCreateFromH264ParameterSets()`
- Converteer NAL slices uit één pakket naar **AVCC-formaat** door *elke* slice te voorzien van een `4-byte` big-endian lengte-prefix in plaats van de NAL start-code.
- Bundel deze in **één enkele iteratie** per Frame in een `CMBlockBuffer` en daarna een `CMSampleBuffer`. 

#### AVSampleBufferDisplayLayer Rendering
- Voorkom dangling pointers in Swift buffer arrays bij CMBlockBuffer generatie (kies voor `CMBlockBufferCreateWithMemoryBlock` in plaats van `withUnsafeBytes`).
- Stel de `CMSampleBuffer` attributen in: `kCMSampleAttachmentKey_DependsOnOthers` (false voor keyframes) en `kCMSampleAttachmentKey_DisplayImmediately` (true voor allemaal, ingesteld via raw pointers `CFDictionarySetValue`).
- Timestamps: forceer `.invalid` timestamps zodat de AVSampleBufferDisplayLayer beelden direct pusht en niet de frames gaat "vasthouden" of bufferen.

#### Retry-logica
- Max 5 pogingen, 2 seconden interval
- Bij stream-onderbreking: rapporteer via `@Published var errorMessage`

### Stap 5: Android Display (AndroidMirrorView.swift)
- `NSViewRepresentable` met `AVSampleBufferDisplayLayer`
- **Latency-optimalisatie**: `controlTimebase` instellen op realtime klok (geen buffering)
- Video gravity: `.resizeAspect`

---

## Stap 6: SwiftUI Interface (ContentView.swift)
Implementeer met NavigationSplitView:

### Sidebar — 2 secties:

#### iOS sectie
- Lijst van iOSDevices uit DeviceManager
- Iconen: `rectangle.on.rectangle` (scherm) of `iphone` (camera)
- "Scherm" badge (blauw) + groene verbindingsindicator
- Lege staat: "Geen iOS-apparaat" + instructie

#### Android sectie
- Lijst van AndroidDevices uit ADBManager
- Iconen: `phone`
- "Scherm" badge (groen) + groene verbindingsindicator
- Lege staat: "Geen Android-apparaat" + "USB Debugging inschakelen?" help-link
- Help-popover met 6 stappen (Developer Options → USB Debugging)

### SelectedDevice enum
```swift
enum SelectedDevice: Hashable {
    case ios(String)       // iOSDevice id
    case android(String)   // AndroidDevice id
}
```

### Detail View — afhankelijk van selectie:
1. **iOS geselecteerd**: `MirrorView` met bezel overlay (cornerRadius: 32)
2. **Android geselecteerd**: `AndroidMirrorView` met bezel overlay (cornerRadius: 16)
3. **Error staat**: Foutmelding + "Probeer opnieuw" knop
4. **Geen selectie**: Instructie met `iphone.and.arrow.forward` icoon

### Toolbar
- Status indicator: Zoeken → Gevonden → Koppelen → Gespiegeld (met gekleurde bolletjes)
- Roteer-knop (werkt voor zowel iOS als Android)
- Screenshot-knop
- Opname start/stop-knop

### Window
- Minimum grootte: 400×600
- NSStatusItem in menubar

## Stap 7: App Entry Point (AppShowCaseApp.swift)
- `@main` struct met WindowGroup
- `@NSApplicationDelegateAdaptor(AppDelegate.self)` voor menubar + cleanup
- `NSStatusItem` met menu: "Toon AppShowcase" + "Stop"
- `applicationWillTerminate`: ADB server cleanup

## Stap 8: Entitlements & Permissions

### AppShowcase.entitlements:
```xml
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.usb</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.network.client</key><true/>
```

### Info.plist:
```xml
<key>NSCameraUsageDescription</key>
<string>AppShowcase vereist toegang tot je camera om het beeldscherm van de iPhone via USB in te kunnen lezen.</string>
<key>NSMicrophoneUsageDescription</key>
<string>AppShowcase gebruikt de mediapoort van je iPhone, hiervoor eist macOS microfoontoestemming (er wordt echter geen geluid opgevangen).</string>
```

## Foutafhandeling
- iOS stream onderbroken → error message + "Probeer opnieuw"
- Android stream onderbroken → auto-retry (max 5, 2s interval)
- Camera permissie geweigerd → toon System Settings link
- Geen iOS devices → lege staat met instructies
- Geen Android devices → lege staat met USB Debugging help-popover
- ADB binary niet gevonden → foutmelding in console
- Scrcpy push/tunnel/start mislukt → gebruikersvriendelijke foutmelding

## Architectuur Principes
- Alle `@Published` property updates op main thread
- Session start/stop altijd op background queue
- Geen audio capture (voorkom echo)
- iOS device type `.external` (niet `.externalUnknown`)
- iOS preset `.high` (niet geforceerd resolutie)
- Android: hardware-versnelde H.264 decoding via VideoToolbox
- Android: `controlTimebase` op `AVSampleBufferDisplayLayer` voor minimale latency
- Android: `adb track-devices` (continu) i.p.v. polling
- ADB zombie cleanup bij app-exit
- Gebundelde binaries (adb + scrcpy-server) — geen externe dependencies voor de gebruiker

Begin met een volledig werkend Xcode project. Maak alle bestanden aan en geef werkende code. Start met DeviceManager.swift als fundament, dan ADBManager.swift, dan MirrorView.swift + ScrcpyClient.swift + AndroidMirrorView.swift, dan ContentView.swift.
