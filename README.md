# AppShowCase

Toon het scherm van een **iPhone/iPad** of **Android-toestel** live op je Mac, in een echt toestelframe. Bedoeld voor demo's (Teams/Zoom/beamer) en testen.

- Eén venster per toestel: kies het venster bij "venster delen", of deel je hele scherm om iOS en Android naast elkaar te laten zien.
- Werkt via USB, zonder app op het toestel.
- Alleen kijken, niet bedienen.
- macOS 14 (Sonoma) of nieuwer, Intel en Apple Silicon.

> **Status:** in ontwikkeling. Zie [Roadmap](#roadmap).

## Installeren (vanaf de broncode)

Benodigd: Xcode 16 of nieuwer.

```bash
git clone https://github.com/GvdHengel/AppShowcase.git ~/Developer/AppShowCase
cd ~/Developer/AppShowCase
./scripts/fetch-deps.sh        # downloadt adb + scrcpy-server (nodig voor Android)
open AppShowCase.xcodeproj
```

Kies in Xcode het schema **AppShowCase** en druk op ⌘R.

> Zet de projectmap **niet** in iCloud Drive: git en iCloud-synchronisatie gaan slecht samen.

## Eerste gebruik

### iPhone / iPad
1. Sluit het toestel aan met een USB-kabel.
2. Ontgrendel het en tik op **Vertrouw** als daarom gevraagd wordt.
3. Sta de **camera-toegang** toe als macOS daarom vraagt. Het iPhone-scherm komt binnen als een soort camerabron; de camera van je Mac wordt niet gebruikt.

### Android
1. Open **Instellingen → Over de telefoon** en tik 7× op **Build-nummer**.
2. Open **Instellingen → Systeem → Ontwikkelaarsopties** en zet **USB-foutopsporing** aan.
3. Sluit het toestel aan en kies **Toestaan** in de melding op het toestel (vink "Altijd toestaan" aan).

AppShowCase gebruikt bij voorkeur een al geïnstalleerde `adb` (Android Studio of Homebrew), zodat het niet botst met Android Studio. Is die er niet, dan wordt de meegeleverde `adb` uit `Vendor/` gebruikt.

## Bekende beperkingen

- iOS: het toestel moet ontgrendeld zijn; tegelijk QuickTime gebruiken voor hetzelfde toestel kan conflicteren (een duidelijke melding hiervoor staat gepland).
- iOS: het scherm wakker houden of aanrakingen tonen kan niet vanaf de Mac (Android wel).
- De app is niet door Apple genotariseerd. Bij een gedownloade build: **Systeeminstellingen → Privacy en beveiliging → Open toch**.

## Roadmap

| Fase | Inhoud | Status |
|---|---|---|
| 0 | Fundament: project, structuur, vensters, menubalk | ✅ |
| 1 | iOS live beeld | ✅ |
| 2 | Android live beeld (scrcpy) | 🔨 te testen |
| 3 | Echte toestelframes | ⏳ |
| 4 | Screenshot, opname, demo-functies | ⏳ |
| 5 | Afwerking en release-build | ⏳ |

## Met dank aan

- [scrcpy](https://github.com/Genymobile/scrcpy) van Genymobile (Apache-2.0): de server die het Android-scherm streamt.
- Android SDK Platform-Tools (`adb`) van Google: wordt bij het bouwen gedownload, niet meegeleverd.

## Licentie

MIT. Zie [LICENSE](LICENSE). Zie [NOTICE](NOTICE) voor componenten van derden.
