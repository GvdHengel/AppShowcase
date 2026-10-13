# CLAUDE.md — AppShowCase

macOS-app (SwiftUI) die het scherm van via USB aangesloten iOS- en Android-toestellen live toont in een toestelframe, voor demo's. Alleen kijken, geen bediening.

## Afspraken

- **Taal:** UI-teksten, commentaar en documentatie in het Nederlands; code-identifiers in het Engels.
- **Doelplatform:** macOS 14+, Universal (arm64 + x86_64). Geen API's nieuwer dan macOS 14 zonder `#available`-fallback.
- **Geen Swift-packages.** Alleen Apple-frameworks. Android loopt via `adb` + `scrcpy-server` (in `Vendor/`, gedownload met `scripts/fetch-deps.sh`, nooit committen).
- **Signing:** ad-hoc (`-`), hardened runtime aan, sandbox uit. Entitlements in `Config/AppShowCase.entitlements`.
- **Xcode-project** gebruikt folder-gesynchroniseerde groepen: nieuwe bestanden in `AppShowCase/` of `AppShowCaseTests/` worden automatisch opgepakt; `project.pbxproj` hoeft daarvoor niet aangepast te worden.
- **Concurrency:** UI-state `@MainActor`; capture/decoding op eigen seriële queues; nooit `AVCaptureSession.startRunning()` op de main thread.
- **Tests:** Swift Testing (`import Testing`). Protocol- en parsercode moet zonder hardware testbaar zijn (fixtures).

## Architectuur

Beide platforms leveren een stroom `CVPixelBuffer`-frames via één `FrameSource`-protocol; weergave, toestelframe, screenshot en opname zijn gedeeld.

```
AppShowCase/
├── App/        entry point: Apparaten-venster, WindowGroup per toestel (DeviceID), MenuBarExtra
├── Core/       Device/DeviceID/DeviceInfo, DeviceRegistry (@Observable), FrameSource (fase 1)
├── iOS/        (fase 1) CoreMediaIO + AVCaptureSession + AVCaptureVideoDataOutput
├── Android/    (fase 2) ADB/ en Scrcpy/: launcher, protocol-parser, VTDecompressionSession
├── Rendering/  VideoDisplayView (AVSampleBufferDisplayLayer), DeviceFrameView (behuizing + beeld + uitsparing)
├── Frames/     DeviceFrameStyle (catalogus), FrameMatcher (auto-keuze), FrameLayout (geometrie, ook liggend)
├── Features/   FramedImage (uitsnede, FramedCanvas, renderer), ScreenshotService, FramedRecorder (AVAssetWriter + Core Image)
└── UI/         SwiftUI-views
```

## Toestelframes

- Eigen, generieke tekeningen in code (geen logo's of officiële afbeeldingen) zodat ze in de repo mogen.
- Rekenen in staande coördinaten; liggend = canvas 90° tegen de klok in gedraaid (bovenkant toestel links). Het videobeeld komt al liggend binnen en wordt niet gedraaid.
- Keuze en achtergrond per toestel in UserDefaults: `frame.<DeviceID>` ("auto" of frame-id) en `background.<DeviceID>`.

## Demo-functies

- `MirrorSession.frameTap` bewaart het laatste frame (schermafbeelding) en geeft frames door aan de opname.
- Schermafbeelding/opname renderen het frame met `ImageRenderer` via `DeviceFrameView(parts:)`; de opname stelt per frame samen met Core Image (behuizing + video met afgeronde-hoekenmasker + notch/eiland). Uitvoer: H.264 `.mov`, max. 2160 px lange zijde, even maten.
- Android-demomodus (`AndroidDemoMode`): bewaart oorspronkelijke `settings`, zet ze terug bij uitzetten, venster sluiten en (via `ADBCleanup.registerRestore`) bij afsluiten.

## Belangrijke technische lessen (uit de prototypes)

### iOS
- Zet **vóór** elke discovery `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1` (CoreMediaIO), anders verschijnt het schermdevice niet.
- Vraag camera-toegang **eerst** en ontdek pas daarna; zonder toestemming geeft `DiscoverySession` een lege lijst.
- Schermdevice = `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed)`. Het `.video`-device met "Camera" in de naam is Continuity Camera, niet het scherm.
- Geen audio-output toevoegen (echo). Het schermdevice is wel *muxed* (beeld + geluid): daarom staan `NSMicrophoneUsageDescription` en de entitlement `device.audio-input` erin.
- Weergave via `AVCaptureVideoDataOutput` (BGRA) → `AVSampleBufferDisplayLayer` met `DisplayImmediately`; zelfde pad als Android.
- Onschadelijke console-ruis: `AddInstanceForFactory`, `CMIO_DAL_CMIOExtension_*`, `CMIOObjectGetPropertyData Error: 2003332927`, `Fig assert "surfaceValue"`.
- Ook onschadelijk (ad-hoc signing, App Intents/Shortcuts): `connection to service named com.apple.linkd.autoShortcut`, `Unable to re-register with Process Instance Registry`, `(Fig) signalled err=-12710`, `CMIOObjectSetPropertyData property isn't settable`, `open(/private/var/db/DetachedSignatures)`.
- iPhone Xs levert 1126×2436 (één pixel opvulling t.o.v. 1125); verwaarloosbaar.

### Android (scrcpy, vastgezet op 3.3.1 — zie `scripts/fetch-deps.sh`)
- De server moet **exact** dezelfde versie hebben als de client-parameter; scrcpy 4.x heeft een ander videoprotocol (sessie-pakketten) en vraagt om aangepaste parsercode.
- Gebruik `send_frame_meta=true`: elk pakket = 12-byte header (PTS u64 met bit 63 = config, bit 62 = keyframe; lengte u32 big-endian) + precies één frame. Zonder frame-meta breken multi-slice frames (groen beeld in prototype).
- Forward-tunnel: lees eerst de dummy-byte, dan 64 bytes toestelnaam, dan 12 bytes codec-meta (codec-id, breedte, hoogte; big-endian).
- Per toestel een eigen `scid` en lokale poort; socketnaam `scrcpy_<scid als 8 hex-cijfers>`.
- Nooit `adb kill-server`, `pkill -f scrcpy` of `forward --remove-all`: alleen eigen tunnels opruimen (Android Studio kan dezelfde adb-server gebruiken).
- stdout/stderr van het server-proces continu uitlezen, anders loopt het vast.
- Implementatie: `ADBLocator` (voorkeur geïnstalleerde adb boven `Vendor/adb`), `AndroidDiscovery` (`track-devices` + `devices -l`), `ScrcpyServer` (actor: push naar `/data/local/tmp/appshowcase-scrcpy-server.jar`, `forward tcp:0`), `ScrcpyStreamParser` (puur, getest), `H264Decoder` (Annex B → AVCC → `VTDecompressionSession` → BGRA), `AndroidScrcpySource` (NWConnection; opnieuw verbinden tot de dummy-byte binnenkomt).
- Bij afsluiten ruimt `ADBCleanup` onze eigen processen en tunnels op.

## Documentatie

Plan en analyse staan in het claude.ai-project "AppShowCase" (`plan-nieuwe-app.md`, `analyse-prototypes.md`).
