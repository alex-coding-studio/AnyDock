# AnyDock Contributor Instructions

Read `ProjectContext.md` and `docs/PROJECT.md` before changing the project. Each fact lives in exactly one of these documents:

- `AGENTS.md`: contributor rules only: conventions, prohibitions, data-protection rules, validation entry points and naming. It changes only when a rule changes.
- `ProjectContext.md`: stable facts: product purpose, technical foundation (platform, toolchain, dependencies), commands, ports, and trust and contribution boundaries. It changes only when the foundation changes.
- `docs/PROJECT.md`: product behaviour contracts that code cannot express and must not regress, plus release and operations procedures. It contains no type names, file layout, ownership or implementation descriptions. Behaviour-preserving refactors do not edit it.

A pull request that does not change product behaviour, commands, dependencies or contributor rules does not edit these documents.

## Project conventions

- Keep Swift identifiers in English and localize user-visible strings in English and Simplified Chinese, keeping strings and placeholders consistent across both. Write contributor documentation in English.
- Do not add explanatory code comments, documentation comments or `MARK` sections.
- Follow the tray content, selection, dragging, Quick Look and clipboard bar contracts in `docs/PROJECT.md` when changing them. Do not add configuration fields or listener status to the tray.
- UI state and its rules live in a view model that does not import AppKit, exposes state through Combine publishers and user intents through methods, and receives its dependencies through init; view controllers and views only bind to the view model and forward user actions. New screens follow this; existing screens (Settings next) migrate one at a time.
- `AppDelegate` only handles application lifecycle callbacks. `AppServiceProvider` is the composition root: it creates the services and the interface, injects dependencies through init and connects their publishers. Only `AppDelegate` holds it; no other type may hold or receive `AppServiceProvider` (no service locator). Services such as `Inbox` expose state through publishers and are injected into the components that need them.
- Components publish events with Combine: keep a private `PassthroughSubject` (or `CurrentValueSubject` for state) and expose it as `AnyPublisher`; subscribers store the `AnyCancellable`. Closure callback properties are being replaced with publishers file by file; new component communication uses publishers, not closures.
- Use PockyFoundation semantic roles directly for gaps, insets, control/row padding and matching shared sizes. Do not rename roles through local constants, typealiases or one-line forwarding APIs. Local layout Metrics contain only specific element geometry or actual multi-role calculations. `PKYLayout.Space.` is forbidden in `Sources/AnyDock` outside files named `*Metrics.swift`.
- Use native AppKit controls and system colors. Guard Liquid Glass APIs with macOS 26 availability checks and retain the material fallback for macOS 14–25. Keep magic values in local Metrics roles such as `TrayMetrics`.

## Auto Layout

- Use SnapKit's standard DSL for Auto Layout. Each target using it declares the product directly. Keep one view's constraints in one `snp.makeConstraints` closure per assembly phase, and put priorities in the chain. Preserve existing numeric priorities; AppKit's `ConstraintPriority.medium` is 501, unlike UIKit's 500. Pass native priority `rawValue` when needed.
- Keep one current `Constraint?` for a switched relationship, deactivate it before replacement, and use `snp.remakeConstraints` only when replacing that view's complete SnapKit placement. Preserve independently owned sizing constraints and explicit activation phases; use `prepareConstraints` for deferred activation.
- Remove redundant `translatesAutoresizingMaskIntoConstraints = false` only when SnapKit owns placement. A size-only constraint must not take placement ownership from a frame-managed host; preserve its original autoresizing setting.
- Frame/layout-managed `NSScrollView.documentView` instances, such as `NSCollectionView`, are sized by their layout object or explicit frames and retain only width-following `autoresizingMask`; do not add constraints to those document views themselves. For Auto Layout content-driven document views, such as `TrayScopeBar`'s `FlippedView`, pin both sides of the non-scrolling axis and only the start of the scrolling axis (`top`/`bottom`/`leading` for horizontal scrolling). Never pin the scrolling end or match the viewport's scrolling dimension, or the content cannot grow and scroll. The collection view manages each `NSCollectionViewItem` root view's frame; constrain only its internal subviews.
- Use leading/trailing relationships and directional edges for nonzero insets; `edges` is suitable for zero edge pinning. Preserve AppKit clip-view relationships, flipped-coordinate behavior, native stack visibility/detachment rules, glass `contentView` ownership and availability fallbacks.
- Animated height and visibility regions retain constraint-based outer geometry without changing the existing native stack hierarchy or timing. Preserve AppKit `NSAnimationContext` and `NSLayoutConstraint.animator()` behavior; a synchronous SnapKit constant update is not equivalent to an animator update.
- Native anchor construction, `NSLayoutConstraint(item:)`, VFL and `addConstraint(s)` are directly forbidden in `Sources`. Legacy `NSLayoutConstraint.activate` and `activate: false` calls are directly forbidden in `Sources` and `Tests`. These checks have no layout baseline, Git comparison, write command or exception; run their fixture tests after checker changes.

## Protect user data

- Never overwrite or automatically delete received originals; receive-folder changes follow the receive-folder safety rules in `docs/PROJECT.md`.
- User-requested recycling stays within the recycling boundary in `docs/PROJECT.md`. Never permanently delete inbox files.
- Keep receive credentials and personalized shortcuts out of source files, bundled resources, logs and shared test output. Personalized shortcuts belong in temporary storage and must be cleaned up after sharing or failure.
- Tests use temporary directories, fixture credentials, separate ports and private localhost listeners, private pasteboards (never the general pasteboard) and isolated preference suites. Do not use real user configuration, preferences or received images as fixtures.
- Do not launch, replace or terminate an installed running copy, or perform interactive UI/device checks, unless the task explicitly requests it.

## Validation

Enable the committed Git hooks once per clone with `git config core.hooksPath .githooks`. The pre-commit hook refuses commits on `main` and runs `./scripts/lint.sh` in check mode.

Use the entry points listed under Commands in `ProjectContext.md` (`lint.sh`, `test.sh`, `build.sh`, `run.sh` only when an app launch is requested). Do not substitute direct formatter or compiler commands for them.

- New code must not add SwiftLint violations, and `.swiftlint-baseline.json` is re-recorded only to remove fixed violations, never to accept new ones. File and type line counts are not a lint gate.
- Use lint check mode while other contributors may be editing; `--fix` rewrites sources across the project.
- Choose checks appropriate to the change and follow any narrower task instructions. Report the checks actually run, their results and any remaining manual acceptance. Local automated checks do not establish iPhone upload, visual behavior or target-chat compatibility.

## Naming

- Use `com.cuxiao.mac.anydock` for the bundle identifier, Logger subsystem and preferences domain. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
- Preserve existing preference keys: `appearance`, `copyNewItems`, `keepClipboardHistory` and `wakeHotKey` (`keyCode` as a Carbon virtual key and `modifiers` as an `NSEvent.ModifierFlags` raw value limited to ⌃⌥⇧⌘). Language uses the app-local `AppleLanguages` key: `["en"]`, `["zh-Hans"]`, or removed for Follow System; never write the global value.
- The connection configuration file (`Application Support/AnyDock/configuration.json`) holds `ConnectionConfiguration`: `receiver` (port, token, receive folder) and `sender` (personalized shortcut name, saved only after a successful send). Never log configuration bytes or keys.
- Received files use the `AnyDock-` prefix; only `AnyDock-` items are listed by `InboxStore.list`, and recycling uses that same set.
- The `X-AnyDock-*` upload headers in `docs/PROJECT.md` are a compatibility contract with installed iPhone shortcuts; do not rename them.
