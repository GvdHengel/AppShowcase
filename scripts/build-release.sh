#!/bin/bash
# Bouwt een Universal release (Intel + Apple Silicon) van AppShowCase als zip.
#
# Gebruik:
#   ./scripts/build-release.sh             → build/AppShowCase-<versie>.zip
#   ./scripts/build-release.sh --publish   → idem, en maakt een GitHub Release (vereist `gh auth login`)
#
# De app is ad-hoc ondertekend (geen Apple Developer-account): bij de eerste start op een
# andere Mac moet de gebruiker hem eenmalig toestaan (zie README → "Downloaden").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
cd "$ROOT"

if [[ ! -f Vendor/adb || ! -f Vendor/scrcpy-server ]]; then
  echo "▸ Android-hulpmiddelen ontbreken, eerst downloaden…"
  ./scripts/fetch-deps.sh
fi

echo "▸ Release bouwen (arm64 + x86_64)…"
rm -rf "$BUILD/Release"
xcodebuild \
  -project AppShowCase.xcodeproj \
  -target AppShowCase \
  -configuration Release \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  SYMROOT="$BUILD" \
  -quiet \
  build

APP="$BUILD/Release/AppShowCase.app"
[[ -d "$APP" ]] || { echo "✗ $APP niet gevonden"; exit 1; }

echo "▸ Controleren…"
ARCHS_FOUND="$(lipo -archs "$APP/Contents/MacOS/AppShowCase")"
echo "  architecturen: $ARCHS_FOUND"
[[ "$ARCHS_FOUND" == *x86_64* && "$ARCHS_FOUND" == *arm64* ]] || { echo "✗ Geen Universal binary"; exit 1; }
[[ -f "$APP/Contents/Resources/adb" ]] || echo "  ⚠️  adb zit niet in de app (Android werkt dan alleen met een geïnstalleerde adb)"
[[ -f "$APP/Contents/Resources/scrcpy-server" ]] || { echo "✗ scrcpy-server ontbreekt in de app"; exit 1; }
codesign --verify --strict "$APP"
echo "  handtekening: ok (ad-hoc)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$BUILD/AppShowCase-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "✓ Klaar: $ZIP"
echo "  sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "  grootte: $(du -h "$ZIP" | awk '{print $1}')"

if [[ "${1:-}" == "--publish" ]]; then
  echo "▸ GitHub Release v$VERSION maken…"
  NOTES="$ROOT/docs/release-notes-$VERSION.md"
  if [[ -f "$NOTES" ]]; then
    gh release create "v$VERSION" "$ZIP" --title "AppShowCase $VERSION" --notes-file "$NOTES"
  else
    gh release create "v$VERSION" "$ZIP" --title "AppShowCase $VERSION" --generate-notes
  fi
fi
