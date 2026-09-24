#!/usr/bin/env bash
# Builds "build/Mouse Shaker.app" from the SwiftPM executable. Works with Command Line Tools
# only (no Xcode). Signs ad-hoc unless SIGN_ID names a codesigning identity.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Mouse Shaker.app"
ICON="build/AppIcon.icns"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [[ ! -f "$ICON" || scripts/make-icon.swift -nt "$ICON" ]]; then
  mkdir -p build
  swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MouseShaker" "$APP/Contents/MacOS/MouseShaker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

codesign --force --sign "${SIGN_ID:--}" --identifier dev.dumorro.mouseshaker "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
