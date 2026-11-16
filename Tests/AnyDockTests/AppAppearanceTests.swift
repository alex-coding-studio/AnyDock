import AppKit
import Combine
import PockyFoundation
import Testing
@testable import AnyDock

@MainActor
@Test("切换外观后托盘 popover 立即跟随，跟随系统时与 App 的有效外观一致")
func popoverFollowsAppAppearance() {
    let app = NSApplication.shared
    let original = app.appearance
    defer { app.appearance = original }
    let trayPopover = TrayPopoverController(
        inbox: TestInbox(),
        clipboard: makeTestClipboard(),
        statusItem: StatusItemController(status: Just(.starting).eraseToAnyPublisher())
    )
    let popover = trayPopover.popover
    app.appearance = PKYAppearance.Mode.dark.nsAppearance
    #expect(popover.appearance?.name == .darkAqua)
    app.appearance = PKYAppearance.Mode.light.nsAppearance
    #expect(popover.appearance?.name == .aqua)
    app.appearance = PKYAppearance.Mode.system.nsAppearance
    #expect(popover.appearance?.name == app.effectiveAppearance.name)
}

@MainActor
@Test("外观偏好复用原有键名、默认值和异常值回退")
func appearancePreferenceUsesOriginalKeyAndFallback() throws {
    let suiteName = "com.cuxiao.mac.anydock.tests.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suiteName))
    defer { store.removePersistentDomain(forName: suiteName) }

    #expect(Preferences.appearance.key == Preferences.Key.appearance.rawValue)
    #expect(Preferences.appearance.defaultMode == .system)

    let appearance = PKYAppearance(store: store, key: Preferences.Key.appearance.rawValue)
    #expect(appearance.storedMode() == .system)

    appearance.save(.dark)
    #expect(store.string(forKey: Preferences.Key.appearance.rawValue) == "dark")
    #expect(appearance.storedMode() == .dark)

    appearance.save(.light)
    #expect(store.string(forKey: Preferences.Key.appearance.rawValue) == "light")
    #expect(appearance.storedMode() == .light)

    store.set("unexpected", forKey: Preferences.Key.appearance.rawValue)
    #expect(appearance.storedMode() == .system)
}
