import AppKit

@MainActor
final class TrayCollectionView: NSCollectionView {
    var copyItems: (() -> Void)?
    var revealItems: (() -> Void)?
    var previewItems: (() -> Void)?
    var trashItems: (() -> Void)?
    var selectionChanged: (() -> Void)?
    var escapePressed: (() -> Bool)?
    private(set) var dragStartedOnCard = false

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
        selectionChanged?()
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
            keyEquivalent: "\u{8}"
        )
        trash.target = self
        menu.addItem(trash)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        let clickedCard = indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil
        dragStartedOnCard = clickedCard
        super.mouseDown(with: event)
        if event.clickCount == 2, clickedCard {
            previewItems?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "c", event.modifierFlags.contains(.command) {
            copyItems?()
        } else if event.modifierFlags.contains(.command), event.keyCode == 51 {
            trashItems?()
        } else if event.charactersIgnoringModifiers == " " {
            previewItems?()
        } else if event.keyCode == 53, escapePressed?() == true {
            return
        } else if event.keyCode == 53, !selectionIndexPaths.isEmpty {
            deselectAll(nil)
            selectionChanged?()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_: Any?) {
        copyItems?()
    }

    @objc private func reveal() {
        revealItems?()
    }

    @objc private func trash() {
        trashItems?()
    }
}
