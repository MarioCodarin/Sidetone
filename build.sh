#!/bin/bash
set -euo pipefail

# Build (and optionally install) the Sidetone menu-bar app.
#
#   ./build.sh              build + assemble + ad-hoc sign ./Sidetone.app
#   ./build.sh --install    also replace /Applications/Sidetone.app and launch it
#
# Signing: set CODESIGN_IDENTITY to a certificate name (e.g. "Apple Development: you@example.com")
# to sign with a stable identity — this keeps the Microphone / Audio-capture / Calendar TCC grants
# sticky across rebuilds. Defaults to "-" (ad-hoc), which works locally but may re-prompt for
# permissions after every rebuild.
#   CODESIGN_IDENTITY="Apple Development: you@example.com" ./build.sh --install

cd "$(dirname "$0")"

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

APP="Sidetone.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
IDENTITY="${CODESIGN_IDENTITY:--}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
echo "==> Sidetone $VERSION ($BUILD)"
echo "==> swift build -c release --product Sidetone"
swift build -c release --product Sidetone

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/release/Sidetone" "$MACOS/Sidetone"
cp "Info.plist" "$CONTENTS/Info.plist"

if [ -f "Assets/Sidetone.icns" ]; then
    cp "Assets/Sidetone.icns" "$RESOURCES/Sidetone.icns"
else
    echo "    (no Assets/Sidetone.icns — run ./make-icon.sh to generate it)" >&2
fi

# PkgInfo: 4-char type + 4-char creator.
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [ "$IDENTITY" = "-" ]; then
    echo "==> codesign (ad-hoc, non-sandboxed)"
else
    echo "==> codesign (\"$IDENTITY\", non-sandboxed)"
fi
codesign --force --sign "$IDENTITY" --entitlements "Sidetone.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

if [ "$INSTALL" = 1 ]; then
    echo "==> installing to /Applications (quitting the running copy first)"
    osascript -e 'tell application "Sidetone" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -x Sidetone >/dev/null 2>&1 || break
        sleep 0.5
    done
    rm -rf "/Applications/Sidetone.app"
    ditto "$APP" "/Applications/Sidetone.app"
    echo "==> launching /Applications/Sidetone.app"
    open "/Applications/Sidetone.app"
fi

echo "done — $APP ($(/usr/bin/du -sh "$APP" | cut -f1))"
