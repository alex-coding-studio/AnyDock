import AppKit
import Combine
@testable import AnyDock

@MainActor
func makeTestTray(inbox: TrayInbox = TrayInbox(
    list: { [] },
    recycle: { _ in }
)) -> TrayViewController {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
    let clipboard = ClipboardMonitor(
        pasteboard: pasteboard,
        isEnabled: Just(false).eraseToAnyPublisher()
    )
    return TrayViewController(viewModel: TrayViewModel(inbox: inbox), clipboard: clipboard)
}
