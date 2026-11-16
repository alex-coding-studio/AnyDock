import AppKit
import Combine
@testable import AnyDock

@MainActor
func makeTestTray() -> ImageTrayController {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
    let clipboard = ClipboardMonitor(
        pasteboard: pasteboard,
        isEnabled: Just(false).eraseToAnyPublisher()
    )
    return ImageTrayController(clipboard: clipboard)
}
