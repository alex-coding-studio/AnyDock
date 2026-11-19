# AnyDock Engineering

See [AGENTS.md](../AGENTS.md) for Agent startup and delivery, [Product Behaviour and Operations](PROJECT.md) for behavioural contracts, and [README](../README.en.md) for product and installation information. Update these documents when their rules or facts change. Behaviour-preserving refactors do not change product contracts.

## Technical foundation

- Swift 6 language mode, SwiftPM tools version 6.0, macOS 14+ deployment target. The development toolchain is Xcode 27.2 / Apple Swift 6.4.2; source builds need a compatible compiler and an SDK containing the macOS 26 glass APIs. `Package.swift` is the package source of truth.
- Native AppKit controls, materials, selection, dragging, Quick Look and sharing APIs. Settings is SwiftUI hosted in AppKit: an `NSSplitViewController` sidebar item and detail item each contain an `NSHostingController`; SwiftUI ships with the SDK and adds no dependency. The public MIT PockyFoundation package supplies shared spacing, shape and motion roles, appearance-aware elevation, and pure masonry/grid placement. Product-specific Metrics remain local; AnyDock does not use CXDesignKit. SnapKit is the third-party Auto Layout DSL, declared directly by the app and its layout-test target. The committed `Package.resolved` pins resolved dependencies; SnapKit uses an exact release. Its privacy resource bundle and full MIT license ship inside the assembled app.
- Sparkle 2 provides macOS updates. SwiftPM pins the binary framework, and the build embeds it under Contents/Frameworks with its upstream license. Release builds sign the nested helpers and publish a signed appcast alongside the notarized disk image. The update signing key stays in the release Mac's login keychain under the AnyDock bundle identifier.
- Network.framework HTTP receiver on default TCP port 8765, configurable in Settings, with no automatic port switching.
- Received originals live in the user-selected receive folder, outside the checkout. Connection configuration lives in Application Support; the other preferences use UserDefaults (see [Naming and compatibility](#naming-and-compatibility)).
- English is the development language; strings, plural rules and localized privacy text ship as English and Simplified Chinese `.lproj` resources embedded in the app by `build.sh`. System errors keep the platform's localized descriptions.
- Project scripts assemble an ad-hoc-signed app bundle. `Resources/Shortcuts` holds the signed generic shortcut; `build.sh` regenerates the unsigned personalization template there, which Git ignores. See [icon asset provenance](../Resources/Brand/README.md).

## Commands

Run from the project root. Development scripts use system Python 3. `lint.sh` needs SwiftFormat 0.62.1 and SwiftLint 0.65.0 (`brew install swiftformat swiftlint`) and stops when either local version differs from the pin in `.github/workflows/ci.yml`.

- `./scripts/lint.sh`: SwiftFormat check (`.swiftformat`, `.swift-version`) over `Sources`, `Tests` and `Package.swift`, then SwiftLint (`.swiftlint.yml`, rules copied from the owner's shared iOS rules) in strict mode against the committed `.swiftlint-baseline.json`, then native-layout and constraint-style fixture tests and direct prohibitions, script syntax (`bash -n`) and bundle metadata. Layout checks need no Git history or layout baseline: native construction is forbidden in production, legacy activation in production/tests, and primitive spacing outside app Metrics files. `--fix` rewrites Swift sources; `--write-baseline` re-records the baseline with repository-relative paths through `scripts/portable-swiftlint-baseline.py`.
- `./scripts/test.sh`: Swift and shortcut checks.
- `./scripts/build.sh`: build and ad-hoc sign `dist/AnyDock.app`. Build products are disposable.
- `./scripts/run.sh`: build and open the menu bar app.
- `./scripts/release.sh`: Developer ID signing, DMG, notarization and Gatekeeper checks; local only (see [Release](PROJECT.md#release)). Disk image packaging uses Python 3.11+ and hash-pinned dmgbuild dependencies in a project-local virtual environment.
- `./scripts/shortcut.sh`: sign the generic shortcut with `shortcuts sign`, which needs a signed-in Mac; run it locally and commit the signed `Resources/Shortcuts/发送到 Mac.shortcut`.

GitHub Actions (`.github/workflows/ci.yml`) runs lint, test and build on the `macos-26` runner with its newest installed Xcode, installing SwiftFormat and SwiftLint from pinned release binaries (`SWIFTFORMAT_VERSION`, `SWIFTLINT_VERSION`, each checked by SHA-256); update a pin together with its local version. CI never signs shortcuts or runs `release.sh`. Pull requests merge only through `.github/workflows/auto-merge.yml` (see [Merging pull requests](PROJECT.md#merging-pull-requests)).

## UI foundation and architecture

- Keep Swift identifiers in English and localize user-visible strings in English and Simplified Chinese, keeping strings and placeholders consistent across both. Write contributor documentation in English.
- Do not add explanatory code comments, documentation comments or `MARK` sections.
- Follow the tray content, selection, dragging, Quick Look and clipboard bar contracts in [Product Behaviour and Operations](PROJECT.md) when changing them. Do not add configuration fields or listener status to the tray.
- UI state and its rules live in a view model that does not import AppKit or SwiftUI, exposes state through Combine (`@Published private(set)` on an `ObservableObject` for SwiftUI screens, or private subjects exposed as `AnyPublisher`) and user intents through methods, and receives its dependencies through init; view controllers and SwiftUI views only bind to the view model and forward user actions. New screens follow this.
- Settings uses SwiftUI in AppKit. The sidebar and detail items of an `NSSplitViewController` each have an `NSHostingController` inside `SettingsWindowController`. The tray and the other existing screens stay AppKit with SnapKit; do not move them to SwiftUI. AppKit-only work a SwiftUI view needs (open/save panels, Finder reveal, key recording) stays in the view layer or behind the injected service protocols, never in a view model.
- `AppDelegate` only handles application lifecycle callbacks. `AppServiceProvider` is the composition root: it creates the services and the interface, injects dependencies through init and connects their publishers. Only `AppDelegate` holds it; no other type may hold or receive `AppServiceProvider` (no service locator). Services such as `Inbox` expose state through publishers and are injected into the components that need them.
- Components publish events with Combine: keep a private `PassthroughSubject` (or `CurrentValueSubject` for state) and expose it as `AnyPublisher`; subscribers store the `AnyCancellable`. Closure callback properties are being replaced with publishers file by file; new component communication uses publishers, not closures.
- Use PockyFoundation semantic roles directly for gaps, insets, control/row padding and matching shared sizes. Do not rename roles through local constants, typealiases or one-line forwarding APIs. Local layout Metrics contain only specific element geometry or actual multi-role calculations. `PKYLayout.Space.` is forbidden in `Sources/AnyDock` outside files named `*Metrics.swift`.
- Use native AppKit or SwiftUI controls and system colors. Guard Liquid Glass APIs with macOS 26 availability checks and retain the material fallback for macOS 14–25. Keep magic values in local Metrics roles such as `TrayMetrics`.

## Auto Layout

These rules cover AppKit views. SwiftUI views use SwiftUI layout with PockyFoundation roles and local Metrics under the same rules as above.

- Use SnapKit's standard DSL for Auto Layout. Each target using it declares the product directly. Keep one view's constraints in one `snp.makeConstraints` closure per assembly phase, and put priorities in the chain. Preserve existing numeric priorities; AppKit's `ConstraintPriority.medium` is 501, unlike UIKit's 500. Pass native priority `rawValue` when needed.
- Keep one current `Constraint?` for a switched relationship, deactivate it before replacement, and use `snp.remakeConstraints` only when replacing that view's complete SnapKit placement. Preserve independently owned sizing constraints and explicit activation phases; use `prepareConstraints` for deferred activation.
- Remove redundant `translatesAutoresizingMaskIntoConstraints = false` only when SnapKit owns placement. A size-only constraint must not take placement ownership from a frame-managed host; preserve its original autoresizing setting.
- Frame/layout-managed `NSScrollView.documentView` instances, such as `NSCollectionView`, are sized by their layout object or explicit frames and retain only width-following `autoresizingMask`; do not add constraints to those document views themselves. For Auto Layout content-driven document views, such as `TrayScopeBar`'s `FlippedView`, pin both sides of the non-scrolling axis and only the start of the scrolling axis (`top`/`bottom`/`leading` for horizontal scrolling). Never pin the scrolling end or match the viewport's scrolling dimension, or the content cannot grow and scroll. The collection view manages each `NSCollectionViewItem` root view's frame; constrain only its internal subviews.
- Use leading/trailing relationships and directional edges for nonzero insets; `edges` is suitable for zero edge pinning. Preserve AppKit clip-view relationships, flipped-coordinate behavior, native stack visibility/detachment rules, glass `contentView` ownership and availability fallbacks.
- Animated height and visibility regions retain constraint-based outer geometry without changing the existing native stack hierarchy or timing. Preserve AppKit `NSAnimationContext` and `NSLayoutConstraint.animator()` behavior; a synchronous SnapKit constant update is not equivalent to an animator update.
- Native anchor construction, `NSLayoutConstraint(item:)`, VFL and `addConstraint(s)` are directly forbidden in `Sources`. Legacy `NSLayoutConstraint.activate` and `activate: false` calls are directly forbidden in `Sources` and `Tests`. These checks have no layout baseline, Git comparison, write command or exception; run their fixture tests after checker changes.

## Protect user data

- Keep the receiver on a trusted LAN. HTTP carries received content and the installation-specific key without encryption. Keep the listener off the public Internet and keep personalized shortcuts private.
- Never overwrite or automatically delete received originals; receive-folder changes follow the receive-folder safety rules in [Product Behaviour and Operations](PROJECT.md).
- User-requested recycling stays within the recycling boundary in [Product Behaviour and Operations](PROJECT.md). Never permanently delete inbox files.
- Keep receive credentials and personalized shortcuts out of source files, bundled resources, logs and shared test output. Personalized shortcuts belong in temporary storage and must be cleaned up after sharing or failure.
- Tests use temporary directories, fixture credentials, separate ports and private localhost listeners, private pasteboards (never the general pasteboard) and isolated preference suites. Do not use real user configuration, preferences or received images as fixtures.
- Do not launch, replace or terminate an installed running copy, or perform interactive UI/device checks, unless the task explicitly requests it.

## Validation

Enable the committed Git hooks once per clone with `git config core.hooksPath .githooks`. The pre-commit hook refuses commits on `main` and runs `./scripts/lint.sh` in check mode.

Use the entry points listed under [Commands](#commands) (`lint.sh`, `test.sh`, `build.sh`, `run.sh` only when an app launch is requested). Do not substitute direct formatter or compiler commands for them.

- New code must not add SwiftLint violations, and `.swiftlint-baseline.json` is re-recorded only to remove fixed violations, never to accept new ones. File and type line counts are not a lint gate.
- Use lint check mode while other contributors may be editing; `--fix` rewrites sources across the project.
- Choose checks appropriate to the change and follow any narrower task instructions. Report the checks actually run, their results and any remaining manual acceptance. Local automated checks do not establish iPhone upload, visual behavior or target-chat compatibility.

For shortcut generator changes, generate a placeholder-configured shortcut and have the user check for action errors in Mac Shortcuts before sending it to iPhone. Follow the [iPhone shortcut acceptance cases](PROJECT.md#iphone-shortcut).

## Naming and compatibility

- Use `com.cuxiao.mac.anydock` for the bundle identifier, Logger subsystem and preferences domain. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
- Preserve existing preference keys: `appearance`, `copyNewItems`, `keepClipboardHistory` and `wakeHotKey` (`keyCode` as a Carbon virtual key and `modifiers` as an `NSEvent.ModifierFlags` raw value limited to ⌃⌥⇧⌘). Language uses the app-local `AppleLanguages` key: `["en"]`, `["zh-Hans"]`, or removed for Follow System; never write the global value.
- The connection configuration file (`Application Support/AnyDock/configuration.json`) holds `ConnectionConfiguration`: `receiver` (port, token, receive folder) and `sender` (personalized shortcut name, saved only after a successful send). Never log configuration bytes or keys.
- Received files use the `AnyDock-` prefix; only `AnyDock-` items are listed by `InboxStore.list`, and recycling uses that same set.
- The `X-AnyDock-*` upload headers in [Upload protocol compatibility](PROJECT.md#upload-protocol-compatibility) are a compatibility contract with installed iPhone shortcuts; do not rename them.
