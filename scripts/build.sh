#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Swift test"
swift test

echo "==> Swift build (release, universal)"
# One download for both Apple Silicon and Intel: SwiftPM cross-builds the x86_64 slice
# alongside the host architecture and lipos them into a single executable.
if ! swift build -c release --arch arm64 --arch x86_64; then
  echo "    universal build failed; falling back to the host architecture"
  swift build -c release
fi

# --show-bin-path without the arch flags reports the single-architecture directory,
# which can still hold a stale binary, so prefer the universal product when present.
UNIVERSAL="$ROOT/.build/apple/Products/Release/Gridlet"
NATIVE="$(swift build -c release --show-bin-path)/Gridlet"
BIN="$NATIVE"
if [ -f "$UNIVERSAL" ] && lipo -archs "$UNIVERSAL" 2>/dev/null | grep -q x86_64; then
  BIN="$UNIVERSAL"
fi
echo "    binary: $(lipo -archs "$BIN" 2>/dev/null || echo unknown)"
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

# Signing identity: a stable self-signed cert keeps the same code requirement across
# rebuilds, so macOS does not drop Gridlet's Accessibility grant every time. Falls back to
# ad-hoc when the identity cannot be created (ad-hoc = one manual re-grant per build).
echo "==> Sign"
SIGN_IDENTITY=""
if IDENTITY_LINE="$(./scripts/dev-signing-identity.sh 2>/dev/null)"; then
  SIGN_IDENTITY="$IDENTITY_LINE"
fi
if [ -n "$SIGN_IDENTITY" ]; then
  echo "    identity: $SIGN_IDENTITY"
  KEYCHAIN="${GRIDLET_KEYCHAIN:-$HOME/Library/Keychains/gridlet-dev.keychain-db}"
  security unlock-keychain -p "${GRIDLET_KEYCHAIN_PASSWORD:-gridlet-dev}" "$KEYCHAIN" >/dev/null 2>&1 || true
  codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$KEYCHAIN" "$APP"
else
  echo "    identity: ad-hoc (Accessibility must be re-granted after each build)"
  codesign --force --deep --sign - "$APP"
fi
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
