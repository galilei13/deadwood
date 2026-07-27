# Changelog

All notable changes to Deadwood are documented in this file.

## [Unreleased]

## [1.0.0] - Unreleased

### Added

- Native Apple Silicon macOS disk-space analyzer built with SwiftUI.
- Parallel, cancellation-aware scanning with live progress.
- Tree, treemap, and largest-files views with synchronized selection.
- Quick Look, Finder reveal, path copying, Trash, and confirmed permanent deletion.
- Drive capacity, quick-location, recent-scan, and Full Disk Access helpers.
- Configurable hidden-file and package-content scanning.
- Optional crypto support page for BTC, BNB, USDT on TRON, and POL.
- Automated scanner, model, layout, and support-link tests.
- GitHub Actions workflows for continuous integration and GitHub Pages.

### Security

- Scans do not follow symlinks or cross volume boundaries.
- Repeated filesystem identities are skipped to avoid double counting.
- Permanent deletion requires confirmation.
- Donation addresses and QR codes are stored as public, reviewable repository data.

### Distribution

- Requires macOS 14 or later and an Apple Silicon Mac.
- Version 1.0.0 is ad-hoc signed and is not Apple-notarized.

[Unreleased]: https://github.com/galilei13/deadwood/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/galilei13/deadwood/releases/tag/v1.0.0
