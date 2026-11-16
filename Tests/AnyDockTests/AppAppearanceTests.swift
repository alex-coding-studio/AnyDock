import AppKit
import Testing
@testable import AnyDock

@MainActor
@Test("切换外观后托盘 popover 立即跟随，跟随系统时与 App 的有效外观一致")
func popoverFollowsAppAppearance() {
    let app = NSApplication.shared
    let original = app.appearance
    defer { app.appearance = original }
    let trayPopover = TrayPopoverController(
        tray: makeTestTray(),
        statusItem: StatusItemController()
    )
    let popover = trayPopover.popover
    AppAppearance.dark.apply()
    #expect(popover.appearance?.name == .darkAqua)
    AppAppearance.light.apply()
    #expect(popover.appearance?.name == .aqua)
    AppAppearance.system.apply()
    #expect(popover.appearance?.name == app.effectiveAppearance.name)
}
