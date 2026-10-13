Je bent een expert macOS Swift developer. Bouw een volledige macOS-app in Swift/SwiftUI genaamd "AppShowcase" die een aangesloten iPhone via USB kan spiegelen op de Mac, vergelijkbaar met de app Bezel van Nonstrict.

## Tech Stack
- macOS 14+ (Sonoma minimaal)
- Swift 5.9 + SwiftUI voor UI
- AVFoundation (AVCaptureSession / AVCaptureDevice) voor screen mirroring via QuickTime-protocol
- **CoreMediaIO** (vereist voor `kCMIOHardwarePropertyAllowScreenCaptureDevices` — zonder deze flag verschijnt het schermspiegeling-device NIET)
- AVCaptureVideoPreviewLayer voor rendering (AVSampleBufferDisplayLayer niet nodig voor de basisflow)
- IOKit voor USB-apparaatdetectie (optioneel, als aanvulling op AVFoundation)

## Vereisten
- iPhone 17 compatibel (iOS 26) — getest met iPhone17,1
- Universal Binary (Ondersteuning voor zowel Apple Silicon (M-chips) als Intel Macs vereist)
- Minimale latency via USB (Target latency: < 200ms)
- Geen afhankelijkheid van libimobiledevice vanwege iOS 26 compatibiliteitsproblemen en de noodzaak voor Intel-support
- App draait **buiten de App Store** (geen sandbox, directe USB-toegang)

## Projectstructuur
AppShowcase/
├── AppShowcaseApp.swift           // App entry point + NSStatusItem
├── ContentView.swift              // Hoofd SwiftUI view met NavigationSplitView
├── MirrorView.swift               // NSViewRepresentable wrapper voor AVCaptureVideoPreviewLayer
├── DeviceManager.swift            // CoreMediaIO + AVFoundation device discovery
├── CaptureService.swift           // AVFoundation capture sessie beheer
├── AppShowcase.entitlements       // Sandbox UIT, camera/USB access
└── Info.plist                     // NSCameraUsageDescription + NSMicrophoneUsageDescription

## Stap 0: CoreMediaIO initialisatie (KRITIEK)
**Dit moet als ALLEREERSTE stap uitgevoerd worden, vóór alle device discovery.**

```swift
import CoreMediaIO

// Activeer CoreMediaIO DAL plugins voor screen capture/mirroring devices.
// Zonder deze flag verschijnt ALLEEN de Continuity Camera, NIET het iPhone scherm.
var property = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var allow: UInt32 = 1
CMIOObjectSetPropertyData(
    CMIOObjectID(kCMIOObjectSystemObject),
    &property, 0, nil,
    UInt32(MemoryLayout<UInt32>.size),
    &allow
)
```

> **Waarom**: Zonder deze flag registreert de CoreMediaIO DAL plugin het iPhone screen mirroring device niet. Je ziet dan alleen `iPhoneG Camera` (Continuity Camera, `.video`), en de `.muxed` discovery geeft 0 resultaten. Met de flag actief verschijnt het iPhone-scherm als een `.muxed` device via het QuickTime-protocol.

## Stap 1: Camera-permissie aanvragen (VÓÓR device discovery)
**Kritiek: kip-en-ei probleem!**

- `AVCaptureDevice.DiscoverySession` geeft **lege resultaten** als camera-toegang niet is verleend.
- Camera-toegang (`AVCaptureDevice.requestAccess(for: .video)`) moet daarom worden aangevraagd **bij het opstarten van de app**, vóór de eerste device discovery.
- Pas NA de callback met `granted == true` mag `refreshDevices()` worden aangeroepen.
- Publiceer een `@Published var cameraAuthorized: Bool` zodat de UI altijd een duidelijke melding kan tonen als de permissie ontbreekt.

