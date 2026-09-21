#!/bin/bash
set -e

# Render the app icon and bundle it into Assets/Sidetone.icns.
#
# Assets/icon.swift draws a 1024x1024 master PNG (Sidetone-1024.png) with pure
# AppKit / Core Graphics. This script then downscales it to every size macOS
# wants and packs them into Sidetone.icns via iconutil.

cd "$(dirname "$0")"

MASTER="Sidetone-1024.png"
SET="Sidetone.iconset"

echo "==> rendering $MASTER from Assets/icon.swift"
swift Assets/icon.swift

echo "==> building $SET"
rm -rf "$SET"
mkdir "$SET"
sips -z 16  16   "$MASTER" --out "$SET/icon_16x16.png"      >/dev/null
sips -z 32  32   "$MASTER" --out "$SET/icon_16x16@2x.png"   >/dev/null
sips -z 32  32   "$MASTER" --out "$SET/icon_32x32.png"      >/dev/null
sips -z 64  64   "$MASTER" --out "$SET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128  "$MASTER" --out "$SET/icon_128x128.png"    >/dev/null
sips -z 256 256  "$MASTER" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256  "$MASTER" --out "$SET/icon_256x256.png"    >/dev/null
sips -z 512 512  "$MASTER" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512  "$MASTER" --out "$SET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o Assets/Sidetone.icns
rm -rf "$SET" "$MASTER"
echo "==> wrote Assets/Sidetone.icns"
