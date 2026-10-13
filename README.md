# AppShowCase

Toon het scherm van een **iPhone/iPad** of **Android-toestel** live op je Mac, in een toestelframe. Bedoeld voor demo's (Teams, Zoom, beamer) en testen.

- **Eén venster per toestel**: kies het venster bij "venster delen", of deel je hele scherm om iPhone en Android naast elkaar te laten zien.
- **Via USB**, zonder app op het toestel. Alleen kijken, niet bedienen.
- **Toestelframes** (iPhone met notch, eiland of thuisknop; Android met randen of camera-gaatje; tablet), automatisch gekozen en per toestel aan te passen. Draait mee als je het toestel kantelt.
- **Achtergrond** donker, licht of transparant (alleen het toestel zweeft op je bureaublad).
- **Schermafbeelding** (⇧⌘S) en **opname** (⇧⌘R) mét toestelframe.
- **Android-demo**: scherm aan houden, aanrakingen tonen, schone statusbalk (9:41, volle batterij). Wordt na afloop teruggezet.
- macOS 14 (Sonoma) of nieuwer, **Intel en Apple Silicon**.

## Downloaden (zonder Xcode)

1. Download de nieuwste `AppShowCase-x.y.z.zip` via [Releases](https://github.com/GvdHengel/AppShowcase/releases).
2. Pak uit en sleep **AppShowCase** naar **Programma's**.
3. Open de app. Omdat de app niet bij Apple is aangemeld (geen notarisatie), blokkeert macOS hem de eerste keer:
   open **Systeeminstellingen → Privacy en beveiliging**, scroll naar beneden en klik bij AppShowCase op **Open toch**.
   *Alternatief in Terminal:* `xattr -dr com.apple.quarantine /Applications/AppShowCase.app`
4. Sta **camera-toegang** toe als macOS daarom vraagt (zie hieronder waarom).

Voor Android is `adb` nodig. De release bevat er een; heb je Android Studio of Homebrew (`brew install android-platform-tools`), dan gebruikt AppShowCase die.

## Eerste gebruik

### iPhone / iPad
1. Sluit het toestel aan met een USB-kabel.
2. Ontgrendel het en tik op **Vertrouw**.
3. Sta **camera-toegang** (en eventueel microfoon) toe. macOS levert het iPhone-scherm aan als camerabron; de camera van je Mac wordt niet gebruikt en er wordt geen geluid opgenomen.

### Android
1. Open **Instellingen → Over de telefoon** en tik 7× op **Build-nummer**.
2. Open **Instellingen → Systeem → Ontwikkelaarsopties** en zet **USB-foutopsporing** aan.
3. Sluit het toestel aan en tik op **Toestaan** (vink "Altijd toestaan" aan).

Een venster per toestel opent vanzelf (uit te zetten in Instellingen). Anders: **Apparatenlijst** → **Toon**.

## Gebruik

| Wat | Hoe |
|---|---|
| Schermafbeelding mét frame | ⇧⌘S of camera-knop — PNG in `Afbeeldingen/AppShowCase` én op het klembord |
| Opname mét frame | ⇧⌘R of opnameknop — `.mov` in `Films/AppShowCase`; tijdens opname staat onderin een rode balk met **Stop** |
| Frame, achtergrond, altijd bovenop, venstergrootte | Menu **Weergave** in de werkbalk, of **rechtsklik** op het toestel |
| Android-demo-opties | Zelfde menu, sectie **Android-demo** |
| Hulp | **Help → AppShowCase-hulp** (⌘?) |
| Instellingen | **AppShowCase → Instellingen** (⌘,): auto-openen, klembord, Android-beeldkwaliteit, mappen |

## Problemen oplossen

- **iPhone verschijnt niet**: controleer camera-toegang (Systeeminstellingen → Privacy en beveiliging → Camera), ontgrendel de iPhone, tik op Vertrouw, probeer een andere kabel.
- **Geen iPhone-beeld terwijl QuickTime open is**: QuickTime kan het scherm bezet houden. AppShowCase toont dan een melding met **Sluit QuickTime**; daarna verbindt het venster vanzelf opnieuw.
- **Android: "Tik op Toestaan"**: bevestig de melding op het toestel. Geen melding? Kabel eruit en weer erin.
- **Android: "adb niet gevonden"**: installeer Android Studio of `brew install android-platform-tools`.
- **Android-beeld hapert**: kies in Instellingen een lagere beeldkwaliteit of gebruik een andere kabel.

## Zelf bouwen (ontwikkelaars)

Benodigd: Xcode 16 of nieuwer.

```bash
git clone https://github.com/GvdHengel/AppShowcase.git ~/Developer/AppShowCase
cd ~/Developer/AppShowCase
./scripts/fetch-deps.sh        # downloadt adb + scrcpy-server (niet in git)
open AppShowCase.xcodeproj     # ⌘R om te starten, ⌘U voor de tests
```

> Zet de projectmap **niet** in iCloud Drive: git en iCloud-synchronisatie gaan slecht samen.

**Release maken** (Universal zip, ad-hoc ondertekend):

```bash
./scripts/build-release.sh             # → build/AppShowCase-<versie>.zip
./scripts/build-release.sh --publish   # idem + GitHub Release (na `gh auth login`)
```

Zie [CLAUDE.md](CLAUDE.md) voor architectuur en technische keuzes.

## Bekende beperkingen

- iOS: het toestel moet ontgrendeld zijn; scherm wakker houden en aanrakingen tonen kan niet vanaf de Mac (Android wel).
- Liggend staat de bovenkant van het toestelframe altijd links.
- De app is niet genotariseerd (zie Downloaden).

## Roadmap

| Fase | Inhoud | Status |
|---|---|---|
| 0 | Fundament: project, structuur, vensters, menubalk | ✅ |
| 1 | iOS live beeld | ✅ |
| 2 | Android live beeld (scrcpy) | ✅ |
| 3 | Toestelframes | ✅ |
| 4 | Schermafbeelding, opname, demo-functies | ✅ |
| 5 | Afwerking: QuickTime-melding, hulp, instellingen, icoon, release | ✅ |
| 6 | Automatische toestelherkenning (exact model) en officiële frames importeren | 💡 idee |

## Met dank aan

- [scrcpy](https://github.com/Genymobile/scrcpy) van Genymobile (Apache-2.0): de server die het Android-scherm streamt.
- Android SDK Platform-Tools (`adb`) van Google.

## Licentie

MIT. Zie [LICENSE](LICENSE). Zie [NOTICE](NOTICE) voor componenten van derden.
