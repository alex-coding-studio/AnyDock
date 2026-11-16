import AppKit
import Combine

@MainActor
final class TrayPopoverController: NSObject, NSPopoverDelegate {
    let tray: TrayViewController

    private(set) lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = tray
        popover.contentSize = TrayMetrics.popoverSize
        followAppAppearance(popover)
        return popover
    }()

    private let statusItem: StatusItemController
    private let reloadSubject = PassthroughSubject<Void, Never>()
    private var appearance: NSKeyValueObservation?
    private var subscriptions = Set<AnyCancellable>()

    var reloadRequests: AnyPublisher<Void, Never> {
        reloadSubject.eraseToAnyPublisher()
    }

    init(tray: TrayViewController, statusItem: StatusItemController) {
        self.tray = tray
        self.statusItem = statusItem
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
            reloadSubject.send()
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
    }

    private func followAppAppearance(_ popover: NSPopover) {
        appearance = NSApp.observe(\.effectiveAppearance, options: [
            .initial,
        ]) { [weak popover] _, _ in
            MainActor.assumeIsolated { popover?.appearance = NSApp.effectiveAppearance }
        }
    }

    private func holdPresentation(_ held: Bool) {
        popover.behavior = held ? .applicationDefined : .transient
    }
}
