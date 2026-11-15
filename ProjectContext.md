# SnapDock Project Context

## Purpose and product behavior

SnapDock receives images shared from an iPhone over the local network and exposes them in a native macOS menu bar tray. Users can browse thumbnails, select images, drag their original files into another app, copy them, preview them with Quick Look or reveal them in Finder.

The tray is a 450 × 520 pt popover with equal-width masonry columns. It defaults to three columns; General offers two through five, applies changes immediately and preserves valid saved preferences. Images go into the shortest column, with ties going left. Heights preserve aspect ratio up to 2.5 times the column width; capped images show their top portion with aspect fill. Liquid Glass is used on macOS 26 or later, with a native visual-effect fallback on older supported systems.

The tray remains image-focused. Receipt time is the only per-image caption, and the latest receipt highlight is independent of manual selection. Folder, trash and Settings controls float above the scrolling content. Configuration and listener status belong in Settings. New receipts reveal or update the tray and scroll into view; loading history does not reveal it. Each manual opening rereads the receive folder, reflecting Finder removals and restores, while receipt-driven opening skips an extra reload. Every actual tray close clears the selection. Quick Look and trash confirmation keep the tray open; closing either of those alone preserves selection.

The trash button always asks for confirmation, targeting the selected images or all listed images when nothing is selected. Escape and outside clicks cancel without recycling files. Command-Delete and the context menu recycle selected images directly. Every request is checked against the current receive folder's `ImageStore.list` set and uses `NSWorkspace.recycle`. Originals are never overwritten or deleted automatically.

Settings has General, Connection and Receiving toolbar tabs, with General selected initially. General owns columns, immediate login startup and Quit. Connection owns one-step AirDrop setup and manual address/key copying plus generic shortcut export. The one-step shortcut contains the applied address and key; its editable name persists in UserDefaults and defaults to `发送到 ` plus the computer name, falling back to `发送到 Mac`. Each Mac sends its own named shortcut. Only Receiving stages folder/port edits and has an Apply button; receiver status and failures appear there. Switching folders never moves or deletes previous originals.

See `docs/PROJECT.md` for the complete current UI and engineering rules.

## Technical foundation

- Swift 6 language mode, SwiftPM tools version 6.0, macOS 14+ deployment target. The development toolchain is Xcode 27.2 / Apple Swift 6.4.2; source builds need a compatible compiler and an SDK containing the macOS 26 glass APIs.
- Native AppKit controls, materials, selection, dragging, Quick Look and sharing APIs. No third-party package dependencies.
- Network.framework HTTP receiver, default TCP port 8765, configurable in Settings. No automatic port switching.
- Original image files live in the user-selected directory, initially `~/Downloads/SnapDock`. Receiver configuration lives in Application Support; columns and personalized shortcut names use UserDefaults.
- `Package.swift` is the package source of truth. Project scripts assemble an ad-hoc-signed app bundle with identifier `studio.alex.snapdock`.

## Structure

- `Sources/SnapDockCore`: upload protocol, image validation/storage and pure masonry geometry.
- `Sources/SnapDock`: app lifecycle, tray layout and interactions, Settings and personalized shortcut preparation.
- `Resources/Info.plist`: application metadata.
- `Resources/Shortcuts`: unsigned personalization template and signed generic manual shortcut.
- `scripts`: build, run, lint, test, icon and shortcut generation entry points.
- `Tests`: protocol, storage, masonry placement and shortcut checks.
- `docs/PROJECT.md`: engineering operations, UI rules and debugging commands.

## Commands

Run from the project root. No package installation is required; development scripts use system Python 3.

- `./scripts/lint.sh`: check formatting, script syntax and bundle metadata.
- `./scripts/test.sh`: run Swift and shortcut checks.
- `./scripts/build.sh`: create and ad-hoc sign `dist/SnapDock.app`. It regenerates the unsigned `Resources/Shortcuts/Template.shortcut`, which is ignored by Git.

GitHub Actions (`.github/workflows/ci.yml`) runs lint, test and build on the `macos-26` runner with its newest installed Xcode. `scripts/shortcut.sh` signs the generic shortcut with `shortcuts sign`, which needs a signed-in Mac; run it locally and commit the signed `Resources/Shortcuts/发送到 Mac.shortcut`. CI never signs.
- `./scripts/run.sh`: build and open the menu bar app when launching is requested.

## Trust and contribution boundaries

The receiver is intended for a trusted LAN. HTTP does not encrypt images or the installation-specific connection key; do not expose the listener to the Internet. Validate request sizes and image contents and generate unique filenames. Limit user-requested recycling to SnapDock images listed in the current folder. Tests use temporary directories, fixture credentials and separate ports; never print or publish real keys, configuration or received images.

Personalized shortcuts contain the connection key. Prepare and sign them only in temporary storage, clean up after sharing or failure, and never put them into the source tree or bundle. System `shortcuts sign --mode anyone` submits a copy to Apple for validation; Settings discloses this and directs users to their own iPhone. Signing or AirDrop failures leave manual setup available. Changing the receive port requires resending or updating the iPhone shortcut.

Follow `AGENTS.md` for contribution conventions and `docs/PROJECT.md` for current behavior. Respect the accepted task scope and report the checks actually performed. Local checks do not replace visual, iPhone or target-chat acceptance.
