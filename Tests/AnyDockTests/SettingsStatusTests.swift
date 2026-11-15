import AnyDockCore
import AppKit
import Testing

@testable import AnyDock

@MainActor
@Test("设置界面延迟构建后仍保留启动时写入的接收状态图标")
func receiverStatusSurvivesDeferredSettingsBuild() {
  let settings = SettingsController(
    configuration: ReceiverConfiguration(
      directory: FileManager.default.temporaryDirectory, token: "test-token"))
  settings.setStatus("failed", isError: true)
  settings.prepareInterface()
  #expect(settings.window?.contentViewController != nil)
  #expect(settings.statusIcon.image?.accessibilityDescription == L10n.text("Receiver Failed"))
}
