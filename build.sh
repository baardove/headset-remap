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
cp -R assets/HeadsetDiagrams "$APP/Contents/Resources/HeadsetDiagrams"

# Universal binary (Apple Silicon + Intel)
swiftc -O -target arm64-apple-macos13.0 Sources/*.swift -o build/HeadsetRemap-arm64
swiftc -O -target x86_64-apple-macos13.0 Sources/*.swift -o build/HeadsetRemap-x86_64
lipo -create -output "$APP/Contents/MacOS/HeadsetRemap" \
  build/HeadsetRemap-arm64 build/HeadsetRemap-x86_64
cp Info.plist "$APP/Contents/Info.plist"

# Stable signing prevents each rebuild from invalidating Accessibility/Input
# Monitoring grants. An explicit override takes precedence. Otherwise use the
# original local certificate, or an unambiguous Apple Development identity.
SIGNING_IDENTITY="${HEADSET_REMAP_SIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if printf '%s\n' "$IDENTITIES" | grep -q '"JabraMicMute Signing"'; then
    SIGNING_IDENTITY="JabraMicMute Signing"
  elif [ "$(printf '%s\n' "$IDENTITIES" | awk '/"Apple Development:/{n++} END {print n+0}')" = 1 ]; then
    SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk '/"Apple Development:/{print $2}')"
  else
    SIGNING_IDENTITY="-"
  fi
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APP"

# Distributable zip (preserves the bundle structure and signature)
ditto -c -k --keepParent "$APP" "build/Headset-Remap.zip"

echo "Built:  $APP"
echo "Zip:    build/Headset-Remap.zip"
echo "Install: cp -R \"$APP\" /Applications/"
