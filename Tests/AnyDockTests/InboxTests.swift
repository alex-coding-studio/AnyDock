import AnyDockCore
import Foundation
import Testing
@testable import AnyDock

@MainActor
@Test("只保存发送端设置时保留当前的接收端配置，不会用旧副本覆盖")
func savingSenderKeepsCurrentReceiver() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConnectionConfigurationStore(
        file: folder.appendingPathComponent("configuration.json")
    )
    let receiver = ConnectionConfiguration.Receiver(
        port: 50123,
        directory: folder.appendingPathComponent("Inbox", isDirectory: true),
        token: String(repeating: "a", count: 32)
    )
    let inbox = Inbox(configuration: ConnectionConfiguration(receiver: receiver), store: store)
    try inbox.apply(sender: ConnectionConfiguration.Sender(shortcutName: "Send to Test"))
    let saved = try store.load()
    #expect(saved.receiver == receiver)
    #expect(saved.sender.shortcutName == "Send to Test")
    #expect(inbox.configuration.receiver == receiver)
}

@MainActor
@Test("接收目录恢复可读后清除目录提示，重列失败和恢复都不改监听状态")
func folderReadErrorClearsIndependentlyOfListener() async throws {
    let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let images = folder.appendingPathComponent("Images")
    let manager = FileManager.default
    try manager.createDirectory(at: images, withIntermediateDirectories: true)
    defer {
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path)
        try? manager.removeItem(at: folder)
    }
    let inbox = Inbox(
        configuration: ConnectionConfiguration(receiver: .init(
            directory: folder,
            token: String(repeating: "a", count: 32)
        )),
        store: ConnectionConfigurationStore(
            file: folder.appendingPathComponent("configuration.json")
        )
    )
    try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: images.path)
    await inbox.reload()
    let settings = ReceivingSettingsViewModel(receiver: inbox)
    #expect(settings.state.folderReadError != nil)
    #expect(settings.state.status == ListenerStatus(.starting))
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path)
    await inbox.reload()
    #expect(settings.state.folderReadError == nil)
    #expect(settings.state.status == ListenerStatus(.starting))
}
