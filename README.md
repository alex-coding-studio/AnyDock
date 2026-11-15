# AnyDock · 随手坞

AnyDock (随手坞) is a local-network relay from your phone to your Mac. Use its image tray to browse, select and drag original images from the menu bar into a chat. The app supports English and Simplified Chinese, follows the system language by default, and offers an app-specific language override.

## Features

- A 450 × 520 pt masonry tray with three columns by default and a choice of two to five columns. Long images show their top portion without stretching.
- Liquid Glass on macOS 26 or later, with native materials on older supported systems. Choose System, Light or Dark appearance; changes apply immediately to the tray and Settings.
- English and Simplified Chinese interface, with localized counts, menus, tooltips and accessibility labels. Language changes take effect after restarting.
- Native click, Command/Shift and rubber-band selection, original-file dragging, copying and Finder reveal. A successful drop closes the tray.
- Quick Look with Space or a double-click; arrow keys browse selected images, and Space closes the preview while preserving selection.
- Automatic reveal for new receipts, independent latest-receipt highlighting and receipt-time capsules with full timestamps on hover.
- A folder refresh each time you open the tray manually, so images restored or removed in Finder appear without restarting. Closing the tray clears the selection.
- Recoverable recycling: the trash button always asks for confirmation, targeting the selection or all listed images. Escape or clicking outside cancels and leaves the tray open. Command-Delete and the context menu recycle selected images directly. Received originals are never overwritten or deleted automatically.

## Requirements

- **macOS 14 or later** to run AnyDock. **Liquid Glass requires macOS 26 or later**.
- For source builds, use Xcode 27.2 / Apple Swift 6.4.2, or a compatible Swift 6 toolchain with an SDK containing the macOS 26 glass APIs. Development scripts also use system Python 3. No third-party package installation is required.
- An iPhone with Shortcuts, connected to the same trusted local network as the Mac. One-step setup uses AirDrop.

## Build and run from source

Run these commands from the project root:

```sh
./scripts/build.sh
open dist/AnyDock.app
```

The build script assembles and ad-hoc signs `dist/AnyDock.app`. To build and open it in one step instead:

```sh
./scripts/run.sh
```

AnyDock runs in the menu bar without a Dock icon. Open Settings with the gear button in the tray. General (通用) controls thumbnail columns, appearance, language and launch at login and provides Quit; Connection (连接) sets up the iPhone; Receiving (接收) shows receiver status and lets you change the save folder and port. Folder and port changes take effect when you choose Apply (应用). The default folder is `~/Downloads/SnapDock`, and the default receive port is **8765**. Switching folders does not move existing images.

## Settings

- **Appearance:** Follow System, Light or Dark. The choice is saved and applies immediately to both the tray and Settings, including Liquid Glass.
- **Language:** Follow System, English or 简体中文. This changes only AnyDock's own `AppleLanguages` preference; Follow System removes that override. Settings shows a restart notice and a **Restart Now** button when the selection differs from the one used at launch.
- **Localization:** English is the development language. SwiftPM bundles `en.lproj` and `zh-Hans.lproj` resources, including plural rules; `scripts/build.sh` embeds the resource bundle and localized app metadata in the `.app`. The generated iPhone shortcut's internal prompts remain in Chinese for now.

## Set up your iPhone

### One-step AirDrop setup

1. Open Settings → Connection (连接).
2. Choose a shortcut name. It is remembered and defaults to **Send to** or **发送到** followed by the computer name, according to the app language. Existing custom names are preserved. For multiple Macs, send a separately named shortcut from each Mac.
3. Choose **发送到 iPhone…** and select your own iPhone in AirDrop. AnyDock fills the current receive address and connection key into the shortcut and signs it using the system Shortcuts tool.
4. Accept the file on the iPhone and tap **添加快捷指令**. The connection values are already filled in.
5. Share an image from the iPhone Share Sheet and choose the shortcut by its name.

If signing or AirDrop is unavailable, Settings shows the reason; manual setup remains available.

### Manual export

1. In Connection (连接), find Manual Setup (手动设置). Copy the receive address and connection key, and use **导出…** to save the generic **发送到 Mac** shortcut.
2. Transfer the exported `.shortcut` file to your iPhone, open it and fill in the address and key when prompted during import.
3. Share an image and choose **发送到 Mac** in the Share Sheet.

The default port is **8765**. After changing it in Receiving (接收), resend the personalized shortcut or update the address in the existing iPhone shortcut.

## Security

Use AnyDock only on a **trusted local network**. HTTP does not encrypt images or the connection key; do not expose the receive port to the Internet. Keep your connection key private.

A personalized shortcut contains the key, so send it only to your own iPhone. System shortcut signing submits a copy to Apple for validation. Keep personalized shortcuts and receiver configuration out of public repositories and shared logs.

AnyDock validates incoming image data, saves unique originals and never overwrites or automatically deletes them. User-requested recycling is limited to AnyDock images listed in the current receive folder and moves them to the system Trash, where they can be recovered.

## Development

```sh
./scripts/lint.sh
./scripts/test.sh
```

Read [AGENTS.md](AGENTS.md), [ProjectContext.md](ProjectContext.md) and [docs/PROJECT.md](docs/PROJECT.md) for contribution conventions, architecture and engineering details. Automated checks do not replace actual iPhone upload or target-chat acceptance.

## Compatibility with existing installations

The app keeps the `studio.alex.snapdock` bundle identifier, existing preferences, connection key and `Application Support/SnapDock` configuration location. The default receive folder remains `~/Downloads/SnapDock`; your saved folder is preserved. New images use `AnyDock-` filenames, while existing `SnapDock-` images remain visible and can still be recycled. Existing iPhone shortcuts continue to use the same upload protocol.

## Contributing

This is a personally maintained project and is not accepting external issues or pull requests at this time; you are welcome to fork and modify it under the MIT license.

这是个人维护的项目，目前不接受外部 issue 和 pull request；欢迎 fork 后按 MIT 许可证自行修改。

## License

License: **MIT**. See [LICENSE](LICENSE).
