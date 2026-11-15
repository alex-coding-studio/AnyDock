[简体中文](README.md) | English

# AnyDock

Send images from your iPhone to your Mac over the local network, then drag them from the menu bar into any chat.

- One tap from the iPhone Share Sheet
- Drag straight from the menu bar tray into chats
- No shared Apple ID needed; any number of phones can send
- Local network only, no cloud

## Install

Requires macOS 14+ and Xcode 26+.

```sh
./scripts/run.sh
```

## Connect your iPhone

In Settings → Connection, choose "Send to iPhone…", AirDrop it to your phone and add the shortcut. Then pick it from any app's Share Sheet.

## Security

Use only on a trusted local network: traffic is unencrypted, so never expose the port to the Internet. The shortcut contains your connection key; send it only to your own devices.

## Development

```sh
./scripts/lint.sh && ./scripts/test.sh
```

Personally maintained; external issues and pull requests are not accepted. Forks welcome. MIT License, see [LICENSE](LICENSE).
