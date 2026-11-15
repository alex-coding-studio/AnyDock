# AnyDock Contributor Instructions

Read `ProjectContext.md` and `docs/PROJECT.md` before changing the project. These files describe the architecture, current UI behavior, data boundaries and validation commands.

## Project conventions

- AnyDock is a native AppKit menu bar app using Swift 6 and Swift Package Manager, targeting macOS 14 or later. Keep `com.cuxiao.mac.anydock` as the bundle identifier.
- Keep Swift identifiers in English and localize user-visible strings in English and Simplified Chinese. Write contributor documentation in English.
- Do not add explanatory code comments, documentation comments or `MARK` sections.
- Keep the tray focused on received content: cards show only what identifies the item (image, text lines, link, or a file's thumbnail and name) in a single caption line (the filename for files, the receipt time for text and links, a time capsule for images); size, character count and full URL belong to the bottom bar's single-selection detail; selection feedback, filter capsules and icon controls. The clipboard bar is a separate attachment, not tray content: it sits above the bottom controls, shows the in-memory history of the last 4 plain-text clipboard entries, never joins the filters or counts and is never written to disk or logs. Put configuration and listener status in Settings; do not add configuration fields to the tray.
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

- `./scripts/lint.sh`: check formatting, script syntax and bundle metadata. Use check mode while other contributors may be editing; `--fix` rewrites sources across the project.
- `./scripts/test.sh`: run Swift and shortcut checks.
- `./scripts/build.sh`: build and ad-hoc sign `dist/AnyDock.app`.
- `./scripts/run.sh`: build and open the app when an app launch is requested.

Choose checks appropriate to the change and follow any narrower task instructions. Do not substitute direct formatter or compiler commands for the declared gates. Report the checks actually run, their results and any remaining manual acceptance. Local automated checks do not establish iPhone upload, visual behavior or target-chat compatibility.

## Rename compatibility

Use `com.cuxiao.mac.anydock` for the bundle identifier, Logger subsystem and current preferences domain. Preserve existing preference keys, including copyNewItems and personalizedShortcutName. Keep configured receive paths unchanged; fresh installations use ~/Downloads/AnyDock. Before UI initialization, copy the legacy preferences and `Application Support/SnapDock/configuration.json` into the new domain and `Application Support/AnyDock/configuration.json`, leaving old data intact. Do not overwrite an existing new configuration file or existing preference values; only mark migration complete after success. On failure, retain old data, do not mark completion, and retry at the next launch. The app displays in-memory defaults with an empty key, pauses receiving, prevents saving or personalizing that fallback, and shows a safe localized migration warning in Receiving. Never log configuration bytes or keys. Login items are not migrated automatically; users must switch launch at login off and on after upgrading. New files use `AnyDock-`; `ImageStore.list` must also include legacy `SnapDock-` images, and recycling must use that same set. Retain the `X-SnapDock-Key` upload header so installed phone shortcuts keep working. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
