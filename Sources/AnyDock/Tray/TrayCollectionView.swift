import AppKit
import Combine

@MainActor
final class TrayCollectionView: NSCollectionView {
    enum Command {
        case copy
        case reveal
        case preview
        case trash
        case collapseClipboard
        case selectionChanged
    }

    private static let deleteKeyCode: UInt16 = 51
    private static let escapeKeyCode: UInt16 = 53
    private static let backspaceKeyEquivalent = "\u{8}"
    private static let previewClickCount = 2

    var consumesEscape = false
    private(set) var dragStartedOnCard = false

    private let commandSubject = PassthroughSubject<Command, Never>()

    var commands: AnyPublisher<Command, Never> {
        commandSubject.eraseToAnyPublisher()
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
        commandSubject.send(.selectionChanged)
        let menu = NSMenu()
        let count = selectionIndexPaths.count
        let copy = NSMenuItem(
            title: count > 1 ? L10n.text("copy_count", count) : L10n.text("Copy"),
            action: #selector(copy(_:)),
            keyEquivalent: "c"
        )
        copy.target = self
        menu.addItem(copy)
        let reveal = NSMenuItem(
            title: L10n.text("Show in Finder"),
            action: #selector(reveal),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())
        let trash = NSMenuItem(
            title: count > 1 ? L10n.text("trash_count", count) : L10n.text("Move to Trash"),
            action: #selector(trash),
            keyEquivalent: Self.backspaceKeyEquivalent
        )
        trash.target = self
        menu.addItem(trash)
        return menu
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
        if event.charactersIgnoringModifiers == "c", event.modifierFlags.contains(.command) {
            commandSubject.send(.copy)
        } else if event.modifierFlags.contains(.command), event.keyCode == Self.deleteKeyCode {
            commandSubject.send(.trash)
        } else if event.charactersIgnoringModifiers == " " {
            commandSubject.send(.preview)
        } else if event.keyCode == Self.escapeKeyCode, consumesEscape {
            commandSubject.send(.collapseClipboard)
        } else if event.keyCode == Self.escapeKeyCode, !selectionIndexPaths.isEmpty {
            deselectAll(nil)
            commandSubject.send(.selectionChanged)
        } else {
            super.keyDown(with: event)
        }
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
}
