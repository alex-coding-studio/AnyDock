# AnyDock Project Context

## Purpose and product behavior

AnyDock receives images, UTF-8 text snippets, HTTP/HTTPS links and arbitrary files shared from an iPhone over the local network and exposes them in a native macOS menu bar tray. Users can browse thumbnails, select images, drag their original files into another app, copy them, preview them with Quick Look or reveal them in Finder.

The tray is a 450 × 520 pt popover with a fixed three-column masonry layout; the Text filter uses a single full-width column. Filter capsules at the top show All, Images, Text, Links and Files with counts, hide empty types, default to All and switch back to All when a new arrival would be hidden. Cards go into the shortest column, with ties going left. Heights preserve aspect ratio up to 2.5 times the column width; capped images show their top portion with aspect fill. Liquid Glass is used on macOS 26 or later, with a native visual-effect fallback on older supported systems.

The tray shows all four content kinds: image cards, text cards with the first lines, link cards with the domain and URL, and file cards with a Quick Look thumbnail or monospaced first lines, a type badge, filename and size. Dragging gives the original file for images and files, plain text for text, and the URL plus the file for links. Receipt time appears on every card, and the latest receipt highlight is independent of manual selection. Folder, trash and Settings controls float above the scrolling content. Configuration and listener status belong in Settings. New receipts reveal or update the tray and scroll into view; loading history does not reveal it. Each manual opening rereads the receive folder, reflecting Finder removals and restores, while receipt-driven opening skips an extra reload. Every actual tray close clears the selection. Quick Look and trash confirmation keep the tray open; closing either of those alone preserves selection.

The trash button always asks for confirmation, targeting the selected items, or with nothing selected, the items in the current filter; the confirmation names the type and count. Escape and outside clicks cancel without recycling files. Command-Delete and the context menu recycle selected items directly. Every request is checked against the current receive folder's `ImageStore.list` set and uses `NSWorkspace.recycle`. Originals are never overwritten or deleted automatically.

Settings has General, Connection and Receiving toolbar tabs, with General selected initially. General owns the off-by-default option to copy each new item to the clipboard, appearance, language, immediate login startup and Quit. Appearance follows the system or forces Light/Dark using `NSApp.appearance`, applying immediately to the tray and Settings. Language follows the system or selects English/Simplified Chinese via the app-local `AppleLanguages` override and requires a restart; Settings offers Restart Now. Connection owns one-step AirDrop setup and manual address/key copying plus generic shortcut export. The one-step shortcut contains the applied address and key; its editable name persists in UserDefaults and defaults to localized `Send to ` / `发送到 ` plus the computer name, falling back to localized `Send to Mac`. Saved custom names are preserved. Each Mac sends its own named shortcut. Only Receiving stages folder/port edits and has an Apply button; receiver status and failures appear there. Switching folders never moves or deletes previous originals.

See `docs/PROJECT.md` for the complete current UI and engineering rules.

## Technical foundation

- Swift 6 language mode, SwiftPM tools version 6.0, macOS 14+ deployment target. The development toolchain is Xcode 27.2 / Apple Swift 6.4.2; source builds need a compatible compiler and an SDK containing the macOS 26 glass APIs.
- Native AppKit controls, materials, selection, dragging, Quick Look and sharing APIs. No third-party package dependencies.
- Network.framework HTTP receiver, default TCP port 8765, configurable in Settings. No automatic port switching.
- Received originals live in the user-selected directory. Fresh configurations default to `~/Downloads/AnyDock`; existing configured paths are unchanged. New items use Images/Text/Links/Files subdirectories, while flat legacy images remain in place. Receiver configuration lives in Application Support; columns, appearance, language overrides and personalized shortcut names use UserDefaults.
- `Package.swift` is the package source of truth. Project scripts assemble an ad-hoc-signed app bundle with identifier `studio.alex.snapdock`.

## Structure

