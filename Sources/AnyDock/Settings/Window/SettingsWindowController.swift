import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let frameAutosaveName = "AnyDockSettingsWindow"

    init(
        viewModel: SettingsViewModel,
        general: GeneralSettingsViewModel,
        connection: ConnectionSettingsViewModel,
        receiving: ReceivingSettingsViewModel
    ) {
        let sidebar = NSSplitViewItem(
            sidebarWithViewController: Self.hosting(SettingsSidebar(viewModel: viewModel))
        )
        sidebar.canCollapse = false
        sidebar.minimumThickness = SettingsMetrics.sidebarWidth
        sidebar.maximumThickness = SettingsMetrics.sidebarWidth
        let detail = NSSplitViewItem(viewController: Self.hosting(SettingsDetailView(
            viewModel: viewModel,
            general: general,
            connection: connection,
            receiving: receiving
        )))
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(detail)
        let window = SettingsWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.text("AnyDock Settings")
        window.contentMinSize = SettingsMetrics.windowMinimumSize
        window.setContentSize(SettingsMetrics.windowContentSize)
        window.center()
        window.setFrameAutosaveName(Self.frameAutosaveName)
        super.init(window: window)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    private static func hosting(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        return controller
    }
}

final class SettingsWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        guard Int(event.keyCode) == kVK_Escape,
              event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
        else {
            return super.keyDown(with: event)
        }
        if !event.isARepeat {
            cancelOperation(nil)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
