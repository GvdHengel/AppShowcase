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
├── Rendering/  (fase 1) AVSampleBufferDisplayLayer-view, (fase 3) frame-compositie
├── Frames/     (fase 3) datagedreven toestelframes
├── Features/   (fase 4) screenshot, opname, Android demo-modus
└── UI/         SwiftUI-views
```

## Belangrijke technische lessen (uit de prototypes)

### iOS
- Zet **vóór** elke discovery `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1` (CoreMediaIO), anders verschijnt het schermdevice niet.
- Vraag camera-toegang **eerst** en ontdek pas daarna; zonder toestemming geeft `DiscoverySession` een lege lijst.
- Schermdevice = `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed)`. Het `.video`-device met "Camera" in de naam is Continuity Camera, niet het scherm.
- Geen audio-output toevoegen (echo). Het schermdevice is wel *muxed* (beeld + geluid): daarom staan `NSMicrophoneUsageDescription` en de entitlement `device.audio-input` erin.
- Weergave via `AVCaptureVideoDataOutput` (BGRA) → `AVSampleBufferDisplayLayer` met `DisplayImmediately`; zelfde pad als Android.
- Onschadelijke console-ruis: `AddInstanceForFactory`, `CMIO_DAL_CMIOExtension_*`, `CMIOObjectGetPropertyData Error: 2003332927`, `Fig assert "surfaceValue"`.
- Ook onschadelijk (ad-hoc signing, App Intents/Shortcuts): `connection to service named com.apple.linkd.autoShortcut`, `Unable to re-register with Process Instance Registry`.

### Android (scrcpy, vastgezet op 3.3.1 — zie `scripts/fetch-deps.sh`)
- De server moet **exact** dezelfde versie hebben als de client-parameter; scrcpy 4.x heeft een ander videoprotocol (sessie-pakketten) en vraagt om aangepaste parsercode.
- Gebruik `send_frame_meta=true`: elk pakket = 12-byte header (PTS u64 met bit 63 = config, bit 62 = keyframe; lengte u32 big-endian) + precies één frame. Zonder frame-meta breken multi-slice frames (groen beeld in prototype).
- Forward-tunnel: lees eerst de dummy-byte, dan 64 bytes toestelnaam, dan 12 bytes codec-meta (codec-id, breedte, hoogte; big-endian).
- Per toestel een eigen `scid` en lokale poort; socketnaam `scrcpy_<scid als 8 hex-cijfers>`.
- Nooit `adb kill-server`, `pkill -f scrcpy` of `forward --remove-all`: alleen eigen tunnels opruimen (Android Studio kan dezelfde adb-server gebruiken).
- stdout/stderr van het server-proces continu uitlezen, anders loopt het vast.

## Documentatie

Plan en analyse staan in het claude.ai-project "AppShowCase" (`plan-nieuwe-app.md`, `analyse-prototypes.md`).
