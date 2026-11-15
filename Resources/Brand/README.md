# AnyDock Brand Assets

The V2 app artwork depicts a receiving tray with a photo, a video card, a text card and falling motion lines. The user generated it through Codex imagegen and normalized it with Apple Icon Composer.

- `../AppIcon.icns` is copied directly from the supplied V2 macOS icon package. Apple's renderer produced its ten macOS size representations, including system-rounded corners and transparent outer margins. This is the app icon used by the SwiftPM/manual app-bundle build.
- `AnyDockIcon.png` is the supplied `SnapDock-legacy-1024.png`, retained under the existing resource name for the Settings About card. It is a 1024 × 1024 compatibility image with system-rounded corners and transparent margins.
- `MenuBarTemplate.png` and `MenuBarTemplate@2x.png` come from the user's `SnapDock-menu-tray-v1.png` line drawing. Black ink becomes opaque black, white becomes transparent and antialiased edges retain intermediate alpha. Excess white space is cropped and a small transparent margin is retained. The files are 18 × 18 and 36 × 36 pixels for an 18 pt menu bar slot. AppKit loads both representations and uses `isTemplate = true` to follow system appearance.

The old icon-generation script has been removed: regenerating an icns with `sips` from the already-rounded, padded About-card PNG would degrade the supplied native icon. For a future icon update, replace the rendered icns and About-card PNG with the corresponding approved exports. The obsolete generation prompt was removed with the previous artwork.

Only the delivered icns, About-card PNG and two menu bar PNGs are included. Original working images, previews, Icon Composer projects and the one-off conversion script remain outside the repository.

These assets are distributed with the project under the repository's MIT license.
