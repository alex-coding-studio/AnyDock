import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let clickSubject = PassthroughSubject<Void, Never>()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var clicks: AnyPublisher<Void, Never> {
        clickSubject.eraseToAnyPublisher()
    }

    var button: NSStatusBarButton? {
        statusItem.button
    }

    override init() {
        super.init()
        statusItem.button?.setAccessibilityLabel(L10n.text("AnyDock"))
        statusItem.button?.toolTip = L10n.text("AnyDock")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
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
