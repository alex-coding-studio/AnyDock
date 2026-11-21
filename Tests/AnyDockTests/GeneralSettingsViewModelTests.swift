import AnyDockCore
import AppKit
import Combine
import Testing
@testable import AnyDock

@MainActor
private func makeGeneral(
    preferences: FakePreferences = FakePreferences(),
    notifications: FakeNotificationPermissions = FakeNotificationPermissions(),
    hotKeys: FakeHotKeys = FakeHotKeys(),
    restarter: FakeRestarter = FakeRestarter(),
    sharing: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
) -> GeneralSettingsViewModel {
    GeneralSettingsViewModel(
        preferences: preferences,
        loginItem: FakeLoginItem(),
        notifications: notifications,
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
    #expect(viewModel.state.showsRestartNotice == false)
    viewModel.selectLanguage(.simplifiedChinese)
    #expect(preferences.language == .simplifiedChinese)
    #expect(viewModel.state.showsRestartNotice)
    viewModel.restart()
    #expect(restarter.restarts == 0)
    #expect(
        viewModel.state.restartMessage == L10n.text(
            "Finish sharing before restarting AnyDock."
        )
    )
    sharing.send(false)
    viewModel.restart()
    #expect(restarter.restarts == 1)
    viewModel.selectLanguage(.english)
    #expect(viewModel.state.showsRestartNotice == false)
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
    #expect(viewModel.state.hotKeyMessage == nil)

    viewModel.beginHotKeyRecording()
    #expect(hotKeys.registered == nil)
    viewModel.record(taken)
    #expect(preferences.wakeHotKey == previous)
    #expect(hotKeys.registered == previous)
    #expect(viewModel.state.hotKey == previous)
    #expect(viewModel.state.hotKeyMessage == L10n.text(
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
    #expect(viewModel.state.hotKey == saved)
    viewModel.clearHotKey()
    #expect(viewModel.state.hotKey == nil)
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
    #expect(viewModel.state.hotKeyMessage == L10n.text(
        "hotkey.unavailable",
        saved.displayString
    ))
}

@MainActor
@Test("系统拒绝时保留原收件方式，允许后可启用，关闭时不再申请权限")
func receiveNotificationsRespectAuthorization() async {
    let preferences = FakePreferences()
    let permissions = FakeNotificationPermissions()
    let model = makeGeneral(preferences: preferences, notifications: permissions)
    await model.setReceiveNotifications(true)
    #expect(!preferences.receiveNotifications)
    #expect(model.state.notificationsDenied)

    model.setOpensTrayOnArrival(false)
    permissions.denied = false
    await model.refreshNotificationPermission()
    #expect(!model.state.notificationsDenied)
    await model.setReceiveNotifications(true)
    #expect(preferences.receiveNotifications)
    #expect(!preferences.opensTrayOnArrival)
    model.setOpensTrayOnArrival(true)
    #expect(preferences.receiveNotifications)

    permissions.denied = true
    await model.refreshNotificationPermission()
    #expect(model.state.notificationsDenied)
    await model.setReceiveNotifications(false)
    #expect(!preferences.receiveNotifications)
    #expect(permissions.requests == 2)
}

@MainActor
@Test("首次启动仅请求一次通知权限：允许时自动开启通知，拒绝、未打包或已有设置不误改")
func initialNotificationAuthorizationRunsOnceAndSyncsSettings() async {
    let unbundledPermissions = FakeNotificationPermissions()
    unbundledPermissions.denied = false
    unbundledPermissions.canRequestAuthorization = false
    let unbundledPreferences = FakePreferences()
    let didRequestUnbundled = await ReceiveNotifications.requestInitialAuthorizationIfNeeded(
        using: unbundledPermissions,
        preferences: unbundledPreferences
    )
    #expect(!didRequestUnbundled)
    #expect(unbundledPermissions.requests == 0)
    #expect(!unbundledPreferences.hasRequestedNotificationPermission)
    #expect(!unbundledPreferences.receiveNotifications)

    let grantedPermissions = FakeNotificationPermissions()
    grantedPermissions.denied = false
    let grantedPreferences = FakePreferences()
    let viewModel = makeGeneral(preferences: grantedPreferences, notifications: grantedPermissions)
    let didRequestGranted = await ReceiveNotifications.requestInitialAuthorizationIfNeeded(
        using: grantedPermissions,
        preferences: grantedPreferences
    )
    #expect(didRequestGranted)
    #expect(grantedPermissions.requests == 1)
    #expect(grantedPreferences.hasRequestedNotificationPermission)
    #expect(grantedPreferences.receiveNotifications)

    grantedPermissions.authorizationChangeSubject.send()
    for _ in 0 ..< 20 where !viewModel.state.receiveNotifications || viewModel.state.notificationsDenied {
        await Task.yield()
    }
    #expect(viewModel.state.receiveNotifications)
    #expect(!viewModel.state.notificationsDenied)

    let didRequestSecondLaunch = await ReceiveNotifications.requestInitialAuthorizationIfNeeded(
        using: grantedPermissions,
        preferences: grantedPreferences
    )
    #expect(!didRequestSecondLaunch)
    #expect(grantedPermissions.requests == 1)

    let deniedPermissions = FakeNotificationPermissions()
    deniedPermissions.denied = true
    let deniedPreferences = FakePreferences()
    let didRequestDenied = await ReceiveNotifications.requestInitialAuthorizationIfNeeded(
        using: deniedPermissions,
        preferences: deniedPreferences
    )
    #expect(didRequestDenied)
    #expect(deniedPermissions.requests == 1)
    #expect(deniedPreferences.hasRequestedNotificationPermission)
    #expect(!deniedPreferences.receiveNotifications)

    let existingPermissions = FakeNotificationPermissions()
    existingPermissions.denied = false
    let existingPreferences = FakePreferences()
    existingPreferences.receiveNotifications = false
    let didRequestExisting = await ReceiveNotifications.requestInitialAuthorizationIfNeeded(
        using: existingPermissions,
        preferences: existingPreferences
    )
    #expect(!didRequestExisting)
    #expect(existingPermissions.requests == 0)
    #expect(!existingPreferences.hasRequestedNotificationPermission)
    #expect(!existingPreferences.receiveNotifications)
}
