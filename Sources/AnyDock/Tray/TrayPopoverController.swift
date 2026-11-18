import AnyDockCore
import AppKit
import Combine

@MainActor
final class TrayPopoverController: NSObject, NSPopoverDelegate {
    private(set) lazy var tray = TrayViewController(viewModel: viewModel, clipboard: clipboard)

    private(set) lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = tray
        popover.contentSize = TrayMetrics.popoverSize
        followAppAppearance(popover)
        return popover
    }()

    private let inbox: any TrayInbox
    private let clipboard: ClipboardMonitor
    private let statusItem: StatusItemController
    private let updates: (any UpdateChecking)?
    private var appearance: NSKeyValueObservation?
    private var subscriptions = Set<AnyCancellable>()

    private lazy var viewModel = TrayViewModel(inbox: inbox, updates: updates)

    var settingsRequests: AnyPublisher<Void, Never> {
        tray.settingsRequests
    }

    init(
        inbox: any TrayInbox,
        clipboard: ClipboardMonitor,
        statusItem: StatusItemController,
        updates: (any UpdateChecking)? = nil
    ) {
        self.inbox = inbox
        self.clipboard = clipboard
        self.statusItem = statusItem
        self.updates = updates
        super.init()
        subscribeEvents()
    }

    func toggle() {
        if tray.holdsPresentation {
            tray.closePreview()
        } else if popover.isShown {
            close()
        } else {
            show()
        }
    }

    func show(reloading: Bool = true) {
        guard !popover.isShown, let button = statusItem.button else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        tray.focusCollection()
        if reloading {
            Task { await inbox.reload() }
        }
    }

    func close() {
        tray.closePreview()
        popover.performClose(nil)
    }

    func popoverShouldClose(_: NSPopover) -> Bool {
        !tray.holdsPresentation
    }

    func popoverDidClose(_: Notification) {
        tray.trayDidClose()
    }

    private func subscribeEvents() {
        statusItem.clicks
            .sink { [weak self] in self?.toggle() }
            .store(in: &subscriptions)
        tray.presentationHolds
            .sink { [weak self] in self?.holdPresentation($0) }
            .store(in: &subscriptions)
        tray.dragFinishes
            .sink { [weak self] in self?.popover.performClose(nil) }
            .store(in: &subscriptions)
        tray.folderRequests
            .sink { [weak self] in self?.inbox.openFolder() }
            .store(in: &subscriptions)
        viewModel.arrivals
            .sink { [weak self] in self?.showArrival($0) }
            .store(in: &subscriptions)
    }

    private func followAppAppearance(_ popover: NSPopover) {
        appearance = NSApp.observe(\.effectiveAppearance, options: [
            .initial,
        ]) { [weak popover] _, _ in
            MainActor.assumeIsolated { popover?.appearance = NSApp.effectiveAppearance }
        }
    }

    private func showArrival(_ item: ReceivedItem) {
        if Preferences.copiesNewItems {
            tray.copyToPasteboard(item)
        }
        show(reloading: false)
        tray.scrollToLatest()
    }

    private func holdPresentation(_ held: Bool) {
        popover.behavior = held ? .applicationDefined : .transient
    }
}
