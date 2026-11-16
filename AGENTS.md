# AnyDock Contributor Instructions

Read `ProjectContext.md` and `docs/PROJECT.md` before changing the project. These files describe the architecture, current UI behavior, data boundaries and validation commands.

## Project conventions

- AnyDock is a native AppKit menu bar app using Swift 6 and Swift Package Manager, targeting macOS 14 or later. Keep `com.cuxiao.mac.anydock` as the bundle identifier.
- Keep Swift identifiers in English and localize user-visible strings in English and Simplified Chinese. Write contributor documentation in English.
- Do not add explanatory code comments, documentation comments or `MARK` sections.
- Keep the tray focused on received content: cards show only what identifies the item (image, text lines, link, or a file's thumbnail and name) in a single caption line (the filename for files, the receipt time for text and links, a time capsule for images); size, character count and full URL belong to the floating selection capsule's single-selection detail; selection feedback, filter capsules and icon controls. The clipboard bar is a separate attachment, not tray content: it sits at the bottom of the tray below the floating selection capsule, shows the in-memory history of the last 4 plain-text clipboard entries, never joins the filters or counts and is never written to disk or logs. Put configuration and listener status in Settings; do not add configuration fields to the tray.
- Preserve native collection selection, original-file dragging and Quick Look. Follow the interaction rules in `docs/PROJECT.md` when changing them.
- Use native AppKit controls and system colors. Guard Liquid Glass APIs with macOS 26 availability checks and retain the material fallback for macOS 14–25. No third-party dependencies are currently required.

## Protect user data

- Never overwrite or automatically delete received originals. Changing receive folders must not move or delete existing files.
- User-requested recycling must be limited to the generated items returned by `ImageStore.list` in the current receive folder. Use `NSWorkspace.recycle`, report failures and keep remaining items visible. Never permanently delete inbox files.
- Keep receive credentials and personalized shortcuts out of source files, bundled resources, logs and shared test output. Personalized shortcuts belong in temporary storage and must be cleaned up after sharing or failure.
- Use temporary directories and separate ports for tests. Do not use real user configuration or received images as fixtures.
- Do not launch, replace or terminate an installed running copy, or perform interactive UI/device checks, unless the task explicitly requests it.

## Validation

Run the project entry points from the project root:

- `./scripts/lint.sh`: check SwiftFormat formatting, SwiftLint, script syntax and bundle metadata. Formatting rules live in `.swiftformat` and `.swift-version`, lint rules in `.swiftlint.yml`; both tool versions are pinned in `.github/workflows/ci.yml`. Existing SwiftLint violations are recorded in `.swiftlint-baseline.json`; new code must not add violations, and the baseline is never re-recorded to accept them. File and type line counts are not a lint gate; keep magic values in local Metrics roles such as `TrayMetrics`. Use check mode while other contributors may be editing; `--fix` rewrites sources across the project.
- `./scripts/test.sh`: run Swift and shortcut checks.
- `./scripts/build.sh`: build and ad-hoc sign `dist/AnyDock.app`.
- `./scripts/run.sh`: build and open the app when an app launch is requested.

Choose checks appropriate to the change and follow any narrower task instructions. Do not substitute direct formatter or compiler commands for the declared gates. Report the checks actually run, their results and any remaining manual acceptance. Local automated checks do not establish iPhone upload, visual behavior or target-chat compatibility.

## Naming

Use `com.cuxiao.mac.anydock` for the bundle identifier, Logger subsystem and preferences domain. Preserve existing preference keys, including copyNewItems. The connection configuration file (`Application Support/AnyDock/configuration.json`) holds `ConnectionConfiguration`: `receiver` (port, token, receive folder) and `sender` (personalized shortcut name, saved only after a successful send). Keep configured receive paths unchanged; fresh installations use ~/Downloads/AnyDock. Never log configuration bytes or keys. Received files use the `AnyDock-` prefix; `ImageStore.list` includes only `AnyDock-` items, and recycling uses that same set. Uploads authenticate with the `X-AnyDock-Key` header. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
