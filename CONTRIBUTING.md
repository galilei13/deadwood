# Contributing to Deadwood

Thanks for helping improve Deadwood. Bug reports, focused feature proposals,
documentation fixes, tests, and code contributions are welcome.

## Before you start

- Use the issue forms for bugs and feature requests.
- Search existing issues before opening a new one.
- Do not report security vulnerabilities in a public issue. Follow
  [SECURITY.md](SECURITY.md) instead.
- Keep pull requests focused on one problem.

## Development setup

Deadwood currently targets Apple Silicon Macs running macOS 14 or later.
Install Xcode Command Line Tools, then clone the repository and run:

```bash
swift test
swift run
```

To create the local app bundle:

```bash
./build-app.sh
open dist/Deadwood.app
```

## Making a change

1. Create a short branch from the latest `main`.
2. Reproduce the problem or describe the intended behavior.
3. Add or update tests when behavior changes.
4. Keep filesystem work off the main actor and preserve cancellation checks.
5. Never follow symlinks or cross volume boundaries during scans.
6. Run the validation commands below.
7. Open a pull request using the repository template.

```bash
swift test
swift build --configuration release
bash -n build-app.sh scripts/run-smoke-tests.sh scripts/make-dmg.sh
git diff --check
```

Do not commit build products, local editor settings, credentials, private keys,
seed phrases, or real user filesystem paths. Public donation addresses belong
only in `docs/support-config.js`.

## Pull request expectations

- Explain the user-visible problem and the chosen solution.
- Include manual test steps for UI or filesystem changes.
- Call out destructive behavior, privacy implications, or compatibility changes.
- Update `README.md` and `CHANGELOG.md` when appropriate.
- Do not change `VERSION` unless the pull request prepares a release.

By contributing, you agree that your contribution is licensed under the
project's [MIT License](LICENSE).
