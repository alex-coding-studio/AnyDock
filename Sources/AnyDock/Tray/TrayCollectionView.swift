import AppKit
import Combine

@MainActor
final class TrayCollectionView: NSCollectionView {
    private static let previewClickCount = 2

    var consumesEscape = false
    private(set) var dragStartedOnCard = false

    private let commandSubject = PassthroughSubject<TrayCommand, Never>()
    private let selectionChangeSubject = PassthroughSubject<Void, Never>()

    var commands: AnyPublisher<TrayCommand, Never> {
        commandSubject.eraseToAnyPublisher()
    }

    var selectionChanges: AnyPublisher<Void, Never> {
        selectionChangeSubject.eraseToAnyPublisher()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            collectionViewLayout?.invalidateLayout()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let path = indexPathForItem(at: point) else {
            return nil
        }
        if !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
        }
        selectionChangeSubject.send()
        return contextMenu()
    }

    override func mouseDown(with event: NSEvent) {
        let clickedCard = indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil
        dragStartedOnCard = clickedCard
        super.mouseDown(with: event)
        if event.clickCount == Self.previewClickCount, clickedCard {
            commandSubject.send(.preview)
        }
    }

    override func keyDown(with event: NSEvent) {
        if TrayKeyboardShortcuts.copy.matches(event) {
            commandSubject.send(.copy)
        } else if TrayKeyboardShortcuts.trash.matches(event) {
            commandSubject.send(.trash)
        } else if TrayKeyboardShortcuts.preview.matches(event) {
            commandSubject.send(.preview)
        } else if TrayKeyboardShortcuts.escape.matches(event), consumesEscape {
            commandSubject.send(.collapseClipboard)
        } else if TrayKeyboardShortcuts.escape.matches(event), !selectionIndexPaths.isEmpty {
            deselectAll(nil)
            selectionChangeSubject.send()
        } else {
            super.keyDown(with: event)
        }
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let count = selectionIndexPaths.count
        menu.addItem(menuItem(
            count > 1 ? L10n.text("copy_count", count) : L10n.text("Copy"),
            action: #selector(copy(_:)),
            shortcut: TrayKeyboardShortcuts.copy
        ))
        menu.addItem(menuItem(L10n.text("Show in Finder"), action: #selector(reveal)))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            count > 1 ? L10n.text("trash_count", count) : L10n.text("Move to Trash"),
            action: #selector(trash),
            shortcut: TrayKeyboardShortcuts.trash
        ))
        return menu
    }

    @objc func copy(_: Any?) {
        commandSubject.send(.copy)
    }

    @objc private func reveal() {
        commandSubject.send(.reveal)
    }

    @objc private func trash() {
        commandSubject.send(.trash)
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        shortcut: TrayShortcut? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: shortcut?.keyEquivalent ?? ""
        )
        if let shortcut {
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
        item.target = self
        return item
    }
}
