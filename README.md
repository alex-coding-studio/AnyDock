简体中文 | [English](README.en.md)

# 随手坞 · AnyDock

随手坞是从手机到 Mac 的局域网中转工具，不是 Dock 栏的替代品。在 iPhone 上用分享菜单把图片发到 Mac，再从菜单栏托盘直接拖进聊天窗口。

## 功能

- 在 iPhone 分享菜单里一键发送，图片直接存到 Mac。
- 从菜单栏托盘把原图拖进聊天或其他 App，也可以复制、预览。
- 不需要同一个 Apple ID（「通用剪贴板」和 Handoff 都要求同一个 Apple ID），多台手机都能发到同一台 Mac。
- 只走局域网，不经过云端。
- 删除只会移到废纸篓，收到的原件不会被自动删除。
- 支持简体中文和英文界面，以及浅色、深色外观。

## 系统要求

- macOS 14 或更高版本。
- 装有「快捷指令」的 iPhone，和 Mac 连在同一个可信局域网。

## 安装

从源码构建并打开：

```sh
./scripts/run.sh
```

需要 Xcode 26 或更高版本，不需要安装第三方依赖。随手坞只在菜单栏显示，没有 Dock 图标；点托盘里的齿轮按钮打开设置。图片默认保存到 `~/Downloads/SnapDock`，可以在设置的「接收」里修改。

## 设置 iPhone

1. 打开设置 →「连接」，点「发送到 iPhone…」，通过 AirDrop 发给自己的 iPhone。
2. 在 iPhone 上接收文件，点「添加快捷指令」。接收地址和连接密钥已经填好。
3. 在任意 App 里分享图片，选择这个快捷指令。

每台要发送的手机都按这个步骤添加一次。AirDrop 或签名不可用时，可以在「连接」→「手动设置」里导出通用快捷指令，导入时手动填写地址和密钥。更改端口后需要重新发送快捷指令。

## 安全

- 只在可信局域网使用。传输走 HTTP，不加密，不要把接收端口暴露到公网。
- 快捷指令里含有连接密钥，只发给自己的手机，也不要把它放进公开仓库或日志。系统签名快捷指令时会把一份副本交给 Apple 验证。

## 开发

```sh
./scripts/lint.sh
./scripts/test.sh
```

贡献约定、架构和工程细节见 [AGENTS.md](AGENTS.md)、[ProjectContext.md](ProjectContext.md) 和 [docs/PROJECT.md](docs/PROJECT.md)。

## 参与贡献

这是个人维护的项目，目前不接受外部 issue 和 pull request；欢迎 fork 后按 MIT 许可证自行修改。

## 许可证

MIT，见 [LICENSE](LICENSE)。
