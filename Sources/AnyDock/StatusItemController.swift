import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let clickSubject = PassthroughSubject<Void, Never>()

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

    override init() {
        super.init()
        showFailure(false)
    }

    func showFailure(_ failed: Bool) {
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
