import AnyDockCore
import AppKit
import Combine
import Quartz

@MainActor
final class TrayViewController: NSViewController, NSCollectionViewDataSource,
    NSCollectionViewDelegate {
    let collection = TrayCollectionView()
    let viewModel: TrayViewModel
    private(set) lazy var header = TrayHeaderView(viewModel: viewModel)
    private(set) lazy var footer = TrayFooterView(
        viewModel: viewModel,
        clipboard: clipboard,
        entries: cache,
        dragSource: collection
    )

    private let clipboard: ClipboardMonitor
    private let pasteboard: TrayPasteboardWriter
    private let presentationHoldSubject = PassthroughSubject<Bool, Never>()
    private let layout = MasonryCollectionLayout()
    private let scroll = NSScrollView()
    private lazy var emptyState = TrayEmptyStateView(viewModel: viewModel)
    private var entries = [TrayEntry]()
    private let cache = TrayEntryCache()
    private let previews = TrayPreviewCache()
    private var subscriptions = Set<AnyCancellable>()
    private lazy var quickLook = TrayQuickLookController(owner: self, focusTarget: collection)
    private var renderedLatestURL: URL?
    private var isApplyingSelection = false

    var presentationHolds: AnyPublisher<Bool, Never> {
        presentationHoldSubject.eraseToAnyPublisher()
    }

    var dragFinishes: AnyPublisher<Void, Never> {
        viewModel.dragFinishes
    }

    var folderRequests: AnyPublisher<Void, Never> {
        header.folderRequests
    }

    var settingsRequests: AnyPublisher<Void, Never> {
        header.settingsRequests
    }

    var holdsPresentation: Bool {
        quickLook.isShowing || viewModel.isRecycling
    }

    private var singleColumn: Bool {
        viewModel.contents.filter == .kind(.text)
    }

    private var selectedEntries: [TrayEntry] {
        let selected = Set(viewModel.selectedURLs)
        return entries.filter { selected.contains($0.url) }
    }

    init(viewModel: TrayViewModel, clipboard: ClipboardMonitor) {
        self.viewModel = viewModel
        self.clipboard = clipboard
        pasteboard = TrayPasteboardWriter(clipboard: clipboard)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let content = NSView(frame: NSRect(origin: .zero, size: TrayMetrics.popoverSize))
        view = content
        layout.aspectRatio = { [weak self] path in self?.aspectRatio(at: path.item) ?? 1 }
        previews.loaded.sink { [weak self] url in self?.showPreview(for: url) }
            .store(in: &subscriptions)
        collection.collectionViewLayout = layout
        collection.frame = content.bounds
        collection.autoresizingMask = [.width]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.register(ImageCardItem.self, forItemWithIdentifier: ImageCardItem.identifier)
        collection.register(TextCardItem.self, forItemWithIdentifier: TextCardItem.identifier)
        collection.register(LinkCardItem.self, forItemWithIdentifier: LinkCardItem.identifier)
        collection.register(FileCardItem.self, forItemWithIdentifier: FileCardItem.identifier)
        collection.dataSource = self
        collection.delegate = self
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .delete], forLocal: true)
        collection.copyItems = { [weak self] in self?.copySelection() }
        collection.revealItems = { [weak self] in self?.revealSelection() }
        collection.previewItems = { [weak self] in self?.previewSelection() }
        collection.trashItems = { [weak self] in self?.viewModel.recycleSelection() }
        collection.selectionChanged = { [weak self] in self?.syncSelection() }
        collection.escapePressed = { [weak self] in self?.footer.collapseClipboard() ?? false }
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        for element in [emptyState, footer, header] {
            element.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(element)
        }
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyState.centerYAnchor.constraint(
                equalTo: content.centerYAnchor,
                constant: TrayEmptyStateView.centerOffset
            ),
            emptyState.widthAnchor.constraint(
                lessThanOrEqualTo: content.widthAnchor,
                constant: -TrayEmptyStateView.sideInset * 2
            ),
            footer.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: TrayMetrics.margin
            ),
            footer.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -TrayMetrics.margin
            ),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Space.s16),
            header.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: TrayMetrics.margin
            ),
            header.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -TrayMetrics.margin
            ),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: TrayMetrics.margin),
        ])
        subscribeEvents()
    }

    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook.isShowing }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.beginControl(panel) }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.endControl(panel) }
    }

    func select(_ filter: TrayFilter) {
        viewModel.select(filter)
        scrollToLatest()
    }

    func toggleSelectAll(in filter: TrayFilter) {
        let switching = viewModel.contents.filter != filter
        viewModel.toggleSelectAll(in: filter)
        if switching {
            scrollToLatest()
        }
    }

    func trayDidClose() {
        clearSelection()
        footer.trayDidClose()
    }

    func focusCollection() {
        view.window?.makeFirstResponder(collection)
    }

    func clearSelection() {
        viewModel.clearSelection()
    }

    func scrollToLatest() {
        guard !entries.isEmpty else {
            return
        }
        collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int)
        -> Int {
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let entry = entries[indexPath.item]
        let identifier: NSUserInterfaceItemIdentifier =
            switch entry.kind {
            case .image: ImageCardItem.identifier
            case .text: TextCardItem.identifier
            case .link: LinkCardItem.identifier
            case .file: FileCardItem.identifier
            }
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
        let latest = entry.url == viewModel.latestURL
        (item as? TrayCardItem)?.configure(
            entry,
            singleColumn: singleColumn,
            time: TrayTimeFormat.short(entry.item.receivedAt),
            latest: latest
        )
        if entry.kind == .image || (entry.kind == .file && !entry.item.isPlainText) {
            if let image = previews.image(for: entry.url) {
                show(image, in: item)
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
                kindName(entry.kind),
                entry.summary,
                timestamp
            )
        )
        return item
    }

    func collectionView(
        _: NSCollectionView,
        didSelectItemsAt _: Set<IndexPath>
    ) {
        syncSelection()
    }

    func collectionView(
        _: NSCollectionView,
        didDeselectItemsAt _: Set<IndexPath>
    ) {
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

    func beginDrag(_ indexPaths: Set<IndexPath>) {
        viewModel.beginDrag(urls(at: indexPaths))
    }

    func endDrag(operation: NSDragOperation) {
        viewModel.endDrag(succeeded: !operation.isEmpty)
    }

    @discardableResult
    func trashDraggedItems() -> Task<Void, Never>? {
        viewModel.trashDraggedItems()
    }

    func copyToPasteboard(_ item: ReceivedItem) {
        pasteboard.copy([cache.entry(for: item)])
    }

    func closePreview() {
        quickLook.close()
    }

    private func subscribeEvents() {
        header.filterSelections
            .sink { [weak self] in self?.select($0) }
            .store(in: &subscriptions)
        header.selectAllRequests
            .sink { [weak self] in self?.toggleSelectAll(in: $0) }
            .store(in: &subscriptions)
        collection.publisher(for: \.selectionIndexPaths)
            .sink { [weak self] _ in self?.syncSelection() }
            .store(in: &subscriptions)
        viewModel.list
            .sink { [weak self] in self?.render($0) }
            .store(in: &subscriptions)
        viewModel.selection
            .sink { [weak self] in self?.applySelection($0) }
            .store(in: &subscriptions)
        viewModel.recycling
            .dropFirst()
            .sink { [weak self] _ in self?.sendPresentationHold() }
            .store(in: &subscriptions)
        quickLook.holds
            .sink { [weak self] _ in self?.sendPresentationHold() }
            .store(in: &subscriptions)
        viewModel.recycleStarts
            .sink { [weak self] in self?.closePreview() }
            .store(in: &subscriptions)
        footer.bottomInsets
            .sink { [weak self] in self?.layout.extraBottomInset = $0 }
            .store(in: &subscriptions)
        viewModel.errors
            .sink { [weak self] in self?.presentError($0) }
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
        previews.forget(cache.keep(only: Set(list.contents.items.map(\.url))))
        entries = list.contents.visibleItems.map(cache.entry(for:))
        scroll.isHidden = list.contents.items.isEmpty
        layout.columnCount = singleColumn ? 1 : 4
        layout.topInset = TrayMetrics.margin + TrayMetrics.scopeBarHeight + Space.s16
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
        if collection.selectionIndexPaths != paths {
            isApplyingSelection = true
            collection.selectionIndexPaths = paths
            isApplyingSelection = false
        }
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

    private func sendPresentationHold() {
        presentationHoldSubject.send(holdsPresentation)
    }

    private func aspectRatio(at index: Int) -> CGFloat {
        guard entries.indices.contains(index) else {
            return 1
        }
        let entry = entries[index]
        switch entry.kind {
        case .image:
            return entry.item.aspectRatio.map { CGFloat($0) } ?? 1
        case .text:
            guard singleColumn else {
                return 1.15
            }
            return 112 / max(layout.availableWidth, 1)
        case .link: return 1
        case .file: return 1.4
        }
    }

    private func showPreview(for url: URL) {
        guard let index = entries.firstIndex(where: { $0.url == url }),
              let image = previews.image(for: url)
        else {
            return
        }
        show(image, in: collection.item(at: IndexPath(item: index, section: 0)))
    }

    private func show(_ image: NSImage, in item: NSCollectionViewItem?) {
        switch item {
        case let card as ImageCardItem: card.showThumbnail(image)
        case let card as FileCardItem: card.showThumbnail(image)
        default: break
        }
    }

    private func kindName(_ kind: ReceivedKind) -> String {
        switch kind {
        case .image: L10n.text("Image")
        case .text: L10n.text("Text")
        case .link: L10n.text("Link")
        case .file: L10n.text("File")
        }
    }

    private func copySelection() {
        pasteboard.copy(selectedEntries)
    }

    private func revealSelection() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedEntries.map(\.url))
    }

    private func previewSelection() {
        quickLook.toggle(selectedEntries.map(\.url))
    }
}
