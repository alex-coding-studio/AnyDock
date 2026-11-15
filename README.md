简体中文 | [English](README.en.md)

# 随手坞 · AnyDock

随手坞是从手机到 Mac 的局域网中转工具，不是 Dock 栏的替代品。

## 功能

- 分享菜单一键发送到 Mac。
- 从菜单栏托盘直接拖进聊天。
- 不需要同一个 Apple ID，多台手机都能发。
- 只走局域网，不经过云端。

## 系统要求

- macOS 14 或更高版本；从源码构建需要 Xcode 26 或更高版本。
- 装有「快捷指令」的 iPhone，和 Mac 在同一个可信局域网。

## 安装

```sh
./scripts/run.sh
```

随手坞只在菜单栏显示。点托盘里的齿轮按钮打开设置。图片默认保存在 `~/Downloads/SnapDock`。

## 设置 iPhone

1. 打开设置 →「连接」，点「发送到 iPhone…」，用 AirDrop 发给自己的 iPhone。
2. 在 iPhone 上点「添加快捷指令」。
3. 分享图片时选择这个快捷指令。

每台手机各添加一次。AirDrop 不可用时，在「连接」→「手动设置」里导出快捷指令，导入时填写地址和密钥。

## 安全

- 只在可信局域网使用。传输不加密，不要把接收端口暴露到公网。
- 快捷指令含有连接密钥，只发给自己的手机。

## 开发

```sh
./scripts/lint.sh
./scripts/test.sh
```

工程细节见 [AGENTS.md](AGENTS.md)、[ProjectContext.md](ProjectContext.md) 和 [docs/PROJECT.md](docs/PROJECT.md)。

## 参与贡献

这是个人维护的项目，目前不接受外部 issue 和 pull request；欢迎 fork 后按 MIT 许可证自行修改。

## 许可证

MIT，见 [LICENSE](LICENSE)。
