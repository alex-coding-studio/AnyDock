import AnyDockCore
import AppKit
import Testing
@testable import AnyDock

@MainActor
@Test("设置界面延迟构建后仍保留启动时写入的接收状态图标")
func receiverStatusSurvivesDeferredSettingsBuild() {
    let inbox = Inbox(
        configuration: ConnectionConfiguration(
            receiver: .init(directory: FileManager.default.temporaryDirectory, token: "test-token")
        ),
        store: ConnectionConfigurationStore(
            file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    )
    let settings = SettingsController(inbox: inbox, hotKeys: GlobalHotKeyCenter())
    settings.setStatus("failed", isError: true)
    settings.prepareInterface()
    #expect(settings.window?.contentViewController != nil)
    #expect(settings.statusIcon.image?.accessibilityDescription == L10n.text("Receiver Failed"))
}

@MainActor
@Test("关于页的版本号来自 Bundle 的版本和构建号，缺少时不显示")
func aboutVersionComesFromBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func bundle(_ info: [String: String]) throws -> Bundle {
        let app = root.appendingPathComponent(UUID().uuidString + ".app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: info.merging([
                "CFBundleIdentifier": "test." + UUID().uuidString,
            ]) { a, _ in
                a
            },
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: app))
    }
    let versioned = try bundle(["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "42"])
    #expect(
        SettingsController.versionText(bundle: versioned) == L10n.text(
            "Version %@ (%@)",
            "9.8.7",
            "42"
        )
    )
    #expect(try SettingsController.versionText(bundle: bundle([:])) == nil)
}
