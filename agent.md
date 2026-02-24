Je bent een expert macOS Swift developer. Bouw een volledige macOS-app in Swift/SwiftUI genaamd "iPhoneMirror" die een aangesloten iPhone via USB kan spiegelen op de Mac, vergelijkbaar met de app Bezel van Nonstrict.

## Tech Stack
- macOS 14+ (Sonoma minimaal)
- Swift 5.9 + SwiftUI voor UI
- libimobiledevice voor USB/lockdown communicatie
- IOKit voor USB-apparaatdetectie
- VideoToolbox voor H.264 stream decoding
- Metal of AVSampleBufferDisplayLayer voor rendering
- Swift Package Manager voor dependencies

## Vereisten
- iPhone 17 compatibel (iOS 18)
- MacBook Apple Silicon (M1/M4) geoptimaliseerd
- Minimale latency via USB
- Entitlements correct configureren (USB, camera, screen recording)

## Projectstructuur
Maak de volgende bestandsstructuur:
iPhoneMirror/
├── iPhoneMirrorApp.swift          // App entry point
├── ContentView.swift              // Hoofd SwiftUI view
├── MirrorView.swift               // Metal/AVLayer render view
├── DeviceManager.swift            // USB detectie + pairing
├── StreamDecoder.swift            // VideoToolbox H.264 decoding
├── LockdownService.swift          // libimobiledevice communicatie
├── iPhoneMirror.entitlements      // USB + screen recording permissies
└── Info.plist                     // NSCameraUsage, NSScreenCaptureUsage

## Stap 1: USB Apparaatdetectie (IOKit)
Implementeer in DeviceManager.swift:
- Detecteer aangesloten Apple iOS-apparaten via IOKit met vendor ID 0x05AC (Apple)
- Gebruik IOServiceAddMatchingNotification voor hot-plug detectie (plug in/out)
- Extraheer UDID, naam en model identifier via IORegistry
- Publiceer als @Published var devices: [iOSDevice] voor SwiftUI binding
- iOSDevice model: struct met udid: String, name: String, model: String, isConnected: Bool

## Stap 2: Pairing via libimobiledevice
Implementeer in LockdownService.swift:
- Integreer libimobiledevice als system library via SPM of via brew-installed headers
- Gebruik lockdownd_client_new_with_handshake() voor verbinding
- Controleer pairing status met lockdownd_validate_pair()
- Start service com.apple.instruments.remoteserver.dvtsecurearchive voor screen mirroring
- Handle Trust-dialog op iPhone (user interactie vereist, geef instructie in UI)
- Return foutmelding als telefoon niet vertrouwd is

## Stap 3: Screen Mirroring Stream
Implementeer in StreamDecoder.swift:
- Maak verbinding met screenshotservice (com.apple.screenshotr) of instruments remote server
- Ontvang raw H.264 encoded video frames via de lockdown-service socket
- Gebruik VTDecompressionSessionCreate() voor hardware-accelerated H.264 decoding op Apple Silicon
- Converteer decoded CMSampleBuffer naar CVPixelBuffer
- Stuur frames door via callback/delegate naar MirrorView met minimale latency
- Target latency: < 100ms

## Stap 4: Rendering
Implementeer in MirrorView.swift:
- NSViewRepresentable wrapper om AVSampleBufferDisplayLayer te embedden in SwiftUI
- Gebruik AVSampleBufferDisplayLayer.enqueue(sampleBuffer) voor frame rendering
- Behoud correcte aspect ratio van iPhone scherm
- Ondersteun rotatie (portrait/landscape) via CMSampleBuffer metadata
- Voeg optionele iPhone bezel overlay toe als NSImage op basis van model identifier

## Stap 5: SwiftUI Interface
Implementeer in ContentView.swift:
- Sidebar links met lijst van gedetecteerde devices (@Published uit DeviceManager)
- Hoofd area toont MirrorView van geselecteerde device
- Status indicator: Zoeken → Gevonden → Koppelen → Gespiegeld
- Knop "Vertrouw Mac op iPhone" met uitleg als pairing fails
- Toolbar met: Schermafbeelding, Opname starten/stoppen, Roteer
- Menubar item in statusbar voor snelle toegang

## Stap 6: Entitlements & Permissions
Configureer iPhoneMirror.entitlements:
<key>com.apple.security.device.usb</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
Voeg toe aan Info.plist:
- NSCameraUsageDescription
- NSScreenCaptureUsageDescription  
- NSMicrophoneUsageDescription

## Stap 7: libimobiledevice Bridge
- Maak een C-bridging header (iPhoneMirror-Bridging-Header.h)
- Import libimobiledevice headers: libimobiledevice/lockdown.h, libimobiledevice/libimobiledevice.h
- Linker flags: -limobiledevice-2.0 -lusbmuxd-2.0
- Wrap C-functies in Swift classes met proper memory management (idevice_free, etc.)

## Foutafhandeling
- Device niet vertrouwd → toon stap-voor-stap instructie met animatie
- Stream onderbroken → auto-reconnect na 2 seconden
- libimobiledevice niet geïnstalleerd → toon brew install instructie
- iOS versie niet ondersteund → toon melding

## Extra (indien tijd)
- Sla screenshots op als PNG naar Desktop of gekozen locatie
- Schermopname via AVAssetWriter naar .mp4
- Toon iPhone bezel-overlay (device frame) op basis van model

Begin met een volledig werkend Xcode project. Maak alle bestanden aan en geef werkende code. Start met DeviceManager.swift en LockdownService.swift als fundament.
