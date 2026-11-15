# Engineering Operations

## UI Foundation

Use native AppKit controls and semantic colors. General selects system, Light or Dark appearance through `NSApp.appearance` (`nil`, `.aqua`, `.darkAqua`), restored before constructing the UI and applied immediately to existing windows and glass materials. No external UI foundation is installed. The 450 × 520 pt tray uses `NSGlassEffectView` behind a macOS 26 availability check and `NSVisualEffectView` on older supported systems. Keep thumbnail colors intact.

The tray defaults to three masonry columns; General offers two through five, applies the change immediately and persists it without restarting the receiver. Cache image height/width ratios before layout. `MasonryCollectionLayout` uses the pure `AnyDockCore.MasonryLayout` shortest-column placement, preferring the leftmost column on ties. Image heights are capped at 2.5 times the column width and capped images show their top portion with aspect fill. The layout owns the 24 pt top/side margins, 10 pt inter-image spacing and scrollable bottom inset beneath the floating controls.

Keep native `NSCollectionView` click/modifier and rubber-band selection. Only image rectangles start selection or original-file dragging; gaps and margins start rubber-band selection. Selected items have an accent border and corner checkmark. The latest receipt has a separate accent time capsule and soft outline, which can coexist with selection. Time capsules overlay the lower-left of each image, show `HH:mm` today or month/day otherwise, and expose the complete timestamp on hover. Folder sits at the left of the floating bottom controls; the optional selection count, trash and Settings controls sit at the right. Preserve button accessibility labels and tooltips. Configuration and listener errors belong in Settings. The empty tray shows a tray icon, `还没有收到截图` and `在 iPhone 上分享图片，选择「发送到 Mac」`, without configuration or listener errors.

Space or double-click opens `QLPreviewPanel` for the selected files; arrows navigate the preview set and Space closes it. Keep the standard `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl` lifecycle. Hold the tray open while Quick Look is shown and preserve selection when only the preview closes. Copy and Finder reveal use the selected originals; dragging exports original-file URLs and closes the tray on a successful drop.

The trash button always opens a transient confirmation anchored above it. With a selection, the title is `将 N 张截图移到废纸篓？` and the action is `将 N 张移到废纸篓`; with no selection, use `将全部 N 张截图移到废纸篓？` and `全部移到废纸篓`. Escape and outside clicks cancel; the tray stays open while the confirmation is shown and after it closes. Command-Delete and the context menu recycle selected files without confirmation. Keep presentation held through confirmation closure and recycling. Limit requests to the current receive folder's `ImageStore.list` set, call `NSWorkspace.recycle`, then reload the list and report failures with remaining images visible.

New receipts reveal the tray and scroll into view; an open tray updates in place. Loading existing history does not reveal it. Every manual opening rereads the receive folder through `reloadImages`, reflecting files removed or restored in Finder without live folder watching. Automatic opening for a new receipt skips the extra reload. The outer popover's `popoverDidClose` clears selection and updates the controls for the next opening; closing only Quick Look or the trash confirmation does not clear it.

## Settings and shortcut setup

Settings uses native toolbar tabs ordered General, Connection and Receiving, with General selected initially. Content uses grouped inset sections with separators and footnotes.

- **General:** immediate, persisted thumbnail column count and system/Light/Dark appearance; app-local system/English/Simplified Chinese language selection with a restart notice and Restart Now action; immediate login startup with errors in General; an app identity card and Quit. The restart helper waits for the current process to exit before reopening the same app bundle.
- **Connection:** one-step named AirDrop setup, plus manual receive-address copying, masked connection-key copying and generic shortcut export. The shortcut name persists immediately in UserDefaults and defaults to localized `Send to ` / `发送到 ` plus `Host.current().localizedName`, falling back to localized `Send to Mac`. Saved custom names are not translated or replaced. Name validation runs before signing. Each Mac supplies a separate named shortcut, so its entry can be distinguished in the iPhone Share Sheet. There is no Apply button or listener status in this tab.
- **Receiving:** listener status and failures, a save-folder path consistently abbreviated with `~`, and port edits. Only this tab stages changes. Its bottom Apply button is enabled when the selected folder or port differs from the applied configuration, except while applying. Port validation remains 1024–65535; changing folders never moves or deletes existing originals.