- `Sources/AnyDockCore`: compatible authenticated multi-type upload protocol, typed storage/listing, quarantine protection and pure masonry geometry.
- `Sources/AnyDock`: app lifecycle, tray layout and interactions, Settings and personalized shortcut preparation.
- `Resources/Info.plist`: application metadata.
- `Sources/AnyDock/Resources`: English and Simplified Chinese `.lproj` strings, plural rules and localized privacy text. English is the development language; SwiftPM resources use `Bundle.module` and `build.sh` embeds the resource bundle in the app. Shortcut-internal prompts generated by Python remain Chinese.
- `Resources/Shortcuts`: signed generic manual shortcut; `build.sh` also generates the unsigned personalization template here.
- `scripts`: build, run, lint, test and shortcut generation entry points. Approved rendered app and menu bar icon assets are packaged directly; see `Resources/Brand/README.md` for provenance.
- `Tests`: protocol, storage, masonry placement and shortcut checks.
- `docs/PROJECT.md`: engineering operations, UI rules and debugging commands.

## Commands

Run from the project root. No package installation is required; development scripts use system Python 3.

- `./scripts/lint.sh`: check formatting, script syntax and bundle metadata.
- `./scripts/test.sh`: run Swift and shortcut checks.
- `./scripts/build.sh`: create and ad-hoc sign `dist/AnyDock.app`. It regenerates the unsigned `Resources/Shortcuts/Template.shortcut`, which is ignored by Git.
- `./scripts/run.sh`: build and open the menu bar app when launching is requested.

GitHub Actions (`.github/workflows/ci.yml`) runs lint, test and build on the `macos-26` runner with its newest installed Xcode. `scripts/shortcut.sh` signs the generic shortcut with `shortcuts sign`, which needs a signed-in Mac; run it locally and commit the signed `Resources/Shortcuts/发送到 Mac.shortcut`. CI never signs.

Pull requests merge through `.github/workflows/auto-merge.yml`; authors never merge by hand. A PR is squash-merged when its current head is the approved commit, no reviewer's latest decision is `CHANGES_REQUESTED`, counting only reviewers with write, maintain or admin permission on the repository, CI has run and every other check succeeded, and it has no `needs-acceptance` label. A PR with visible UI changes gets `needs-acceptance` when it is opened; the architect removes it after the user accepts the UI, which retries the merge. After merging, the workflow dispatches CI on `main`, because merges made with `GITHUB_TOKEN` do not trigger push CI. See `docs/PROJECT.md` for details.

## Trust and contribution boundaries

The receiver is intended for a trusted LAN. HTTP does not encrypt images or the installation-specific connection key; do not expose the listener to the Internet. Validate request sizes and image contents and generate unique filenames. Limit user-requested recycling to generated items in the current folder; the current image-only tray uses the image subset of the typed list. Every non-image is quarantined, and received content is never automatically opened or executed. Tests use temporary directories, fixture credentials and separate ports; never print or publish real keys, configuration or received images.

Personalized shortcuts contain the connection key. Prepare and sign them only in temporary storage, clean up after sharing or failure, and never put them into the source tree or bundle. System `shortcuts sign --mode anyone` submits a copy to Apple for validation; Settings discloses this and directs users to their own iPhone. Signing or AirDrop failures leave manual setup available. Changing the receive port requires resending or updating the iPhone shortcut.

Updated shortcuts send Share Sheet items one at a time or use the clipboard when there is no input. Oversize and HTTP failures are counted and reported once after the loop. Transport failures may abort through the normal iOS error behavior; there is no dependency or persistent retry queue. Resend the shortcut after upgrading.

Follow `AGENTS.md` for contribution conventions and `docs/PROJECT.md` for current behavior. Respect the accepted task scope and report the checks actually performed. Local checks do not replace visual, iPhone or target-chat acceptance.

## Rename compatibility

Keep the `studio.alex.snapdock` bundle identifier and Logger subsystem, all UserDefaults keys, `Application Support/SnapDock` configuration directory and existing configured receive paths unchanged; fresh configurations use `~/Downloads/AnyDock`. New files use `AnyDock-`; `ImageStore.list` must also include legacy `SnapDock-` images, and recycling must use that same set. Retain the `X-SnapDock-Key` upload header so installed phone shortcuts keep working. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
