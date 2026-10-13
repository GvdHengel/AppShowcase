#!/bin/sh
# Xcode build-fase: kopieert adb + scrcpy-server uit ./Vendor in de app-bundle.
# Ontbreken ze, dan bouwt de app gewoon (iOS werkt dan wel, Android niet) met een waarschuwing.
set -eu

VENDOR="${SRCROOT}/Vendor"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$DEST"

for f in adb scrcpy-server scrcpy-server.version; do
  if [ -f "$VENDOR/$f" ]; then
    ditto "$VENDOR/$f" "$DEST/$f"
  else
    echo "warning: Vendor/$f ontbreekt — draai ./scripts/fetch-deps.sh (nodig voor Android)"
  fi
done

if [ -f "$DEST/adb" ]; then
  chmod 755 "$DEST/adb"
fi
