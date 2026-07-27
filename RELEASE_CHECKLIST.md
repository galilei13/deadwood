# Deadwood 1.0.0 Release Checklist

Do not create the `v1.0.0` tag until every required item below is complete.

## Product identity

- [x] Set the marketing version to `1.0.0`.
- [x] Add the copyright owner and MIT license to the app metadata.
- [x] Include the MIT license in the repository.
- [x] Freeze the bundle identifier as `io.github.galilei13.deadwood`.
- [ ] Replace the current app icon and verify it at 16, 32, 128, 256, 512, and 1024 px.

## Build and distribution

- [x] Build the release configuration successfully.
- [x] Verify the local ad-hoc code signature.
- [ ] Build a universal `arm64` + `x86_64` app, or explicitly document Apple Silicon-only support.
- [ ] Obtain a `Developer ID Application` certificate.
- [ ] Sign the app with the hardened runtime and a timestamp.
- [ ] Build `Deadwood-1.0.0.dmg`.
- [ ] Submit the DMG to Apple's notary service and staple the ticket.
- [ ] Verify the final artifacts:

  ```bash
  codesign --verify --deep --strict --verbose=2 dist/Deadwood.app
  spctl --assess --type execute --verbose=4 dist/Deadwood.app
  xcrun stapler validate dist/Deadwood-1.0.0.dmg
  shasum -a 256 dist/Deadwood-1.0.0.dmg
  ```

- [ ] Download the uploaded DMG and install it on a clean macOS user account.

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
- [ ] Add and independently verify each public wallet address and network.
- [ ] Test address copying on desktop and mobile browsers.
- [ ] Publish the GitHub Pages site and test the in-app Donate link.

## Open-source repository

- [x] Document features, source builds, screenshots, limitations, and the MIT license.
- [ ] Create the public GitHub repository and add its remote.
- [ ] Add `CONTRIBUTING.md`, `SECURITY.md`, and issue templates.
- [ ] Enable GitHub Actions and GitHub Pages.
- [ ] Configure the repository description, topics, social preview, and website URL.
- [ ] Review every tracked file and the full commit history for sensitive data.

## GitHub release

- [ ] Write `CHANGELOG.md` and the `1.0.0` release notes.
- [ ] Merge the release commit into `main`.
- [ ] Create the annotated `v1.0.0` tag from the exact tested commit.
- [ ] Create a draft GitHub Release and attach the notarized DMG and SHA-256 checksum.
- [ ] Re-download and verify the published asset before publishing the release.
