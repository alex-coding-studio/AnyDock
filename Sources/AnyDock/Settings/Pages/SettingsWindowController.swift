import AppKit
import Combine

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel
    private let pages = NSTabViewController()
    private var subscriptions = Set<AnyCancellable>()

    init(viewModel: SettingsViewModel, pages controllers: [NSViewController]) {
        self.viewModel = viewModel
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(
            sidebarWithViewController: SettingsSidebarViewController(viewModel: viewModel)
        )
        sidebar.canCollapse = false
        sidebar.minimumThickness = SettingsMetrics.sidebarWidth
        sidebar.maximumThickness = SettingsMetrics.sidebarWidth
        pages.tabStyle = .unspecified
        pages.transitionOptions = []
        pages.canPropagateSelectedChildViewControllerTitle = false
        for controller in controllers {
            pages.addTabViewItem(NSTabViewItem(viewController: controller))
        }
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: pages))
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.text("AnyDock Settings")
        window.setContentSize(SettingsMetrics.windowContentSize)
        window.center()
        super.init(window: window)
        viewModel.section
            .sink { [weak self] in self?.pages.selectedTabViewItemIndex = $0.rawValue }
            .store(in: &subscriptions)
    }

    required init?(coder _: NSCoder) {
        nil
    }
}
