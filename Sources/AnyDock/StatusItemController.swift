import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let clickSubject = PassthroughSubject<Void, Never>()
    private let status: AnyPublisher<InboxStatus, Never>
    private var subscriptions = Set<AnyCancellable>()

    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel(L10n.text("AnyDock"))
        item.button?.toolTip = L10n.text("AnyDock")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        return item
    }()

    var clicks: AnyPublisher<Void, Never> {
        clickSubject.eraseToAnyPublisher()
    }

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(status: AnyPublisher<InboxStatus, Never>) {
        self.status = status
        super.init()
        subscribeEvents()
    }

    private func subscribeEvents() {
        status
            .sink { [weak self] in self?.show($0) }
            .store(in: &subscriptions)
    }

    private func show(_ status: InboxStatus) {
        if case .failed = status {
            showFailure(true)
        } else {
            showFailure(false)
        }
    }

    private func showFailure(_ failed: Bool) {
        statusItem.button?.image =
            failed
                ? NSImage(
                    systemSymbolName: "exclamationmark.triangle",
                    accessibilityDescription: L10n.text("AnyDock receiver failed. Open Settings.")
                )
                : BrandIcon.menuBar()
        statusItem.button?.image?.isTemplate = true
    }

    @objc private func clicked() {
        clickSubject.send()
    }
}
