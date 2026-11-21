# Product Behaviour and Operations

User-visible behaviour that must not regress, and release and operations procedures. See [AGENTS.md](../AGENTS.md) for Agent workflow and [AnyDock Engineering](ENGINEERING.md) for development and validation.

## Tray

- A 480 × 640 pt menu bar popover lists every received item, newest first, in a fixed four-column masonry layout; the Text filter uses one full-width column. Cards go into the shortest column, ties going left. Image heights keep their aspect ratio up to a cap, and capped images show their top portion. Text, link and file cards take their height from their content up to a cap, truncating longer text. A card keeps its size when its preview loads.
- The top row holds the filter bar at the left and one capsule group with Folder and Settings at the right, aligned with the card margins. The filter bar scrolls horizontally only when its segments do not fit, fading the edges with more content. The first row of cards rests fully below the top row; content scrolls under the top row and the bottom floating controls.
- Filters list All, Images, Text, Links and Files with counts, hide empty types and default to All. A new arrival hidden by the current filter switches it back to All. Switching filters scrolls to the top.
- Image cards show the unframed image, the uppercase extension at the top-left and the receipt time in a capsule at the lower-left. Text, link and file cards are Polaroid cards: a preview above one caption line that is never clipped (previews give up height first), showing the middle-truncated filename for files and the receipt time for text and links. Text previews show the text; link previews the domain on one middle-truncated line and the URL below; file previews a Quick Look first-page thumbnail (starting as the type icon) or, for plain-text files, the first lines in monospace.
- Every card has a badge at its top-left whose color follows the item’s kind, with one color per kind matching the filters (images, text snippets, links, files). Images and files show their real extension, text snippets `TEXT`, and links `URL`. An extensionless file with PDF content is treated as a PDF for badge text, icon and thumbnail.
- Times show `HH:mm` today and month/day otherwise, with the full timestamp on hover. Only an accent dot before its time marks the latest receipt, so it cannot be confused with selection. Selected cards have a solid accent border and a corner checkmark.
- Thumbnail colours stay intact. Liquid Glass is used on macOS 26+, a material fallback on 14–25. Tray and Settings follow the chosen appearance immediately, including system changes while the tray is open.
- The tray shows only received content. Its chrome is limited to card captions, the selection capsule, filters and icon controls; size, character count and full URL appear only in the capsule's single-item detail. Configuration and listener status or errors belong in Settings. Button accessibility labels and tooltips are preserved. The one exception is an accent dot on the Settings icon control while an update is available, also announced as the control's accessibility value; clicking the control still only opens Settings.
- The empty tray shows a tray icon, a "nothing received yet" message and guidance to share on the iPhone and choose this Mac's shortcut, without configuration or listener errors.

## Selection, keyboard and Quick Look

- Native click, modifier-click and rubber-band selection are kept. Only card rectangles start selection or dragging; gaps and margins start rubber-band selection.
- Single-clicking a filter segment only switches the filter. Every even click count selects every card visible in that filter, or clears the selection when all are already selected (a rapid second double-click toggles once more, not twice); it never inverts a partial selection and does not reload an already selected filter. Odd counts act as single clicks.
- Space or double-click opens Quick Look for the selection; arrows navigate and Space closes it. The tray stays open meanwhile, and closing only Quick Look keeps the selection.
- Command-C copies images as file plus PNG, text and links as plain values, files as the file. Finder reveal uses the selected originals.
- Esc collapses an expanded clipboard bar first; otherwise it clears the selection.
- When the tray is the key window, ⌘Q quits AnyDock and ⌘, opens Settings through the same path as the tray's Settings button, requesting that the tray close first. Both use standard macOS menu key equivalents and follow the keyboard layout.
- The context menu shows the same shortcuts the tray handles (⌘C copy, ⌘⌫ move to Trash). ⌘C and Space match the character of the current keyboard layout, so ⌘⇧C does not copy; ⌘⌫ and Esc match the physical key.
- Every actual tray close clears the selection.

