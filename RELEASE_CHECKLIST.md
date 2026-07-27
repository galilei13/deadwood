# Deadwood 1.0.0 Release Checklist

Do not create the `v1.0.0` tag until every required item below is complete.

## Product identity

- [x] Set the marketing version to `1.0.0`.
- [x] Add the copyright owner and MIT license to the app metadata.
- [x] Include the MIT license in the repository.
- [x] Freeze the bundle identifier as `io.github.galilei13.deadwood`.
- [x] Replace the app icon and verify it at 16, 32, 128, 256, 512, and 1024 px.

## Build and distribution

- [x] Build the release configuration successfully.
- [x] Verify the local ad-hoc code signature.
- [x] Ship and document the official `1.0.0` build as Apple Silicon `arm64` only.
- [x] Document that `1.0.0` is ad-hoc signed and not Apple-notarized.
- [x] Build the local `Deadwood-1.0.0.dmg` release candidate.
- [x] Verify the mounted release candidate, app metadata, architecture, ad-hoc
  signature, icon, Applications link, disk-image integrity, and SHA-256 checksum:

  ```bash
  test "$(lipo -archs dist/Deadwood.app/Contents/MacOS/Deadwood)" = "arm64"
  codesign --verify --deep --strict --verbose=2 dist/Deadwood.app
  hdiutil verify dist/Deadwood-1.0.0.dmg
  shasum -a 256 dist/Deadwood-1.0.0.dmg
  ```

- [x] Install, launch, and smoke-test the release candidate on the current macOS
  system.
- [ ] Rebuild and verify the final DMG after completing manual QA.
- [ ] Verify the documented **Open Anyway** flow on a clean macOS user account.
- [ ] Download the uploaded DMG and install it on a clean macOS user account.

### Future distribution trust (not blocking 1.0.0)

- [ ] Join the Apple Developer Program and obtain a `Developer ID Application` certificate.
- [ ] Sign a future release with the hardened runtime and a trusted timestamp.
- [ ] Submit that signed release to Apple's notary service and staple its ticket.

## Quality

- [x] Pass the automated scanner, model, treemap, and support-link tests.
- [ ] Test on macOS 14 and the latest supported macOS release.
- [ ] Test a large home-folder scan, cancellation, and rescan.
- [ ] Test external, network, and permission-restricted volumes.
- [ ] Test Quick Look, Reveal in Finder, copy path, Trash, and permanent deletion.
- [ ] Test keyboard navigation, VoiceOver labels, light appearance, and dark appearance.
- [ ] Confirm that no secrets, wallet private keys, build credentials, or personal files are committed.

## Support page

- [x] Add the in-app Donate button and static support page.
- [x] Add the GitHub funding link.
- [x] Add the four public wallet addresses, exact asset/network labels, and validated QR codes.
- [ ] Confirm ownership and receipt with a small test transfer on every network.
- [ ] Test address copying on desktop and mobile browsers.
- [x] Publish the GitHub Pages site and validate the in-app Donate URL and live
  wallet configuration.

## Open-source repository

- [x] Document features, source builds, screenshots, limitations, and the MIT license.
- [x] Create the public GitHub repository and add its remote.
- [x] Add `CONTRIBUTING.md`, `SECURITY.md`, issue forms, and a pull request template.
- [x] Enable GitHub Actions, GitHub Pages, and private vulnerability reporting.
- [x] Configure the repository description, topics, and website URL.
- [ ] Configure the repository social preview.
- [x] Scan tracked files and the full patch history for known secret patterns.
- [x] Rewrite existing commit metadata to use `blank` and the GitHub-provided noreply address.

## GitHub release

- [x] Write `CHANGELOG.md` and the `1.0.0` release notes.
- [x] Merge the release commit into `main`.
- [ ] Create the annotated `v1.0.0` tag from the exact tested commit.
- [ ] Create a draft GitHub Release and attach the ad-hoc-signed DMG and SHA-256 checksum.
- [ ] Re-download and verify the published asset before publishing the release.
