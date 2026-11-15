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

需要 macOS 14+ 和 Xcode 26+。

```sh
./scripts/run.sh
```

## 连接 iPhone

在设置的「连接」里点「发送到 iPhone…」，用 AirDrop 发到手机并添加快捷指令。之后在任意 App 的分享菜单里选它。

## 升级与迁移

新版使用 `com.cuxiao.mac.anydock`。首次启动会把旧偏好及 `Application Support/SnapDock/configuration.json` 复制到新偏好域与 `Application Support/AnyDock/configuration.json`，保留连接密钥、接收目录、端口、外观、语言和快捷指令名称。旧数据不会删除，已有的新配置不会覆盖。

迁移成功后不再重复；失败时接收页会提示「旧配置迁移失败，iPhone 快捷指令暂时不可用」。此时只显示空密钥的内存默认配置，不接收、不写盘，也不发送个性化快捷指令；修复文件访问或旧配置问题后重启会重试。

登录项绑定在 Bundle ID 上：升级后请在设置里把开机启动关闭，再打开一次。App 不会自动修改系统登录项。

## 安全

只在可信局域网使用：传输不加密，不要把端口暴露到公网。快捷指令里有连接密钥，只发给自己的设备。

## 开发

```sh
./scripts/lint.sh && ./scripts/test.sh
```

个人维护，不接受外部 issue 和 PR，欢迎 fork。MIT 许可证，见 [LICENSE](LICENSE)。