## Selection capsule and drag to Trash

- A floating, centred capsule sits above the clipboard bar, or near the bottom edge when the bar is hidden, without taking layout space. It is hidden with no selection and shows the selected count for several items.
- For one item it shows: files `name · size · time` (only the name middle-truncated); images extension, size and time, never the stored filename (`PNG · 1.2 MB · 21:30`); text `86 chars · 21:51`; links the middle-truncated full URL. Empty segments are skipped without separators and an empty detail hides the capsule. Long names truncate instead of widening the tray.
- Dragging gives images and files as the original file, text as plain text, links as the URL plus the `.webloc` file. A successful drop outside the tray closes it.
- While tray cards are dragged, the capsule becomes a red "drop here to move to Trash" target that accepts only tray drags and highlights on hover. Dropping there recycles exactly the dragged items (the selection, or the one unselected card dragged) without confirmation, clears the selection and keeps the tray open. The target hides as soon as the mouse button is released, without waiting for the drop or slide-back, then the selection detail returns. Drops elsewhere are ordinary drags.
- There is no trash button and no recycling of a whole filter. Command-Delete and the context menu recycle the selection without confirmation.

## Recycling boundary

Recycling is limited to the generated items listed for the current receive folder, the same set the tray shows. Items go to the Trash, never permanently deleted. The tray stays presented meanwhile, then relists, reports failures and keeps remaining items visible.

## Arrivals and reloading

- New receipts update the tray and, by default, reveal it. Turning off automatic opening keeps a closed tray closed. An open tray scrolls to the new item; loading history does not reveal it. With the General copy-new-items option on (off by default, applied to an open tray), each arrival is also copied as Command-C would.
- Each manual opening rereads the receive folder, reflecting Finder removals and restores; there is no live folder watching. Opening for a new receipt skips the extra reload.
- Listing reads only metadata and image headers. Previews load as cards come into view into a bounded cache and regenerate after eviction. An undecodable image keeps a gray placeholder.

## Clipboard history

- Privacy: at most the 4 newest plain-text entries, in memory only, never written to disk or logs, cleared on quit. The General switch to keep them is on by default, with a footnote saying they stay in memory only and are cleared on quit. Turning it off clears the history and stops polling; turning it on starts from the current clipboard without recording it.
- While on, AnyDock polls the general clipboard about every half second and records plain text, including its own copies. It skips items that also carry a file URL or `org.nspasteboard.ConcealedType`, and deliberately records transient-marked text because voice input uses that marker. A repeat of the newest entry is not added. Copying the connection key in Settings marks it concealed, so no clipboard history records it.
- Before any tray clipboard write, including copying new items, AnyDock checks the clipboard once so another app's new text is captured first.
- The clipboard bar is a separate attachment at the bottom of the tray, aligned with the card margins, never part of filters, counts, selection, Quick Look or the selection capsule, and hidden while the history is empty.
- It is collapsed at every opening: one row with the entry count, Clear and an up arrow; clicking the row or arrow expands it. Expanded, the header says double-click to copy, with Clear and a down arrow, above four equal cells that never scroll; clicking the header (except Clear) or the arrow collapses it. Each cell shows two lines and a relative time; the newest is at the left with the accent dot.
- Double-clicking a cell (or its accessibility press) copies it without adding a duplicate. Cells drag out as plain text; the Trash target rejects them. Clear empties the history immediately without confirmation and hides the bar. The last card row stays reachable above the bar in both states.

## Wake shortcut

