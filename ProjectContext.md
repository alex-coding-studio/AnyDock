# AnyDock Project Context

## Purpose

AnyDock receives images, UTF-8 text snippets, HTTP/HTTPS links and arbitrary files shared from an iPhone over the local network and shows them in a native macOS menu bar tray. Users browse, select, drag original files into other apps, copy, preview with Quick Look or reveal in Finder. The user-visible behaviour contracts are in `docs/PROJECT.md`; contributor rules and naming are in `AGENTS.md`.

## Technical foundation

- Swift 6 language mode, SwiftPM tools version 6.0, macOS 14+ deployment target. The development toolchain is Xcode 27.2 / Apple Swift 6.4.2; source builds need a compatible compiler and an SDK containing the macOS 26 glass APIs. `Package.swift` is the package source of truth.
- Native AppKit controls, materials, selection, dragging, Quick Look and sharing APIs. The public MIT PockyFoundation package supplies shared spacing, matching macOS shape and motion roles, elevation, and pure masonry/grid placement. Product-specific Metrics remain local; AnyDock does not use CXDesignKit. SnapKit is the third-party Auto Layout DSL, declared directly by the app and its layout-test target. The committed Package.resolved pins both dependencies; SnapKit uses an exact release. Its privacy resource bundle and full MIT license ship inside the assembled app.
- Network.framework HTTP receiver on default TCP port 8765, configurable in Settings, with no automatic port switching.
- Received originals live in the user-selected receive folder, outside the checkout. Connection configuration lives in Application Support; the other preferences use UserDefaults (see Naming in `AGENTS.md`).
- English is the development language; strings, plural rules and localized privacy text ship as English and Simplified Chinese `.lproj` resources embedded in the app by `build.sh`. System errors keep the platform's localized descriptions.
- Project scripts assemble an ad-hoc-signed app bundle. `Resources/Shortcuts` holds the signed generic shortcut; `build.sh` regenerates the unsigned personalization template there, which Git ignores. Icon asset provenance is in `Resources/Brand/README.md`.

## Commands

Run from the project root. Development scripts use system Python 3. `lint.sh` needs SwiftFormat 0.62.1 and SwiftLint 0.65.0 (`brew install swiftformat swiftlint`) and stops when either local version differs from the pin in `.github/workflows/ci.yml`.

- `./scripts/lint.sh`: SwiftFormat check (`.swiftformat`, `.swift-version`) over `Sources`, `Tests` and `Package.swift`, then SwiftLint (`.swiftlint.yml`, rules copied from the owner's shared iOS rules) in strict mode against the committed `.swiftlint-baseline.json`, then native-layout and constraint-style fixture tests and direct prohibitions, script syntax (`bash -n`) and bundle metadata. Layout checks need no Git history or layout baseline: native construction is forbidden in production, legacy activation in production/tests, and primitive spacing outside app Metrics files. `--fix` rewrites Swift sources; `--write-baseline` re-records the baseline with repository-relative paths through `scripts/portable-swiftlint-baseline.py`.
- `./scripts/test.sh`: Swift and shortcut checks.
- `./scripts/build.sh`: build and ad-hoc sign `dist/AnyDock.app`. Build products are disposable.
- `./scripts/run.sh`: build and open the menu bar app.
- `./scripts/release.sh`: Developer ID signing, DMG, notarization and Gatekeeper checks; local only (see Release in `docs/PROJECT.md`).
- `./scripts/shortcut.sh`: sign the generic shortcut with `shortcuts sign`, which needs a signed-in Mac; run it locally and commit the signed `Resources/Shortcuts/发送到 Mac.shortcut`.

GitHub Actions (`.github/workflows/ci.yml`) runs lint, test and build on the `macos-26` runner with its newest installed Xcode, installing SwiftFormat and SwiftLint from pinned release binaries (`SWIFTFORMAT_VERSION`, `SWIFTLINT_VERSION`, each checked by SHA-256); update a pin together with its local version. CI never signs shortcuts or runs `release.sh`. Pull requests merge only through `.github/workflows/auto-merge.yml` (see Merging pull requests in `docs/PROJECT.md`).

## Trust and contribution boundaries

The receiver is intended for a trusted LAN. HTTP does not encrypt content or the installation-specific connection key, and personalized shortcuts contain that key; do not expose the listener to the Internet. How received content is validated, stored and quarantined is in `docs/PROJECT.md`; data-protection and contribution rules are in `AGENTS.md`. Local checks do not replace visual, iPhone or target-chat acceptance.
