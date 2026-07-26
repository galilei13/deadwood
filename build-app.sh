#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building Deadwood (release)..."
swift build -c release

APP_NAME="Deadwood"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

if [ ! -f "Assets/AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift scripts/make-icon.swift
fi

rm -rf dist
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
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
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
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

# Ad-hoc signature gives the app a stable identity so permission grants
# (e.g. Full Disk Access) survive rebuilds.
codesign --force --sign - "${APP_BUNDLE}"

echo ""
echo "Done! App bundle created at: ${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
