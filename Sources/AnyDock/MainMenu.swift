import AppKit

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let application = addMenu("AnyDock", to: menu)
        let quit = application.addItem(
            withTitle: L10n.text("Quit AnyDock"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        let edit = addMenu("Edit", to: menu)
        let editingCommands: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, keyEquivalent) in editingCommands {
            edit.addItem(withTitle: L10n.text(title), action: action, keyEquivalent: keyEquivalent)
        }

        let window = addMenu("Window", to: menu)
        window.addItem(
            withTitle: L10n.text("Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        return menu
    }

    private static func addMenu(_ title: String, to menu: NSMenu) -> NSMenu {
        let title = L10n.text(title)
        let submenu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }
}
