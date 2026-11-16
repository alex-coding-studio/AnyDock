import AnyDockCore
import AppKit
import Combine
import Foundation
import Testing
@testable import AnyDock

@MainActor
private func settled<State: Sendable>(
    _ publisher: AnyPublisher<State, Never>,
    where predicate: @escaping (State) -> Bool
) async -> State {
    var subscription: AnyCancellable?
    defer { subscription?.cancel() }
    return await withCheckedContinuation { continuation in
        subscription = publisher.first(where: predicate).sink { continuation.resume(returning: $0) }
    }
}

@MainActor
@Test("接收页只有文件夹或端口与已应用配置不同时才能应用，还原后恢复已应用值")
func receivingApplyAndRevertFollowAppliedConfiguration() async {
    let receiver = FakeReceiver(port: 8765)
    let viewModel = ReceivingSettingsViewModel(receiver: receiver)
    #expect(viewModel.state.canApply == false)

    viewModel.setPortText(" 8765 ")
    #expect(viewModel.state.canApply == false)

    viewModel.setPortText("9000")
    #expect(viewModel.state.canApply)
    viewModel.revert()
    #expect(viewModel.state.portText == "8765")
    #expect(viewModel.state.hasChanges == false)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    viewModel.selectFolder(folder)
    viewModel.setPortText("9000")
    viewModel.apply()
    #expect(viewModel.state.isApplying)
    #expect(viewModel.state.canApply == false)

    let applied = await settled(viewModel.$state.eraseToAnyPublisher()) { !$0.isApplying }
    #expect(applied.hasChanges == false)
    #expect(receiver.appliedReceivers.map(\.port) == [9000])
    #expect(receiver.appliedReceivers.map(\.directory) == [folder])
}

@MainActor
@Test("端口必须是 1024–65535 的整数，否则提示错误且不应用", arguments: ["80", "abc", "70000", "1023"])
func receivingRejectsPortsOutsideRange(text: String) {
    let receiver = FakeReceiver()
    let viewModel = ReceivingSettingsViewModel(receiver: receiver)
    viewModel.setPortText(text)
    viewModel.apply()
    #expect(
        viewModel.state.errorMessage == L10n.text(
            "Enter a whole-number port between 1024 and 65535."
        )
    )
    #expect(viewModel.state.isApplying == false)
    #expect(receiver.appliedReceivers.isEmpty)
}

@MainActor
@Test("底栏说明哪一项未应用：只改端口、只改文件夹或两者都改")
func receivingPendingMessageNamesChangedItem() {
    let viewModel = ReceivingSettingsViewModel(receiver: FakeReceiver())
    viewModel.setPortText("9002")
    #expect(viewModel.state.pendingMessage == L10n.text("settings.pending.port"))
    viewModel.selectFolder(
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    )
    #expect(viewModel.state.pendingMessage == L10n.text("Unapplied changes"))
    viewModel.setPortText("8765")
    #expect(viewModel.state.pendingMessage == L10n.text("settings.pending.folder"))
}

@MainActor
@Test("应用失败时保留未应用的修改并显示错误")
func receivingKeepsChangesWhenApplyFails() async {
    let receiver = FakeReceiver()
    receiver.applyError = CocoaError(.fileWriteNoPermission)
    let viewModel = ReceivingSettingsViewModel(receiver: receiver)
    viewModel.setPortText("9001")
    viewModel.apply()
    let failed = await settled(viewModel.$state.eraseToAnyPublisher()) { !$0.isApplying }
    #expect(failed.hasChanges)
    #expect(failed.errorMessage == CocoaError(.fileWriteNoPermission).localizedDescription)
}

@MainActor
private func makeConnection(
    receiver: FakeReceiver = FakeReceiver(),
    host: FakeHost = FakeHost(),
    sharing: FakeSharing = FakeSharing(),
    pasteboard: FakePasteboard = FakePasteboard()
) -> ConnectionSettingsViewModel {
    ConnectionSettingsViewModel(
        receiver: receiver,
        host: host,
        sharing: sharing,
        pasteboard: pasteboard
    )
}

