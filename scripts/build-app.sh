#!/usr/bin/env bash
# Builds "build/Mouse Shaker.app" from the SwiftPM executable. Works with Command Line Tools
# only (no Xcode). Signs ad-hoc unless SIGN_ID names a codesigning identity.
#
# ARCHS="arm64 x86_64" produces a universal binary; the default is the host architecture only.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-$(uname -m)}"
APP="build/Mouse Shaker.app"
ICON="build/AppIcon.icns"

# One build per architecture, then merged with lipo. Multi-arch `swift build --arch a --arch b`
# needs Xcode's build system, which the Command Line Tools do not ship.
SLICES=()
for arch in $ARCHS; do
  swift build -c "$CONFIG" --triple "$arch-apple-macosx13.0"
  SLICES+=("$(swift build -c "$CONFIG" --triple "$arch-apple-macosx13.0" --show-bin-path)/MouseShaker")
done
mkdir -p build
lipo -create "${SLICES[@]}" -output build/MouseShaker

if [[ ! -f "$ICON" || scripts/make-icon.swift -nt "$ICON" ]]; then
  mkdir -p build
  swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv build/MouseShaker "$APP/Contents/MacOS/MouseShaker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

codesign --force --sign "${SIGN_ID:--}" --identifier dev.dumorro.mouseshaker "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/MouseShaker"))"
