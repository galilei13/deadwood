#!/bin/bash
# Builds dist/Deadwood-<version>.dmg — the classic drag-to-Applications
# installer: app on the left, Applications shortcut on the right.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version in VERSION: $VERSION" >&2
    exit 1
fi

APP="dist/Deadwood.app"
DMG="dist/Deadwood-${VERSION}.dmg"
VOLNAME="Deadwood"
WORK_DIR="$(mktemp -d)"
STAGING="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/rw.dmg"
MOUNT_DIR="/Volumes/$VOLNAME"
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach "$MOUNT_DIR" > /dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ ! -d "$APP" ]; then
    ./build-app.sh
fi

echo "Preparing DMG contents..."
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# HiDPI TIFF (1x + 2x) — Finder then draws the background at 640x400 points
# regardless of display scale. Plain PNGs get misread as full-size points.
BG_TMP="$(mktemp -d)/bg"
swift scripts/make-dmg-background.swift "$BG_TMP" > /dev/null
sips -s dpiHeight 72 -s dpiWidth 72 "$BG_TMP.png" > /dev/null
sips -s dpiHeight 144 -s dpiWidth 144 "$BG_TMP@2x.png" > /dev/null
tiffutil -cathidpicheck "$BG_TMP.png" "$BG_TMP@2x.png" -out "$STAGING/.background/background.tiff"

echo "Creating writable DMG..."
hdiutil create -srcfolder "$STAGING" -volname "$VOLNAME" -fs HFS+ \
    -format UDRW -size 80m "$RW_DMG" > /dev/null

echo "Styling DMG window..."
if [ -e "$MOUNT_DIR" ]; then
    echo "Refusing to mount: $MOUNT_DIR already exists." >&2
    exit 1
fi
hdiutil attach "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" > /dev/null
MOUNTED=1
sleep 1

# Window content: 640x400 pt (matches the background image), +28 pt titlebar.
osascript << EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Deadwood.app" of container window to {160, 185}
        set position of item "Applications" of container window to {480, 185}
        update without registering applications
        delay 2
        set the bounds of container window to {200, 120, 840, 548}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" > /dev/null
MOUNTED=0

echo "Compressing..."
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" > /dev/null

if [ -n "${DEADWOOD_NOTARY_PROFILE:-}" ]; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$DEADWOOD_NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG"
    echo "Notarization ticket stapled."
else
    echo "Skipping notarization (DEADWOOD_NOTARY_PROFILE is not set)."
fi

echo ""
echo "Done! Installer created at: $DMG"
