import AnyDockCore
import Combine
import Foundation

struct TrayInbox {
    let list: @MainActor () async throws -> [ReceivedItem]
    let recycle: @MainActor ([URL]) async throws -> Void
}

struct TrayList {
    var contents = TrayContents()
    var latestURL: URL?
}

@MainActor
final class TrayViewModel {
    private let inbox: TrayInbox
    private let listSubject = CurrentValueSubject<TrayList, Never>(TrayList())
    private let selectionSubject = CurrentValueSubject<[URL], Never>([])
    private let draggedSubject = CurrentValueSubject<[URL], Never>([])
    private let recyclingSubject = CurrentValueSubject<Bool, Never>(false)
    private let recycleStartSubject = PassthroughSubject<Void, Never>()
    private let dragFinishedSubject = PassthroughSubject<Void, Never>()
    private let errorSubject = PassthroughSubject<any Error, Never>()
    private var droppedOnTrash = false

    var list: AnyPublisher<TrayList, Never> {
        listSubject.eraseToAnyPublisher()
    }

    var selection: AnyPublisher<[URL], Never> {
        selectionSubject.eraseToAnyPublisher()
    }

    var dragged: AnyPublisher<[URL], Never> {
        draggedSubject.eraseToAnyPublisher()
    }

    var recycling: AnyPublisher<Bool, Never> {
        recyclingSubject.eraseToAnyPublisher()
    }

    var recycleStarts: AnyPublisher<Void, Never> {
        recycleStartSubject.eraseToAnyPublisher()
    }

    var dragFinishes: AnyPublisher<Void, Never> {
        dragFinishedSubject.eraseToAnyPublisher()
    }

    var errors: AnyPublisher<any Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    var contents: TrayContents {
        listSubject.value.contents
    }

    var latestURL: URL? {
        listSubject.value.latestURL
    }

    var selectedURLs: [URL] {
        selectionSubject.value
    }

    var draggedURLs: [URL] {
        draggedSubject.value
    }

    var isRecycling: Bool {
        recyclingSubject.value
    }

    var isEmpty: Bool {
        contents.items.isEmpty
    }

    init(inbox: TrayInbox) {
        self.inbox = inbox
    }

    func count(of filter: TrayFilter) -> Int {
        guard case let .kind(kind) = filter else {
            return contents.items.count
        }
        return contents.count(of: kind)
    }

    func replace(_ items: [ReceivedItem]) {
        var next = listSubject.value
        next.contents.replace(items)
        publish(next)
    }

    func receive(_ item: ReceivedItem) {
        var next = listSubject.value
        next.latestURL = item.url
        next.contents.receive(item)
        publish(next)
    }

    func select(_ filter: TrayFilter) {
        var next = listSubject.value
        next.contents.select(filter)
        publish(next)
    }

    func toggleSelectAll(in filter: TrayFilter) {
        if contents.filter != filter {
            select(filter)
        }
        let visible = contents.visibleItems.map(\.url)
        select(urls: Set(selectedURLs) == Set(visible) ? [] : visible)
    }

    func select(urls: [URL]) {
        selectionSubject.send(urls)
    }

    func clearSelection() {
        select(urls: [])
    }

    func beginDrag(_ urls: [URL]) {
        droppedOnTrash = false
        draggedSubject.send(urls)
    }

    func endDrag(succeeded: Bool) {
        let trashed = droppedOnTrash
        droppedOnTrash = false
        draggedSubject.send([])
        if !trashed, succeeded {
            dragFinishedSubject.send()
        }
    }

    func canDropOnTrash() -> Bool {
        !draggedURLs.isEmpty && !isRecycling
    }

    @discardableResult
    func trashDraggedItems() -> Task<Void, Never>? {
        guard canDropOnTrash() else {
            return nil
        }
        let targets = draggedURLs
        droppedOnTrash = true
        draggedSubject.send([])
        clearSelection()
        return recycle(targets)
    }

    @discardableResult
    func recycleSelection() -> Task<Void, Never>? {
        recycle(selectedURLs)
    }

    @discardableResult
    func recycle(_ targets: [URL]) -> Task<Void, Never>? {
        guard !isRecycling, !targets.isEmpty else {
            return nil
        }
        recyclingSubject.send(true)
        return Task { [weak self] in
            await self?.performRecycle(targets)
            self?.recyclingSubject.send(false)
        }
    }

    private func performRecycle(_ targets: [URL]) async {
        do {
            let allowed = try await Set(inbox.list().map(\.url))
            let urls = targets.filter { allowed.contains($0) }
            guard !urls.isEmpty else {
                return
            }
            recycleStartSubject.send()
            try await inbox.recycle(urls)
        } catch {
            errorSubject.send(error)
        }
    }

    private func publish(_ next: TrayList) {
        listSubject.send(next)
        let visible = Set(next.contents.visibleItems.map(\.url))
        select(urls: selectedURLs.filter { visible.contains($0) })
    }
}