```swift
// In DeviceManager.init():
let status = AVCaptureDevice.authorizationStatus(for: .video)
if status == .notDetermined {
    AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
            self.cameraAuthorized = granted
            if granted { self.refreshDevices() }
        }
    }
} else if status == .authorized {
    self.cameraAuthorized = true
    self.refreshDevices()
}
```

## Stap 2: Apparaatdetectie (AVFoundation)
Implementeer in DeviceManager.swift:
- Zorg dat `DeviceManager` conform is aan `ObservableObject`.
- `import CoreMediaIO` is vereist naast `import AVFoundation`.
- Gebruik de volgende discovery-volgorde (prioriteit: schermspiegeling boven camera):
  1. `AVCaptureDevice.DiscoverySession` met `deviceTypes: [.external]`, `mediaType: .muxed` → **Schermspiegeling** (QuickTime protocol, video + audio)
  2. `AVCaptureDevice.DiscoverySession` met `deviceTypes: [.external]`, `mediaType: .video` → **Continuity Camera** (fallback)
  3. `AVCaptureDevice.DiscoverySession` met `deviceTypes: [.external]`, `mediaType: nil` → **Alle externe apparaten** (catch-all fallback)
- Filter op `modelID.lowercased().contains("iphone")` óf `localizedName.lowercased().contains("iphone")`.
- Luister naar `.AVCaptureDeviceWasConnected` en `.AVCaptureDeviceWasDisconnected` notificaties. Updates **altijd op main thread** (`DispatchQueue.main.async`).
- iOSDevice model: struct met `id`, `name`, `model`, `isConnected`, `isScreenMirror: Bool`, `captureDevice: AVCaptureDevice`.

> **Belangrijk gedrag iPhone 17,1 / iOS 26**: Het Continuity Camera device verschijnt als `iPhoneG Camera` met mediaType `.video`. Het schermspiegelingsdevice verschijnt als `.muxed` — maar **alleen** als `kCMIOHardwarePropertyAllowScreenCaptureDevices` is geactiveerd.

## Stap 3: Screen Mirroring (QuickTime Protocol)
Implementeer in CaptureService.swift:
- Zorg dat `CaptureService` conform is aan `ObservableObject`.
- Beheer state via `@Published var rotationAngle: Double = 0` en `@Published var isRecording: Bool = false`.
- Camera-autorisatie wordt al afgehandeld in DeviceManager (Stap 1). CaptureService hoeft dit NIET opnieuw te doen.
- Maak een `AVCaptureSession` met preset `.high` (niet forceren naar 1080p — iPhone levert native resolutie).
- Voeg de geselecteerde iPhone toe als `AVCaptureDeviceInput`. Negeer audio (géén `AVCaptureAudioDataOutput`) om echo's te voorkomen.
- **Kritiek**: `session.startRunning()` en `session.stopRunning()` mogen *nooit* de main thread blokkeren! Gebruik altijd een eigen background queue (`DispatchQueue(label: "com.appshowcase.session")`).
- Gebruik `AVCaptureVideoPreviewLayer` voor rendering.
- Luister naar `.AVCaptureSessionRuntimeError` notificatie voor verbrekingen.

## Stap 4: Rendering
Implementeer in MirrorView.swift:
- `NSViewRepresentable` wrapper om `AVCaptureVideoPreviewLayer` te embedden in SwiftUI.
- Aspect ratio behouden: `AVLayerVideoGravity.resizeAspect`.
- Rotatie via `previewLayer.connection?.videoRotationAngle`.
- Generieke iPhone bezel overlay (bijv. `RoundedRectangle` met stroke).

## Stap 5: SwiftUI Interface
Implementeer in ContentView.swift:
- `NavigationSplitView` met sidebar (device lijst) en detail (MirrorView).
- **Camera-permissie geweigerd**: toon duidelijke melding met "Open Systeeminstellingen" knop (`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`).
- **Geen apparaat**: "Sluit je iPhone aan, ontgrendel het scherm en kies 'Vertrouw'."
- **Devices gevonden**: toon met `isScreenMirror` badge ("Scherm") vs camera icoon.
- Status indicator: Zoeken → Gevonden → Koppelen → Gespiegeld.
- Toolbar: Schermafbeelding, Opname starten/stoppen, Roteer.
- Menubar item via `NSStatusItem` in `NSApplicationDelegate`.

