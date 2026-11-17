import AnyDockCore
import Combine
import Foundation

@MainActor
protocol TrayInbox: AnyObject {
    var received: AnyPublisher<ReceivedItem, Never> { get }
    var items: AnyPublisher<[ReceivedItem], Never> { get }
    func list() async throws -> [ReceivedItem]
    func recycle(_ urls: [URL]) async throws
    func reload() async
    func openFolder()
}

struct TrayList {
    var contents = TrayContents()
    var latestURL: URL?
}

@MainActor
final class TrayViewModel {
    private let inbox: any TrayInbox
    private let listSubject = CurrentValueSubject<TrayList, Never>(TrayList())
    private let selectionSubject = CurrentValueSubject<[URL], Never>([])
    private let draggedSubject = CurrentValueSubject<[URL], Never>([])
    private let recyclingSubject = CurrentValueSubject<Bool, Never>(false)
    private let recycleStartSubject = PassthroughSubject<Void, Never>()
    private let dragFinishedSubject = PassthroughSubject<Void, Never>()
    private let errorSubject = PassthroughSubject<any Error, Never>()
    private let thumbnailSubject = PassthroughSubject<(url: URL, data: Data), Never>()
    private let arrivalSubject = PassthroughSubject<ReceivedItem, Never>()
    private var droppedOnTrash = false
    private var subscriptions = Set<AnyCancellable>()

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

    var incomingThumbnails: AnyPublisher<(url: URL, data: Data), Never> {
        thumbnailSubject.eraseToAnyPublisher()
    }

    var arrivals: AnyPublisher<ReceivedItem, Never> {
        arrivalSubject.eraseToAnyPublisher()
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

    var isSingleColumn: Bool {
        contents.filter == .kind(.text)
    }

    init(inbox: any TrayInbox) {
        self.inbox = inbox
        subscribeEvents()
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

    func receive(_ arrival: ReceivedItem) {
        var item = arrival
        if let thumbnail = item.thumbnail {
            item.thumbnail = nil
            thumbnailSubject.send((item.url, thumbnail))
        }
        var next = listSubject.value
        next.latestURL = item.url
        next.contents.receive(item)
        publish(next)
        arrivalSubject.send(item)
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

    private func subscribeEvents() {
        inbox.received
            .sink { [weak self] in self?.receive($0) }
            .store(in: &subscriptions)
        inbox.items
            .sink { [weak self] in self?.replace($0) }
            .store(in: &subscriptions)
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
