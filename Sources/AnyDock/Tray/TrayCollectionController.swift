import AnyDockCore
import AppKit
import Combine

@MainActor
final class TrayCollectionController: NSObject, NSCollectionViewDataSource,
    NSCollectionViewDelegate {
    private static let squareRatio: CGFloat = 1

    private(set) lazy var collection: TrayCollectionView = {
        let collection = TrayCollectionView()
        collection.collectionViewLayout = layout
        collection.autoresizingMask = [.width]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        for kind in ReceivedKind.allCases {
            collection.register(kind.cardItemClass, forItemWithIdentifier: kind.cardIdentifier)
        }
        collection.dataSource = self
        collection.delegate = self
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .delete], forLocal: true)
        return collection
    }()

    private(set) lazy var scroll: NSScrollView = {
        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private lazy var layout = MasonryCollectionLayout { [weak self] path in
        self?.aspectRatio(at: path.item) ?? Self.squareRatio
    }

    private let viewModel: TrayViewModel
    private let cache: TrayEntryCache
    private let previews = TrayPreviewCache()
    private let sizing = TrayCardSizing()
    private var entries = [TrayEntry]()
    private var renderedLatestURL: URL?
    private var isApplyingSelection = false
    private var subscriptions = Set<AnyCancellable>()

    var commands: AnyPublisher<TrayCollectionView.Command, Never> {
        collection.commands
    }

    var selectedEntries: [TrayEntry] {
        let selected = Set(viewModel.selectedURLs)
        return entries.filter { selected.contains($0.url) }
    }

    init(viewModel: TrayViewModel, cache: TrayEntryCache) {
        self.viewModel = viewModel
        self.cache = cache
        super.init()
        subscribeEvents()
    }

    func setBottomInset(_ inset: CGFloat) {
        layout.extraBottomInset = inset
    }

    func scrollToLatest() {
        guard !entries.isEmpty else {
            return
        }
        collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
    }

    func beginDrag(_ indexPaths: Set<IndexPath>) {
        viewModel.beginDrag(urls(at: indexPaths))
    }

    func endDrag(operation: NSDragOperation) {
        viewModel.endDrag(succeeded: !operation.isEmpty)
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let entry = entries[indexPath.item]
        let item = collectionView.makeItem(
            withIdentifier: entry.kind.cardIdentifier,
            for: indexPath
        )
        let latest = entry.url == viewModel.latestURL
        (item as? TrayCardItem)?.configure(
            entry,
            singleColumn: viewModel.isSingleColumn,
            time: TrayTimeFormat.short(entry.item.receivedAt),
            latest: latest
        )
        if entry.kind == .image || (entry.kind == .file && !entry.item.isPlainText) {
            if let image = previews.image(for: entry.url) {
                (item as? TrayCardItem)?.showThumbnail(image)
            } else {
                previews.load(entry)
            }
        }
        let timestamp = entry.item.receivedAt.formatted(date: .complete, time: .standard)
        item.view.toolTip = timestamp
        item.view.setAccessibilityElement(true)
        item.view.setAccessibilityRole(entry.kind == .image ? .image : .group)
        item.view.setAccessibilityLabel(
            L10n.text(
                latest ? "New %@: %@, %@" : "%@: %@, %@",
                entry.kind.displayName,
                entry.summary,
                timestamp
            )
        )
        return item
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        syncSelection()
    }

    func collectionView(_: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        syncSelection()
    }

    func collectionView(
        _: NSCollectionView,
        canDragItemsAt indexPaths: Set<IndexPath>,
        with _: NSEvent
    ) -> Bool {
        collection.dragStartedOnCard && !indexPaths.isEmpty
    }

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        TrayPasteboardWriter.dragWriter(for: entries[indexPath.item])
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt _: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        session.draggingFormation = .pile
        beginDrag(indexPaths)
        DispatchQueue.main.async { [weak self] in
            for indexPath in indexPaths {
                self?.collection.item(at: indexPath)?.view.isHidden = false
            }
        }
    }

    func collectionView(
        _: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        endDrag(operation: operation)
    }

    private func subscribeEvents() {
        previews.loaded
            .sink { [weak self] in self?.showPreview(for: $0) }
            .store(in: &subscriptions)
        collection.publisher(for: \.selectionIndexPaths)
            .sink { [weak self] _ in self?.syncSelection() }
            .store(in: &subscriptions)
        collection.commands
            .filter { $0 == .selectionChanged }
            .sink { [weak self] _ in self?.syncSelection() }
            .store(in: &subscriptions)
        viewModel.list
            .sink { [weak self] in self?.render($0) }
            .store(in: &subscriptions)
        viewModel.selection
            .sink { [weak self] in self?.applySelection($0) }
            .store(in: &subscriptions)
    }

    private func render(_ list: TrayList) {
        if let latest = list.latestURL, latest != renderedLatestURL,
           let item = list.contents.items.first(where: { $0.url == latest }) {
            cache.invalidate(latest)
            if let thumbnail = item.thumbnail {
                previews.store(thumbnail, for: latest)
            }
        }
        renderedLatestURL = list.latestURL
        let removed = cache.keep(only: Set(list.contents.items.map(\.url)))
        previews.forget(removed)
        sizing.forget(removed)
        entries = list.contents.visibleItems.map(cache.entry(for:))
        scroll.isHidden = list.contents.items.isEmpty
        layout.columnCount = viewModel.isSingleColumn ? TrayMetrics.singleColumnCount : TrayMetrics.multiColumnCount
        layout.invalidateLayout()
        isApplyingSelection = true
        collection.reloadData()
        isApplyingSelection = false
        applySelection(viewModel.selectedURLs)
    }

    private func applySelection(_ urls: [URL]) {
        let selected = Set(urls)
        let paths = Set(
            entries.enumerated().compactMap {
                selected.contains($0.element.url) ? IndexPath(item: $0.offset, section: 0) : nil
            }
        )
        guard collection.selectionIndexPaths != paths else {
            return
        }
        isApplyingSelection = true
        collection.selectionIndexPaths = paths
        isApplyingSelection = false
    }

    private func syncSelection() {
        guard !isApplyingSelection else {
            return
        }
        viewModel.select(urls: urls(at: collection.selectionIndexPaths))
    }

    private func urls(at indexPaths: Set<IndexPath>) -> [URL] {
        indexPaths.sorted { $0.item < $1.item }.compactMap {
            entries.indices.contains($0.item) ? entries[$0.item].url : nil
        }
    }

    private func aspectRatio(at index: Int) -> CGFloat {
        guard entries.indices.contains(index) else {
            return Self.squareRatio
        }
        return sizing.heightRatio(
            of: entries[index],
            columnWidth: layout.columnWidth,
            singleColumn: viewModel.isSingleColumn
        )
    }

    private func showPreview(for url: URL) {
        guard let index = entries.firstIndex(where: { $0.url == url }),
              let image = previews.image(for: url)
        else {
            return
        }
        (collection.item(at: IndexPath(
            item: index,
            section: 0
        )) as? TrayCardItem)?.showThumbnail(image)
    }
}
