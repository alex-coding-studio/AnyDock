[简体中文](README.md) | English

# AnyDock · 随手坞

AnyDock is a local-network relay from your phone to your Mac, not a Dock replacement.

## Features

- Send to your Mac from the Share Sheet in one tap.
- Drag from the menu bar tray straight into a chat.
- No shared Apple ID needed; several phones can send.
- Stays on your local network, never the cloud.

## Requirements

- macOS 14 or later; building from source needs Xcode 26 or later.
- An iPhone with Shortcuts, on the same trusted local network as the Mac.

## Install

```sh
./scripts/run.sh
```

AnyDock lives in the menu bar. Open Settings with the gear button in the tray. Images are saved to `~/Downloads/SnapDock` by default.

## Set up your iPhone

1. Open Settings → Connection, choose **Send to iPhone…** and AirDrop it to your own iPhone.
2. Tap **Add Shortcut** on the iPhone.
3. Choose the shortcut when sharing an image.

Add it once on each phone. If AirDrop is unavailable, export the shortcut from Connection → Manual Setup and enter the address and key when importing it.

## Security

- Use AnyDock only on a trusted local network. Transfers are unencrypted; do not expose the receive port to the Internet.
- The shortcut contains your connection key. Send it only to your own phones.

## Development

```sh
./scripts/lint.sh
./scripts/test.sh
```

See [AGENTS.md](AGENTS.md), [ProjectContext.md](ProjectContext.md) and [docs/PROJECT.md](docs/PROJECT.md) for engineering details.

## Contributing

This is a personally maintained project and is not accepting external issues or pull requests at this time; you are welcome to fork and modify it under the MIT license.

## License

MIT. See [LICENSE](LICENSE).
