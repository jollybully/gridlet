#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Swift test"
swift test

echo "==> Swift build (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/Gridlet"
APP="$ROOT/dist/Gridlet.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/Gridlet"
chmod +x "$MACOS/Gridlet"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Original hand-drawn grid icon (NSBezierPath → PNG, then iconset via sips)
ICONSET="$ROOT/build/icon.iconset"
rm -rf "$ICONSET" "$ROOT/build"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/generate_icon.swift" "$ICONSET/icon_512x512@2x.png" 1024
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
plutil -insert CFBundleIconFile -string AppIcon "$CONTENTS/Info.plist"

echo "==> Ad hoc sign"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> plutil lint"
plutil -lint "$CONTENTS/Info.plist"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/dist/Gridlet-${VERSION}-macos.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> UI smoke gate"
"$ROOT/scripts/ui_smoke.sh"

echo "Built: $APP"
echo "Zip:   $ZIP"
