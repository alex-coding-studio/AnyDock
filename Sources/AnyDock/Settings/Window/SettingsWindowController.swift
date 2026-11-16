import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(rootView: SettingsRootView) {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.title = L10n.text("AnyDock Settings")
        window.setContentSize(SettingsMetrics.windowContentSize)
        window.center()
        super.init(window: window)
    }

    required init?(coder _: NSCoder) {
        nil
    }
}
