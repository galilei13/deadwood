#!/bin/bash
# Builds a known fixture in /tmp, compiles the scanner + treemap layout with
# the smoke-test harness, and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

FIXTURE=/tmp/ts-test
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/sub/deep" "$FIXTURE/.hidden" "$FIXTURE/noperm" "$FIXTURE/Fake.app/Contents"
dd if=/dev/zero of="$FIXTURE/a.bin" bs=1024 count=1024 2>/dev/null
dd if=/dev/zero of="$FIXTURE/sub/b.bin" bs=1024 count=2048 2>/dev/null
dd if=/dev/zero of="$FIXTURE/sub/deep/c.bin" bs=1024 count=512 2>/dev/null
dd if=/dev/zero of="$FIXTURE/.hidden/h.bin" bs=1024 count=256 2>/dev/null
dd if=/dev/zero of="$FIXTURE/Fake.app/Contents/x.bin" bs=1024 count=128 2>/dev/null
ln -s "$FIXTURE/sub" "$FIXTURE/link"
chmod 000 "$FIXTURE/noperm"

cleanup() {
    chmod 755 "$FIXTURE/noperm" 2>/dev/null || true
    rm -rf "$FIXTURE" /tmp/deadwood-smoketest
}
trap cleanup EXIT

swiftc -o /tmp/deadwood-smoketest \
    Sources/Deadwood/Models/FileNode.swift \
    Sources/Deadwood/Models/ScanModels.swift \
    Sources/Deadwood/Models/DriveInfo.swift \
    Sources/Deadwood/Services/DiskScanner.swift \
    Sources/Deadwood/Utilities/TreemapLayout.swift \
    scripts/smoke-test/main.swift

/tmp/deadwood-smoketest
