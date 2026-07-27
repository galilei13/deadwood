# Deadwood 1.0.0

Deadwood helps you find the files and folders consuming your Mac's storage,
understand them in three complementary views, and clean them up safely.

## Highlights

- Fast parallel scans with live item, byte, path, and elapsed-time progress.
- Hierarchical tree, interactive treemap, and top-100 largest-files views.
- Native Quick Look and Finder integration.
- Multi-selection with Trash and confirmed permanent deletion.
- Honest allocated-size accounting without following symlinks or crossing volumes.
- Optional crypto support page; all application features remain free.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon (`arm64`) only

## Installation

1. Download `Deadwood-1.0.0.dmg` and its published SHA-256 checksum.
2. Verify the checksum.
3. Open the DMG and drag Deadwood to Applications.
4. Try to open Deadwood once.
5. Because 1.0.0 is ad-hoc signed and not Apple-notarized, open
   **System Settings → Privacy & Security** and choose **Open Anyway** only if
   you trust the downloaded release.

The final SHA-256 value will be added to the GitHub Release before publication.

## Known limitations

- Hard-linked files are counted once per link.
- APFS clone files are counted at full size for each clone.
- Scan option changes apply to the next scan.
- The official 1.0.0 binary does not support Intel Macs.

## License and support

Deadwood is open-source software released under the MIT License. Donations are
optional and never unlock features.
