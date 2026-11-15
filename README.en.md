[简体中文](README.md) | English

# AnyDock · 随手坞

AnyDock is a local-network relay from your phone to your Mac, not a Dock replacement. Send images from the iPhone Share Sheet, then drag them from the menu bar tray straight into a chat.

## Features

- Send from the iPhone Share Sheet in one tap; images land on your Mac.
- Drag originals from the menu bar tray into a chat or any other app, or copy and preview them.
- No shared Apple ID required (Universal Clipboard and Handoff both need one), so several phones can send to the same Mac.
- Stays on your local network; nothing goes through the cloud.
- Deleting only moves images to the Trash; received originals are never deleted automatically.
- English and Simplified Chinese interface, with light and dark appearance.

## Requirements

- macOS 14 or later.
- An iPhone with Shortcuts, on the same trusted local network as the Mac.

## Install

Build from source and open the app:

```sh
./scripts/run.sh
```

This needs Xcode 26 or later; no third-party packages are required. AnyDock lives in the menu bar without a Dock icon; open Settings with the gear button in the tray. Images are saved to `~/Downloads/SnapDock` by default, which you can change under Receiving in Settings.

## Set up your iPhone

1. Open Settings → Connection, choose **Send to iPhone…** and AirDrop it to your own iPhone.
2. Accept the file on the iPhone and tap **Add Shortcut**. The receive address and connection key are already filled in.
3. Share an image from any app and choose the shortcut.

Repeat this once for each phone that will send. If AirDrop or signing is unavailable, use **Export…** under Connection → Manual Setup to save a generic shortcut and enter the address and key when importing it. After changing the port, send the shortcut again.

## Security

- Use AnyDock only on a trusted local network. Transfers use unencrypted HTTP; do not expose the receive port to the Internet.
- A shortcut contains your connection key. Send it only to your own phones and keep it out of public repositories and logs. System shortcut signing submits a copy to Apple for validation.

## Development

```sh
./scripts/lint.sh
./scripts/test.sh
```

Read [AGENTS.md](AGENTS.md), [ProjectContext.md](ProjectContext.md) and [docs/PROJECT.md](docs/PROJECT.md) for contribution conventions, architecture and engineering details.

## Contributing

This is a personally maintained project and is not accepting external issues or pull requests at this time; you are welcome to fork and modify it under the MIT license.

## License

MIT. See [LICENSE](LICENSE).
