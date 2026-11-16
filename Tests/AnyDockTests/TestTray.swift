import AppKit
import Combine
@testable import AnyDock

@MainActor
func makeTestTray() -> TrayViewController {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
    let clipboard = ClipboardMonitor(
        pasteboard: pasteboard,
        isEnabled: Just(false).eraseToAnyPublisher()
    )
    return TrayViewController(clipboard: clipboard)
}
