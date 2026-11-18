[简体中文](README.md) | English

<p align="center"><img src="Resources/Brand/AnyDockIcon.png" alt="AnyDock" width="128"></p>

<h1 align="center">AnyDock</h1>

<p align="center">From iPhone to Mac, in one easy hand-over.</p>

<p align="center">
  <a href="https://github.com/alex-coding-studio/AnyDock/releases/latest"><strong>Download the latest DMG</strong></a>
  · Apple silicon Mac · macOS 14+
</p>

Send images, text, links, and files from your iPhone to your Mac menu bar with a shortcut. Transfers stay on your local network, and each iPhone can use its own Apple ID.

<p align="center"><img src="docs/images/anydock-tray.png" alt="AnyDock menu bar tray showing content filters and sample items" width="460"></p>

## Install

Download the `.dmg` under **Assets** on the release page and drag AnyDock into **Applications**. Open it, then click the menu bar icon. AnyDock checks for new versions in the background and shows a hint in the Settings sidebar and on the tray's Settings button; you can also check manually under **Settings → About**.

## Send from your iPhone

1. Use the gear in the Mac tray to open **Settings → Connection → Send to iPhone…**, then AirDrop the shortcut to your own iPhone.
2. Tap **Add Shortcut** on your iPhone. The address and connection key are already filled in.
3. With both devices on the same local network, run the shortcut from the iPhone Share Sheet. Allow local network access if prompted. On your Mac, drag the received item out of the tray, copy it with ⌘C, or press Space to preview it.

If AirDrop is unavailable, export the generic shortcut from **Connection → Manual Setup**. Enter the receive address and key when importing it on the iPhone.

## Useful settings

- **Copy on arrival.** Enable **Copy new items automatically** under **Settings → General → Tray**, then paste in your destination app.
- **Send with Back Tap.** On iPhone, assign the shortcut in **Settings → Accessibility → Touch → Back Tap**. Copy an item, then tap the back of your iPhone to send it. [Apple's Back Tap guide](https://support.apple.com/en-ca/guide/shortcuts/apd897693606/ios)
- **Find received files.** Click **Show in Finder** under **Settings → Receiving**. The default folder is `~/Downloads/AnyDock`.

If a transfer fails, check that AnyDock is listening on the Mac, both devices are on the same local network, and Shortcuts has local network access. Resend the shortcut if you change the port. The limit is 50 MB per item.

Transfers use unencrypted HTTP on the local network. Use a trusted network, keep the receiving port off the public internet, and keep personalized shortcuts private because they contain your connection key.

## Development

Run `./scripts/run.sh` with Xcode 26 or later. See [ProjectContext.md](ProjectContext.md) for the development environment and checks.

Personally maintained. External issues and pull requests are closed to contributions. Forks are welcome. [MIT License](LICENSE) · [CI](https://github.com/alex-coding-studio/AnyDock/actions/workflows/ci.yml) · [SnapKit](https://github.com/SnapKit/SnapKit). Third-party licenses ship with the app.
