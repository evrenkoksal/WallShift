#!/bin/bash
# Builds WallShift and installs it as a menu bar app bundle in ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WallShift"
DEST="${1:-$HOME/Applications}"
APP="$DEST/$APP_NAME.app"

cd "$ROOT"
echo "==> Building (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Rendering icon"
mkdir -p .build/icon.iconset
swift Scripts/make_icon.swift .build/icon.png
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s .build/icon.png --out ".build/icon.iconset/icon_${s}x${s}.png" >/dev/null
done
# Retina variants expected by iconutil
cp .build/icon.iconset/icon_32x32.png   .build/icon.iconset/icon_16x16@2x.png
cp .build/icon.iconset/icon_64x64.png   .build/icon.iconset/icon_32x32@2x.png
cp .build/icon.iconset/icon_256x256.png .build/icon.iconset/icon_128x128@2x.png
cp .build/icon.iconset/icon_512x512.png .build/icon.iconset/icon_256x256@2x.png
cp .build/icon.iconset/icon_1024x1024.png .build/icon.iconset/icon_512x512@2x.png
rm -f .build/icon.iconset/icon_64x64.png .build/icon.iconset/icon_1024x1024.png
iconutil -c icns .build/icon.iconset -o .build/AppIcon.icns

echo "==> Assembling bundle at $APP"
# Quit a running copy so the binary can be replaced.
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
