[简体中文](README.md) | English

<p align="center"><img src="Resources/Brand/AnyDockIcon.png" alt="AnyDock" width="128"></p>

<h1 align="center">AnyDock</h1>

<p align="center">From iPhone to Mac, in one easy hand-over.</p>

<p align="center">
  <a href="https://github.com/alex-coding-studio/AnyDock/actions/workflows/ci.yml"><img src="https://github.com/alex-coding-studio/AnyDock/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/alex-coding-studio/AnyDock/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <a href="https://github.com/alex-coding-studio/AnyDock"><img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" alt="Platform: macOS 14+"></a>
</p>

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

## Upgrading and migration

The app now uses `com.cuxiao.mac.anydock`. Before creating the UI, it copies previous preferences and `Application Support/SnapDock/configuration.json` into the new preference domain and `Application Support/AnyDock/configuration.json`, preserving the connection key, receive folder, port, appearance, language, automatic clipboard copy and shortcut name. Old data is retained; existing new configuration files and preference values are not overwritten.

Successful migration is not repeated. On failure, Receiving explains that the old configuration could not be migrated and the iPhone shortcut is temporarily unavailable. The app shows in-memory defaults with an empty key, pauses receiving and does not save or personalize those fallback settings. Fix the file-access or old-configuration issue, then restart to retry; failure does not set the completion marker.

Login items are tied to the bundle identifier. After upgrading, switch launch at login off and back on in Settings; the app does not change system login items automatically.

## Security

Use only on a trusted local network: traffic is unencrypted, so never expose the port to the Internet. The shortcut contains your connection key; send it only to your own devices.

## Development

```sh
./scripts/lint.sh && ./scripts/test.sh
```

Personally maintained; external issues and pull requests are not accepted. Forks welcome. MIT License, see [LICENSE](LICENSE).
