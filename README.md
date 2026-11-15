简体中文 | [English](README.en.md)

# 随手坞 · AnyDock

把 iPhone 上的图片通过局域网发到 Mac，在菜单栏直接拖进聊天。

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

## 安全

只在可信局域网使用：传输不加密，不要把端口暴露到公网。快捷指令里有连接密钥，只发给自己的设备。

## 开发

```sh
./scripts/lint.sh && ./scripts/test.sh
```

个人维护，不接受外部 issue 和 PR，欢迎 fork。MIT 许可证，见 [LICENSE](LICENSE)。
