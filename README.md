简体中文 | [English](README.en.md)

<p align="center"><img src="Resources/Brand/AnyDockIcon.png" alt="随手坞 · AnyDock" width="128"></p>

<h1 align="center">随手坞 · AnyDock</h1>

<p align="center">从 iPhone 到 Mac，随手一递。</p>

<p align="center">
  <a href="https://github.com/alex-coding-studio/AnyDock/actions/workflows/ci.yml"><img src="https://github.com/alex-coding-studio/AnyDock/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/alex-coding-studio/AnyDock/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <a href="https://github.com/alex-coding-studio/AnyDock"><img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" alt="Platform: macOS 14+"></a>
</p>

- 分享菜单一键发送
- 从菜单栏托盘拖进聊天
- 不需要同一个 Apple ID，多台手机都能发
- 只走局域网，不经过云端

## 安装

需要 macOS 14+。从 [GitHub Releases](https://github.com/alex-coding-studio/AnyDock/releases) 下载 DMG，把 AnyDock 拖进「应用程序」。

从源码构建需要 Xcode 26+：

```sh
./scripts/run.sh
```

## 连接 iPhone

在设置的「连接」里点「发送到 iPhone…」，用 AirDrop 发到手机并添加快捷指令。之后在任意 App 的分享菜单里选它。

## 安全

只在可信局域网使用：传输不加密，不要把端口暴露到公网。快捷指令里有连接密钥，只发给自己的设备。

## 开发

```sh
./scripts/lint.sh && ./scripts/test.sh
```

个人维护，不接受外部 issue 和 PR，欢迎 fork。MIT 许可证，见 [LICENSE](LICENSE)。

布局使用 [SnapKit](https://github.com/SnapKit/SnapKit)（MIT）；完整第三方许可证随应用资源分发。