@MainActor
@Test("快捷指令名默认用已保存的名字，否则用“发送到”加电脑名，再否则用“发送到 Mac”")
func shortcutNameDefaults() {
    #expect(
        makeConnection(receiver: FakeReceiver(
            shortcutName: "我的 Mac"
        )).state.shortcutName == "我的 Mac"
    )
    #expect(
        makeConnection(host: FakeHost(computerName: " Studio ")).state.shortcutName
            == L10n.text("Send to %@", "Studio")
    )
    #expect(
        makeConnection(host: FakeHost(
            computerName: "  "
        )).state.shortcutName == L10n.text("Send to Mac")
    )
}

@MainActor
@Test("无效的快捷指令名不能发送，签名前会先规范化")
func shortcutNameIsValidatedBeforeSigning() {
    let viewModel = makeConnection()
    viewModel.setShortcutName("   ")
    #expect(viewModel.state.canSend == false)
    #expect(viewModel.state.nameMessage?.isError == true)
    viewModel.setShortcutName(" A/B ")
    #expect(viewModel.state.canSend)
    #expect(viewModel.state.nameMessage == SettingsMessage(
        text: L10n.text("shortcut.name.normalized", "A-B"),
        isError: false
    ))
}

@MainActor
@Test("快捷指令只在隔空投送成功后保存名字，并且总会清理临时文件")
func shortcutNameIsSavedOnlyAfterSuccessfulSend() async {
    let receiver = FakeReceiver()
    let sharing = FakeSharing()
    sharing.shareError = CocoaError(.userCancelled)
    let viewModel = makeConnection(receiver: receiver, sharing: sharing)
    viewModel.setShortcutName("First")
    viewModel.send()
    #expect(viewModel.state.isSending)
    _ = await settled(viewModel.$state.eraseToAnyPublisher()) { !$0.isSending }
    #expect(receiver.savedSenders.isEmpty)
    #expect(sharing.cleanedUp == [sharing.file])
    #expect(viewModel.state.message?.isError == true)

    sharing.shareError = nil
    viewModel.setShortcutName(" Second ")
    viewModel.send()
    let sent = await settled(viewModel.$state.eraseToAnyPublisher()) { !$0.isSending }
    #expect(receiver.savedSenders.map(\.shortcutName) == ["Second"])
    #expect(sharing.cleanedUp == [sharing.file, sharing.file])
    #expect(sent.message == SettingsMessage(
        text: L10n.text("shortcut.airdrop.sent"),
        isError: false
    ))
}

@MainActor
@Test("复制连接密钥时标记为隐藏内容，复制地址则不标记")
func copyingKeyIsConcealed() {
    let receiver = FakeReceiver()
    let pasteboard = FakePasteboard()
    let viewModel = makeConnection(receiver: receiver, pasteboard: pasteboard)
    viewModel.copyConnectionKey()
    viewModel.copyReceiveAddress()
    #expect(pasteboard.copies.map(\.text) == [
        receiver.configuration.receiver.token,
        "http://test.local:8765/upload",
    ])
    #expect(pasteboard.copies.map(\.concealed) == [true, false])
}

@MainActor
@Test("监听状态在侧边栏显示端口或失败，失败详情保留原始错误")
func listenerStatusMapping() {
    let receiver = FakeReceiver()
    let viewModel = SettingsViewModel(status: receiver.status, about: AboutInfo(bundle: .main))
    var statuses = [ListenerStatus]()
    let subscription = viewModel.$listenerStatus.sink { statuses.append($0) }
    receiver.statusSubject.send(.listening(port: 8766))
    receiver.statusSubject.send(.failed("port busy"))
    subscription.cancel()
    #expect(statuses.map(\.tone) == [.pending, .listening, .failed])
    #expect(statuses[1].summary == L10n.text("Listening · %@", "8766"))
    #expect(statuses[1].title.contains("8766"))
    #expect(statuses[2].summary == L10n.text("Receiver Failed"))
    #expect(statuses[2].detail == "port busy")
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
            ]) { a, _ in a },
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: app))
    }
    let versioned = try bundle(["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "42"])
    #expect(AboutInfo(bundle: versioned).version == L10n.text("Version %@ (%@)", "9.8.7", "42"))
    #expect(try AboutInfo(bundle: bundle([:])).version == nil)
}
