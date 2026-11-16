import AppKit
import Combine
@testable import AnyDock
@testable import AnyDockCore

@MainActor
final class TestInbox: TrayInbox {
    let receivedSubject = PassthroughSubject<ReceivedItem, Never>()
    let itemsSubject = PassthroughSubject<[ReceivedItem], Never>()

    private let listItems: @MainActor () -> [ReceivedItem]
    private let recycleItems: @MainActor ([URL]) -> Void

    var received: AnyPublisher<ReceivedItem, Never> {
        receivedSubject.eraseToAnyPublisher()
    }

    var items: AnyPublisher<[ReceivedItem], Never> {
        itemsSubject.eraseToAnyPublisher()
    }

    init(
        list: @escaping @MainActor () -> [ReceivedItem] = { [] },
        recycle: @escaping @MainActor ([URL]) -> Void = { _ in }
    ) {
        listItems = list
        recycleItems = recycle
    }

    func list() async throws -> [ReceivedItem] {
        listItems()
    }

    func recycle(_ urls: [URL]) async throws {
        recycleItems(urls)
    }

    func reload() async {}

    func openFolder() {}
}

@MainActor
func makeTestClipboard() -> ClipboardMonitor {
    ClipboardMonitor(
        pasteboard: NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)")),
        isEnabled: Just(false).eraseToAnyPublisher()
    )
}

@MainActor
func makeTestTray(inbox: any TrayInbox = TestInbox()) -> TrayViewController {
    TrayViewController(viewModel: TrayViewModel(inbox: inbox), clipboard: makeTestClipboard())
}