- General's Keyboard section has a wake shortcut recorder and Clear; none is set by default. Clicking starts recording: the next eligible key with ⌘, ⌥ or ⌃ is saved immediately, Esc without them cancels, and a key with no modifier or ⇧ alone is rejected with a hint while recording continues. Recording ends when the recorder loses focus or Settings stops being key. It shows symbols in Apple order (⌃⌥⇧⌘) and the key name from the current keyboard layout.
- The recorder reserves ⌘Q for Quit and ⌘, for Settings. It matches the character produced with ⌘ held, shows a hint and keeps recording. Either combination, if previously saved, can still act as the wake shortcut and take precedence over its menu command.
- No Accessibility permission is required. While recording, the saved shortcut is suspended so it reaches the recorder. A new shortcut that cannot be registered is not saved, the previous one stays active and General says it is already in use; a saved shortcut failing at launch shows the same message when Settings first opens. A combination taken by a system shortcut may register without error and never fire.
- Pressing it acts like clicking the menu bar icon: closes Quick Look when the tray is held, closes an open tray, or shows the tray, activates AnyDock, rereads the receive folder and focuses the cards so arrows, Space, ⌘C and Esc work immediately.

## Settings

A sidebar lists General, Connection, Receiving and About, General first, below the app icon, localized product name and the listener status (listening port or failure) on every page. Its footer shows the bundle version on the left and a Quit button on the right, with an accent "New Version Available" capsule button above when an update is available (its tooltip naming the new version; clicking it opens Sparkle's update window). Footnotes appear only for security, privacy or a required action. Hidden rows leave no gap.

The Settings… menu command (⌘,) opens or focuses Settings. With Settings as the key window, ⌘Q quits AnyDock and ⌘W closes Settings. Esc closes Settings just like its close button when no control consumes the key. The wake shortcut recorder uses Esc to cancel recording, and controls such as open menus or text editors can handle Esc first. Editable fields use standard macOS editing shortcuts.

- **General:** Appearance (Follow System, Light and Dark preview tiles; a Follow System, English and 简体中文 language segmented control with an inline restart notice and Restart Now), Tray (open on arrival; copy new items; keep clipboard texts), Notifications (notify on arrival; open system notification settings), Startup & Keyboard (login startup and its errors; wake shortcut). Appearance follows the system or forces Light or Dark, applied immediately. Language follows the system or selects English or Simplified Chinese for this app only, never globally, after a restart; Restart Now reopens the same app once the current process exits.
- On the first packaged launch without a saved notification preference, AnyDock requests macOS alert and sound permission once; if granted, receipt notifications turn on automatically. Receipt notifications stay independent of automatic tray opening and copying, and re-enabling them requests permission again if needed. Each successfully received item generates one local notification with generic text. Clicking it opens the tray. General shows a hint if macOS denies notifications. macOS controls banners, sounds and Focus.
- **Connection:** one-step AirDrop setup with an editable shortcut name, manual receive-address copying, masked key copying and generic shortcut export; no Apply button. The name defaults to localized "Send to" plus the computer name, else "Send to Mac"; it is validated before signing and saved after a successful send. Saved custom names are never translated or replaced. Each Mac sends its own named shortcut so the Share Sheet can tell them apart.
- **Receiving:** listener status and failures, the save folder abbreviated with `~`, an immediate toggle to convert recognizable non-PNG screenshots to PNG, and the port (1024–65535). Only folder and port edits stage changes; Apply is enabled when folder or port differs from the applied configuration, except while applying, and Revert restores the applied values. A folder listing error appears under Save Location and clears on the next successful listing. Listener status continues to report the network listener independently. Receive-folder safety is below.
- **About:** app icon, localized product name, version and build from the bundle (hidden when it has neither), a Check for Updates button for user-initiated checks against the latest stable release (Sparkle offers installation and relaunch, and the button is disabled while unavailable), the README tagline, GitHub project and author links (https://github.com/alex-coding-studio/AnyDock, https://github.com/Cunqi), and `© 2026 Cunqi · MIT License`.

Updates: Sparkle also checks in the background at launch and then on its default daily schedule, with no setting to turn it off. A background-found update opens no window by itself; it only shows the sidebar capsule and the tray dot, which disappear when that update session ends, whether the user installs, skips or dismisses it. Updates are never downloaded or installed without the user choosing Install in Sparkle's window, and automatic installation is not offered. While a found update awaits the user, Sparkle pauses further scheduled checks, so a newer release published meanwhile is offered only after that session ends or the app relaunches.

The receive address is `http://<LocalHostName>.local:<port>/upload` from the Bonjour name, falling back to the first IPv4 address, then `localhost`. It must never block launch on DNS; a synchronous host-name lookup once stalled launch for about 30 seconds.

## Personalized shortcut

- It contains the applied address, key and chosen name, so the iPhone user enters no connection values. It is prepared and signed only in temporary storage and handed to AirDrop; completion or failure cleans up, and cleanup failures are reported and retryable. The key and sensitive signing output are never logged.
- System signing submits a copy to Apple; Settings discloses this and says to send it only to the user's own iPhone. Signing or AirDrop failures leave the manual path usable; the generic export keeps its import questions.
- Changing the receive port requires resending or updating the iPhone shortcut.

## iPhone shortcut

- It accepts images, plain and rich text, URLs and Safari pages, files, PDF and media from the Share Sheet, or reads the clipboard without input. Items go one at a time, each as its own authenticated request. Files keep name and extension; links and text are never treated as files.
- Items over 50 MB are skipped and counted as failures. HTTP errors such as 401, 413 and 415 are counted by category and the loop continues. One final 随手坞 notification reports `成功 N 项`, or `成功 N 项，失败 M 项：` followed only by non-zero reasons, such as `超过 50MB 1 项`. No per-item alerts.
- Transport errors (timeout, disconnection, unreachable Mac) may stop the whole shortcut with the standard iOS error; continuing is not promised. There is no third-party action app or persistent queue.
- Internal prompts are Chinese. Generic and personalized shortcuts come from one generator; after it changes, users must resend and add the shortcut, personalized ones included.
- Phone acceptance covers several items with Wi-Fi disconnected (stops with an error, no incomplete files on the Mac), mixed photos and files, clipboard text and links, over-limit skipping and recoverable HTTP errors. Generated-structure checks do not establish these.

## Upload protocol compatibility

- `POST /upload` authenticates with `X-AnyDock-Key` and still accepts the original raw-image body. Requests may set `X-AnyDock-Type` (`image`, `text`, `link`, `file`) and a percent-encoded UTF-8 `X-AnyDock-Filename`. Text is `text/plain; charset=utf-8`, links `text/uri-list`, files `application/octet-stream` with the type inferred from content; a filename makes text a file.
- Images are recognized from content, not a claimed extension. Text must be UTF-8; links must be HTTP or HTTPS. The 50,000,000-byte cap is checked before buffering; videos are ordinary files. At most four concurrent connections, each with a 45-second deadline.

## Received files and receive-folder safety

- Arrivals go into `Images/`, `Text/`, `Links/` or `Files/`, created on first use; existing flat images stay put. Text becomes `.txt`, links `.webloc`, and files keep their sanitized name and extension after a unique prefix. Names reject paths and control characters, drop leading and trailing dots and replace colons.
- When Receiving's screenshot-to-PNG option is on (off by default), single-frame non-PNG images recognized as screenshots from EXIF or XMP `UserComment` (`Screenshot`) are decoded upright and saved as `.png` with `UserComment` preserved, falling back to the original bytes and extension if conversion fails or the PNG exceeds 50,000,000 bytes; unrecognized images and regular photos keep their original format.
- When content is PDF, PNG, JPEG, GIF, HEIC or ZIP but the name has no extension, an undeclared one, a text one or another detectable type's, the detected extension is appended (`report.txt` with PDF content becomes `report.txt.pdf`). Formats built on those signatures (`.ai`, `.heif`, `.epub`, `.docx`) and unrecognized content keep their name. The appended extension never changes image detection, `Files/` placement or quarantine.
- Only generated items are listed; unrelated names, symlinked files and symlinked category folders are ignored.
- An upload never publishes a partial item, never overwrites a file and is refused when a category folder is replaced mid-upload. Non-images carry the quarantine attribute before success is reported. Received content is never opened or executed automatically.
- Fresh configurations use `~/Downloads/AnyDock`; an existing receive path and key are kept. Changing the receive folder never moves or deletes previous files.

## Release

Follow the [shared Sparkle 2 and signed DMG reference](https://github.com/alex-coding-studio/alex-agent-infra/blob/09ee34fb80e7b19fce49cb7f609997ea290c3c47/instructions/references/macos-sparkle-release.md) for framework embedding, signing order, feed and enclosure verification, and the two-build upgrade check. Use AnyDock's settings below for the local release.

`./scripts/release.sh` runs on a developer Mac, never in CI. It takes the version from `Resources/Info.plist` `CFBundleShortVersionString`, builds, re-signs under the hardened runtime (never with `--deep`), and produces a signed, notarized and stapled `dist/AnyDock-<version>.dmg` (volume `AnyDock` with the app and an `Applications` link) that passes `spctl`.

The mounted volume opens in Finder icon view. A bilingual background guides the user to drag the original app icon onto the Applications link. Both items remain native Finder objects.

Defaults: identity `Developer ID Application: Cunqi Xiao (2PQ63WGMNP)`, team `2PQ63WGMNP`, notary profile `MyQuickFinderApi`; override with `ANYDOCK_SIGN_IDENTITY`, `ANYDOCK_TEAM_ID`, `ANYDOCK_NOTARY_PROFILE`. A missing identity stops before building; a missing or invalid profile stops after the signed DMG exists and prints the `xcrun notarytool store-credentials` command. Credentials are never printed. Create a profile once with `xcrun notarytool store-credentials <profile> --apple-id <Apple ID> --team-id 2PQ63WGMNP` and an app-specific password.

The app ships with no entitlements and no sandbox; add the smallest set only when a new capability requires one. The release script also creates `dist/appcast.xml` after stapling, signs the feed and verifies both the feed and DMG signatures. The release Mac needs the Sparkle EdDSA key for the `com.cuxiao.mac.anydock` keychain account. Keep its private key in secure custody. The app embeds its public key. Stage the DMG and appcast together on the same GitHub Release tagged `v<version>` before publishing it as the latest stable release. The permanent feed URL uses GitHub's latest-release asset redirect. Publishing a GitHub Release, tagging and uploading are separate, user-approved steps.

Icons are approved rendered exports; replace them directly rather than regenerating. Provenance is in `Resources/Brand/README.md`.

## Operation

- The app runs as an accessory without a Dock icon. Quit with ⌘Q while the tray or Settings is key, or with Quit in the Settings sidebar. No LaunchAgent is installed; login startup is a user setting. Reopening the running app opens Settings.
- `open dist/AnyDock.app --args --settings` opens Settings on launch; `--tray` opens the tray for authorized local UI checks.
- For an authorized build swap, quit the running app before opening the build under test. Confirm only one instance remains and use the configured port when checking the listener.
- Debug with Console filtered to the AnyDock process, or run the built executable from a terminal. Where a problem requires interaction to reproduce, use narrowly scoped diagnostics and ask the user to reproduce it. Keep secrets and received content out of those diagnostics.

## Merging pull requests

`.github/workflows/auto-merge.yml` is the only merge path; authors never merge. It squash-merges an approved head once CI and every other check pass, counting only reviewers with write, maintain or admin permission, and only when no counted reviewer's latest decision is `CHANGES_REQUESTED`; never while the PR has the `needs-acceptance` label. UI-bearing PRs open with that label; the architect removes it after the user accepts the UI, which retries the merge. Review and label events run the workflow from the PR's merge ref and CI completion runs it from `main`, so a branch predating an `auto-merge.yml` change may get no run on approval or unlabel; update it from `main`. A failed check gets one comment per approved commit. Because merges by `GITHUB_TOKEN` start no push workflows, the workflow dispatches `ci.yml` on `main` after merging. Branch protection is configured separately.
