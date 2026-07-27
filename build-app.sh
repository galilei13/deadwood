#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version in VERSION: $VERSION" >&2
    exit 1
fi

BUILD_NUMBER="${DEADWOOD_BUILD_NUMBER:-1}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Invalid DEADWOOD_BUILD_NUMBER: $BUILD_NUMBER" >&2
    exit 1
fi
SIGNING_IDENTITY="${DEADWOOD_SIGNING_IDENTITY:--}"

echo "Building Deadwood (release)..."
swift build -c release

APP_NAME="Deadwood"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

if [ ! -f "Assets/AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift scripts/make-icon.swift
fi

rm -rf "dist/Deadwood.app"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Deadwood</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.deadwood.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Deadwood</string>
    <key>CFBundleDisplayName</key>
    <string>Deadwood</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Deadwood scans folders you choose to show how disk space is used.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Deadwood scans folders you choose to show how disk space is used.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Deadwood scans folders you choose to show how disk space is used.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Deadwood scans external drives you choose to show how disk space is used.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Deadwood scans network volumes you choose to show how disk space is used.</string>
</dict>
</plist>
PLIST

if [ "$SIGNING_IDENTITY" = "-" ]; then
    # Ad-hoc signing keeps local builds frictionless.
    codesign --force --sign - "${APP_BUNDLE}"
    echo "Ad-hoc signed local build."
else
    # A Developer ID signature with hardened runtime is suitable for
    # notarization. The identity is intentionally supplied by the caller.
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "${APP_BUNDLE}"
    echo "Signed with Developer ID identity: $SIGNING_IDENTITY"
fi

echo ""
echo "Done! App bundle created at: ${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
