#!/bin/bash
# Builds Headset Remap.app into ./build and a distributable zip.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Headset Remap.app"
HOST_TARGET="$(uname -m)-apple-macos13.0"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon: generated once, then cached in assets/
if [ ! -f assets/AppIcon.icns ] || [ tools/makeicon.swift -nt assets/AppIcon.icns ]; then
  mkdir -p assets build/iconwork
  swiftc -O -target "$HOST_TARGET" tools/makeicon.swift -o build/iconwork/makeicon
  build/iconwork/makeicon build/iconwork/AppIcon.iconset
  iconutil -c icns build/iconwork/AppIcon.iconset -o assets/AppIcon.icns
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Universal binary (Apple Silicon + Intel)
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o build/HeadsetRemap-arm64
swiftc -O -target x86_64-apple-macos13.0 Sources/*.swift -o build/HeadsetRemap-x86_64
lipo -create -output "$APP/Contents/MacOS/HeadsetRemap" \
  build/HeadsetRemap-arm64 build/HeadsetRemap-x86_64
cp Info.plist "$APP/Contents/Info.plist"

# Prefer the self-signed "JabraMicMute Signing" cert: it gives the app a
# stable identity so the Input Monitoring grant survives rebuilds.
# Ad-hoc fallback re-triggers the permission prompt on every rebuild.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "JabraMicMute Signing"; then
  codesign --force --sign "JabraMicMute Signing" "$APP"
else
  codesign --force --sign - "$APP"
fi

# Distributable zip (preserves the bundle structure and signature)
ditto -c -k --keepParent "$APP" "build/Headset-Remap.zip"

echo "Built:  $APP"
echo "Zip:    build/Headset-Remap.zip"
echo "Install: cp -R \"$APP\" /Applications/"
