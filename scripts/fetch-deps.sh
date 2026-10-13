#!/bin/bash
# Downloadt de Android-hulpmiddelen naar ./Vendor (staat NIET in git).
#   - adb            uit Google's Android SDK Platform-Tools (macOS, universal)
#   - scrcpy-server  uit de scrcpy-release van Genymobile (Apache-2.0)
#
# Gebruik:  ./scripts/fetch-deps.sh
# Daarna bouwt Xcode ze automatisch mee in de app (zie scripts/embed-vendor.sh).
#
# LET OP: de app spreekt het videoprotocol van precies deze scrcpy-versie.
# Wijzig SCRCPY_VERSION alleen samen met de protocolcode (scrcpy 4.x heeft een ander protocol).
set -euo pipefail

SCRCPY_VERSION="3.3.1"
# Optioneel vastpinnen: zet de sha256 van scrcpy-server hier na de eerste download.
SCRCPY_SHA256="${SCRCPY_SHA256:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$VENDOR"

echo "▸ adb downloaden (Android SDK Platform-Tools)…"
curl -fL --progress-bar -o "$TMP/platform-tools.zip" \
  "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q "$TMP/platform-tools.zip" "platform-tools/adb" -d "$TMP"
cp "$TMP/platform-tools/adb" "$VENDOR/adb"
chmod 755 "$VENDOR/adb"
echo "  adb: $(lipo -archs "$VENDOR/adb" 2>/dev/null || echo 'architectuur onbekend')"
"$VENDOR/adb" version | head -n 1 | sed 's/^/  /'

echo "▸ scrcpy-server v$SCRCPY_VERSION downloaden…"
curl -fL --progress-bar -o "$VENDOR/scrcpy-server" \
  "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION/scrcpy-server-v$SCRCPY_VERSION"
ACTUAL_SHA="$(shasum -a 256 "$VENDOR/scrcpy-server" | awk '{print $1}')"
if [[ -n "$SCRCPY_SHA256" && "$ACTUAL_SHA" != "$SCRCPY_SHA256" ]]; then
  echo "✗ Checksum klopt niet voor scrcpy-server!"
  echo "  verwacht: $SCRCPY_SHA256"
  echo "  gekregen: $ACTUAL_SHA"
  rm -f "$VENDOR/scrcpy-server"
  exit 1
fi
echo "  sha256: $ACTUAL_SHA"
echo "$SCRCPY_VERSION" > "$VENDOR/scrcpy-server.version"

echo "✓ Klaar. Bestanden in Vendor/:"
ls -lh "$VENDOR" | tail -n +2 | sed 's/^/  /'
