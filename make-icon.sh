#!/bin/bash
set -e

# Render Assets/icon.svg at every size macOS wants and pack them into Assets/Sidetone.icns.
#
# Needs `rsvg-convert` (brew install librsvg) and `iconutil` (ships with macOS). The built
# Sidetone.icns is committed, so you only need this when you change the artwork.
#
#   ./make-icon.sh            rebuild Assets/Sidetone.icns
#   ./make-icon.sh --preview  also write icon-preview-{1024,128,32,16}.png next to it (gitignored)

cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

SVG="Assets/icon.svg"
SET="Sidetone.iconset"

echo "==> rendering $SVG"
rm -rf "$SET"
mkdir "$SET"
render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$SET/$2"; }
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o Assets/Sidetone.icns

if [ "$1" = "--preview" ]; then
    for size in 1024 128 32 16; do
        rsvg-convert -w "$size" -h "$size" "$SVG" -o "icon-preview-$size.png"
    done
fi

rm -rf "$SET"
echo "==> wrote Assets/Sidetone.icns"