## Stap 6: Entitlements, Permissions & Build Settings

### Entitlements (AppShowcase.entitlements)
```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.usb</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
```

### Build Settings (project.pbxproj) — KRITIEK
Wanneer Xcode `GENERATE_INFOPLIST_FILE = YES` gebruikt, wordt een **custom Info.plist bestand genegeerd**. De privacy-keys moeten dan als `INFOPLIST_KEY_*` worden toegevoegd in de Build Settings:

```
ENABLE_APP_SANDBOX = NO                          // VERPLICHT voor CoreMediaIO DAL plugin
ENABLE_HARDENED_RUNTIME = YES
RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION = YES  // VERPLICHT voor DAL plugin loading

GENERATE_INFOPLIST_FILE = YES
INFOPLIST_FILE = AppShowCase/Info.plist

// Privacy keys — VERPLICHT, anders crash bij camera-aanvraag
INFOPLIST_KEY_NSCameraUsageDescription = "AppShowcase vereist toegang tot je camera om het beeldscherm van de iPhone via USB in te kunnen lezen."
INFOPLIST_KEY_NSMicrophoneUsageDescription = "AppShowcase gebruikt de mediapoort van je iPhone, hiervoor eist macOS microfoontoestemming."
INFOPLIST_KEY_LSUIElement = NO
```

> **Let op**: Als `ENABLE_APP_SANDBOX = YES` staat in de build settings, overschrijft dit de entitlements file (`com.apple.security.app-sandbox = false`). De build settings winnen altijd.

### Info.plist (custom keys naast de gegenereerde)
```xml
<key>LSUIElement</key>
<false/>
<key>NSCameraUsageDescription</key>
<string>AppShowcase vereist toegang tot je camera om het beeldscherm van de iPhone via USB in te kunnen lezen.</string>
<key>NSMicrophoneUsageDescription</key>
<string>AppShowcase gebruikt de mediapoort van je iPhone, hiervoor eist macOS microfoontoestemming.</string>
```

### Code Signing
- `CODE_SIGN_IDENTITY[sdk=macosx*]` = `"-"` (ad-hoc signing)
- `CODE_SIGN_STYLE` = `Manual`
- Geen development team nodig voor lokale builds

## Stap 7: Extra / Screenshots & Foutafhandeling
- Screenshot: `bitmapImageRepForCachingDisplay(in:)` op de MirrorView NSView.
- Foutafhandeling: Device niet vertrouwd of permissies ontbreken → duidelijke UI-instructies.
- Auto-reconnect bij herverbinding via `AVCaptureDevice.wasConnectedNotification`.

## Bekende onschadelijke console-meldingen
De volgende console-output is **normaal** en kan worden genegeerd:
- `AddInstanceForFactory: No factory registered for id` — CoreMedia plugin registratie, onschadelijk
- `CMIO_DAL_CMIOExtension_Device.mm: Device legacy uuid isn't present` — informatief, oude UUID formaat
- `CMIO_DAL_CMIOExtension_Stream.mm: GetPropertyData background replacement pixel buffer size invalid` — geen impact
- `CMIOHardware.cpp: CMIOObjectGetPropertyData Error: 2003332927` — error code `who?`, device herkent property niet
- `AVCaptureProprietaryDefaults: Fig assert "surfaceValue"` — bekend Apple bug
- `AudioObjectRemovePropertyListener: no object with given ID` — cleanup bij disconnect
- `DetachedSignatures: No such file or directory` — code signing gerelateerd, normaal bij dev builds

Begin met DeviceManager.swift (inclusief CoreMediaIO init) en CaptureService.swift als fundament.