`ShortcutInstaller` personalizes the bundled unsigned template with the applied receive address, key and chosen name. It writes sensitive output only in temporary storage, signs with `/usr/bin/shortcuts sign --mode anyone`, and supplies the signed file to the AirDrop sharing service. Sharing completion or failure cleans up temporary files; cleanup failures are reported and can be retried. Never log the key, print sensitive signing output or copy personalized files into the source tree or bundle. Settings explains that system signing submits a copy to Apple for validation and that the shortcut should be sent only to the user's own iPhone. On the iPhone, the recipient adds the shortcut without entering connection values. Signing or AirDrop failures leave the manual path usable. The generic manual export retains its import questions. Resend or update the iPhone shortcut after changing the receive port.

The selected monochrome brand master and its prompt are retained in `Resources/Brand`. `BrandIcon.swift` draws the small template variant for the existing square menu bar slot. Rebuild `Resources/AppIcon.icns` from the selected master with `./scripts/icon.sh` when changing the artwork.

## Localization

English is the development language. The executable target declares `.process("Resources")` and `defaultLocalization: "en"`; these are localization resource declarations, not dependencies. Load UI text through `L10n.text` and `Bundle.module`. The `en.lproj` and `zh-Hans.lproj` resources contain strings and `.stringsdict` count/plural rules, covering the tray, Settings, shortcut preparation errors and localized default shortcut names. System errors retain the platform's localized descriptions. The generic shortcut resource and Python-generated shortcut-internal prompts remain Chinese.

The app's `Info.plist` declares both supported localizations. `scripts/build.sh` embeds the SwiftPM resource bundle and copies each localized `InfoPlist.strings` into the app's resource directory, so privacy prompts and bundle language negotiation work outside the build tree. Keep new strings and placeholders consistent across both localizations.

Language selection reads only the app's persistent preference domain, not inherited global `AppleLanguages`. English stores `["en"]`, Simplified Chinese stores `["zh-Hans"]`, and Follow System removes the app-local key. This preference is read by Foundation on the next launch; Settings compares it with the launch selection to show the restart action. The preference test uses an isolated suite and never changes user preferences.

## Build and run

Use `./scripts/build.sh`, `./scripts/run.sh`, `./scripts/lint.sh` and `./scripts/test.sh`. Use a compatible Swift 6 compiler and an SDK containing the macOS 26 glass APIs; the development toolchain is Xcode 27.2 / Apple Swift 6.4.2. The selected Xcode compiler builds the Swift package and the build script creates and ad-hoc signs `dist/AnyDock.app`. Build products are disposable. No dependency installation is required. Keep the app bundle identifier `studio.alex.snapdock`.

## Operation

The app runs as an accessory with no Dock icon. Quit through Settings. No LaunchAgent is installed. Login startup is a user-controlled setting in the app. The default port is 8765. Debug with Console using the AnyDock process, or launch the built executable from a terminal. Do not expose authentication tokens in logs.

To open the configuration window on a fresh debug launch, use `open dist/AnyDock.app --args --settings`. Reopening an already-running app also opens Settings. Use `--tray` instead of `--settings` for direct inspection of the menu bar popover during authorized local UI verification.

Only files generated by AnyDock in the selected inbox are shown, using the same `ImageStore.list` set that limits recycling. App configuration and received originals remain outside the checkout. Receiver configuration uses Application Support; the column and personalized shortcut name preferences use UserDefaults. Never overwrite or automatically delete received originals.

## Scope of evidence

The UI rules above describe the current product behavior. Local build and automated checks do not establish visual interaction, iPhone import/upload or compatibility with a particular chat client. Those outcomes require their own acceptance evidence. Report actual validation results and distinguish automated checks from hands-on acceptance.

## Rename compatibility

Keep the `studio.alex.snapdock` bundle identifier and Logger subsystem, all UserDefaults keys, `Application Support/SnapDock` configuration directory and existing receive-folder behavior unchanged. New files use `AnyDock-`; `ImageStore.list` must also include legacy `SnapDock-` images, and recycling must use that same set. Retain the `X-SnapDock-Key` upload header so installed phone shortcuts keep working. Product names are localized as AnyDock in English and 随手坞 in Simplified Chinese.
