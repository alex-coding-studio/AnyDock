# AnyDock Contributor Instructions

Read `ProjectContext.md` and `docs/PROJECT.md` before changing the project. These files describe the architecture, current UI behavior, data boundaries and validation commands.

## Project conventions

- AnyDock is a native AppKit menu bar app using Swift 6 and Swift Package Manager, targeting macOS 14 or later. Keep `studio.alex.snapdock` as the bundle identifier.
- Keep Swift identifiers in English and localize user-visible strings in English and Simplified Chinese. Write contributor documentation in English.
- Do not add explanatory code comments, documentation comments or `MARK` sections.
- Keep the tray focused on images, with receipt-time captions, selection feedback and icon controls. Put configuration and listener status in Settings; do not add filenames, file sizes or configuration fields to the tray.
- Preserve native collection selection, original-file dragging and Quick Look. Follow the interaction rules in `docs/PROJECT.md` when changing them.
- Use native AppKit controls and system colors. Guard Liquid Glass APIs with macOS 26 availability checks and retain the material fallback for macOS 14–25. No third-party dependencies are currently required.

## Protect user data

- Never overwrite or automatically delete received originals. Changing receive folders must not move or delete existing files.
- User-requested recycling must be limited to the generated items returned by `ImageStore.list` (the current image-only tray uses `listImages`) in the current receive folder. Use `NSWorkspace.recycle`, report failures and keep remaining images visible. Never permanently delete inbox files.
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

Keep the `studio.alex.snapdock` bundle identifier and Logger subsystem, all UserDefaults keys, `Application Support/SnapDock` configuration directory and existing configured receive paths unchanged; fresh configurations use `~/Downloads/AnyDock`. New files use `AnyDock-`; `ImageStore.list` must also include legacy `SnapDock-` images, and recycling must use that same set. Retain the `X-SnapDock-Key` upload header so installed phone shortcuts keep working. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
