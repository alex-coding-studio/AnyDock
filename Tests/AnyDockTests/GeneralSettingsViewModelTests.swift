import AnyDockCore
import AppKit
import Combine
import Testing
@testable import AnyDock

@MainActor
private func makeGeneral(
    preferences: FakePreferences = FakePreferences(),
    hotKeys: FakeHotKeys = FakeHotKeys(),
    restarter: FakeRestarter = FakeRestarter(),
    sharing: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
) -> GeneralSettingsViewModel {
    GeneralSettingsViewModel(
        preferences: preferences,
        loginItem: FakeLoginItem(),
        hotKeys: hotKeys,
        restarter: restarter,
        sharing: sharing
    )
}

@MainActor
@Test("语言与启动时不同才显示重启提示，改回后隐藏；分享进行中不能重启")
func languageChangeShowsRestartNotice() {
    let preferences = FakePreferences()
    preferences.language = .english
    let restarter = FakeRestarter()
    let sharing = CurrentValueSubject<Bool, Never>(true)
    let viewModel = makeGeneral(
        preferences: preferences,
        restarter: restarter,
        sharing: sharing.eraseToAnyPublisher()
    )
    #expect(viewModel.currentState.showsRestartNotice == false)
    viewModel.selectLanguage(.simplifiedChinese)
    #expect(preferences.language == .simplifiedChinese)
    #expect(viewModel.currentState.showsRestartNotice)
    viewModel.restart()
    #expect(restarter.restarts == 0)
    #expect(
        viewModel.currentState.restartMessage == L10n.text(
            "Finish sharing before restarting AnyDock."
        )
    )
    sharing.send(false)
    viewModel.restart()
    #expect(restarter.restarts == 1)
    viewModel.selectLanguage(.english)
    #expect(viewModel.currentState.showsRestartNotice == false)
}

@MainActor
@Test("无法注册的新快捷键不保存，原快捷键保持生效并提示已被占用")
func unavailableHotKeyKeepsPreviousOne() throws {
    let previous = try #require(KeyCombination(keyCode: 49, modifiers: [.control, .option]))
    let taken = try #require(KeyCombination(keyCode: 0, modifiers: [.command, .shift]))
    let preferences = FakePreferences()
    preferences.wakeHotKey = previous
    let hotKeys = FakeHotKeys()
    _ = hotKeys.register(previous)
    hotKeys.unavailable = [taken.keyCode]
    let viewModel = makeGeneral(preferences: preferences, hotKeys: hotKeys)
    #expect(viewModel.currentState.hotKeyMessage == nil)

    viewModel.beginHotKeyRecording()
    #expect(hotKeys.registered == nil)
    viewModel.record(taken)
    #expect(preferences.wakeHotKey == previous)
    #expect(hotKeys.registered == previous)
    #expect(viewModel.currentState.hotKey == previous)
    #expect(viewModel.currentState.hotKeyMessage == L10n.text(
        "hotkey.unavailable",
        taken.displayString
    ))
}

@MainActor
@Test("清除后状态里不再有快捷键（清除按钮据此隐藏），偏好和注册也一并清空")
func clearingHotKeyEmptiesState() throws {
    let saved = try #require(KeyCombination(keyCode: 49, modifiers: [.command]))
    let preferences = FakePreferences()
    preferences.wakeHotKey = saved
    let hotKeys = FakeHotKeys()
    _ = hotKeys.register(saved)
    let viewModel = makeGeneral(preferences: preferences, hotKeys: hotKeys)
    #expect(viewModel.currentState.hotKey == saved)
    viewModel.clearHotKey()
    #expect(viewModel.currentState.hotKey == nil)
    #expect(preferences.wakeHotKey == nil)
    #expect(hotKeys.registered == nil)
}

@MainActor
@Test("启动时保存的快捷键注册失败，首次打开设置就显示已被占用")
func savedHotKeyFailureShowsWhenSettingsOpen() throws {
    let saved = try #require(KeyCombination(keyCode: 49, modifiers: [.command]))
    let preferences = FakePreferences()
    preferences.wakeHotKey = saved
    let viewModel = makeGeneral(preferences: preferences)
    #expect(viewModel.currentState.hotKeyMessage == L10n.text(
        "hotkey.unavailable",
        saved.displayString
    ))
}
