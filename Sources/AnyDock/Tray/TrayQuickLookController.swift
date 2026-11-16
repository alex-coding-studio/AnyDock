import AppKit
import Combine
import Quartz

@MainActor
final class TrayQuickLookController: NSObject, @MainActor QLPreviewPanelDataSource,
    @MainActor QLPreviewPanelDelegate {
    private static let previousKeyCodes: Set<UInt16> = [123, 126]
    private static let nextKeyCodes: Set<UInt16> = [124, 125]

    private(set) var isShowing = false

    private let holdSubject = PassthroughSubject<Bool, Never>()
    private weak var owner: NSResponder?
    private weak var focusTarget: NSView?
    private var urls = [URL]()

    var holds: AnyPublisher<Bool, Never> {
        holdSubject.eraseToAnyPublisher()
    }

    init(owner: NSResponder, focusTarget: NSView) {
        self.owner = owner
        self.focusTarget = focusTarget
    }

    func toggle(_ selection: [URL]) {
        if isShowing {
            close()
            return
        }
        guard !selection.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }
        urls = selection
        isShowing = true
        holdSubject.send(true)
        focus()
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    func endControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        finish()
    }

    func close() {
        guard isShowing else {
            return
        }
        if let panel = ownedPanel() {
            panel.close()
        }
        finish()
    }

    func numberOfPreviewItems(in _: QLPreviewPanel?) -> Int {
        urls.count
    }

    func previewPanel(_: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
        urls[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel?, handle event: NSEvent?) -> Bool {
        guard let panel, let event, event.type == .keyDown else {
            return false
        }
        if event.charactersIgnoringModifiers == " " {
            close()
            return true
        }
        guard !urls.isEmpty else {
            return false
        }
        let step: Int
        if Self.previousKeyCodes.contains(event.keyCode) {
            step = -1
        } else if Self.nextKeyCodes.contains(event.keyCode) {
            step = 1
        } else {
            return false
        }
        panel.currentPreviewItemIndex = max(
            0,
            min(urls.count - 1, panel.currentPreviewItemIndex + step)
        )
        return true
    }

    func windowWillClose(_: Notification) {
        finish()
    }

    private func finish() {
        guard isShowing else {
            return
        }
        if let panel = ownedPanel() {
            panel.dataSource = nil
            panel.delegate = nil
        }
        urls = []
        isShowing = false
        if NSApp.isActive, NSApp.keyWindow is QLPreviewPanel {
            focusTarget?.window?.makeKey()
        }
        focus()
        holdSubject.send(false)
    }

    private func focus() {
        focusTarget?.window?.makeFirstResponder(focusTarget)
    }

    private func ownedPanel() -> QLPreviewPanel? {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.currentController as AnyObject? === owner
        else {
            return nil
        }
        return panel
    }
}
