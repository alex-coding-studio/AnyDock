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
