import AnyDockCore
import AppKit
import Combine
import Quartz

@MainActor
final class TrayViewController: NSViewController, NSCollectionViewDataSource,
    NSCollectionViewDelegate {
    private static let dropZoneHeight: CGFloat = 34

    let collection = TrayCollectionView()
    let dropZone = TrayDropZone()
    let clipboardBar = ClipboardBar()
    private(set) var clipboardSurface: NSView?
    private(set) lazy var header = TrayHeaderView(viewModel: viewModel)
    private(set) var dropZoneSurface: NSView?
    let viewModel: TrayViewModel

    private let clipboard: ClipboardMonitor
    private let pasteboard: TrayPasteboardWriter
    private let presentationHoldSubject = PassthroughSubject<Bool, Never>()
    private let layout = MasonryCollectionLayout()
    private let scroll = NSScrollView()
    private let timeFormatter = DateFormatter()
    private var dropZoneAboveClipboard: NSLayoutConstraint?
    private var dropZoneAtBottom: NSLayoutConstraint?
    private var emptyState: NSView?
    private var entries = [TrayEntry]()
    private var cache = [URL: TrayEntry]()
    private let previews = TrayPreviewCache()
    private var subscriptions = Set<AnyCancellable>()
    private lazy var quickLook = TrayQuickLookController(owner: self, focusTarget: collection)
    private var releaseWatch: Timer?
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
        collection.escapePressed = { [weak self] in self?.collapseClipboard() ?? false }
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
        configureEmptyState(in: content)
        configureControls(in: content)
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        NSLayoutConstraint.activate([
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

    func replaceClips(_ clips: [ClipboardClip]) {
        loadViewIfNeeded()
        clipboardBar.update(clips)
        updateClipboardSurface()
    }

    @discardableResult
    func collapseClipboard() -> Bool {
        guard clipboardBar.isExpanded else {
            return false
        }
        clipboardBar.setExpanded(false)
        return true
    }

    func trayDidClose() {
        clearSelection()
        clipboardBar.setExpanded(false, animated: false)
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
            time: timeText(entry.item.receivedAt),
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
        watchForRelease()
    }

    func endDrag(operation: NSDragOperation) {
        releaseWatch?.invalidate()
        releaseWatch = nil
        viewModel.endDrag(succeeded: !operation.isEmpty)
    }

    @discardableResult
    func trashDraggedItems() -> Task<Void, Never>? {
        viewModel.trashDraggedItems()
    }

    func copyToPasteboard(_ item: ReceivedItem) {
        pasteboard.copy([cache[item.url] ?? TrayEntry(item: item)])
    }

    func closePreview() {
        quickLook.close()
    }

    private func configureControls(in content: NSView) {
        dropZone.canAccept = { [weak self] source in
            guard let self else {
                return false
            }
            return source === collection && viewModel.canDropOnTrash()
        }
        dropZone.performDrop = { [weak self] in self?.viewModel.trashDraggedItems() != nil }
        let zone = TrayGlass.surface(dropZone, cornerRadius: Self.dropZoneHeight / 2)
        zone.heightAnchor.constraint(equalToConstant: Self.dropZoneHeight).isActive = true
        dropZoneSurface = zone
        zone.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(zone)
        NSLayoutConstraint.activate([
            zone.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            zone.leadingAnchor.constraint(
                greaterThanOrEqualTo: content.leadingAnchor,
                constant: TrayMetrics.margin
            ),
            zone.trailingAnchor.constraint(
                lessThanOrEqualTo: content.trailingAnchor,
                constant: -TrayMetrics.margin
            ),
        ])
        dropZoneAtBottom = zone.bottomAnchor.constraint(
            equalTo: content.bottomAnchor,
            constant: -Space.s16
        )
        configureClipboardBar(in: content)
        dropZoneAboveClipboard = clipboardSurface.map {
            zone.bottomAnchor.constraint(equalTo: $0.topAnchor, constant: -Space.s8)
        }
        updateClipboardSurface()
    }

    private func configureClipboardBar(in content: NSView) {
        clipboard.clipsPublisher
            .sink { [weak self] in self?.replaceClips($0) }
            .store(in: &subscriptions)
        clipboardBar.clearRequests
            .sink { [weak self] in self?.clipboard.clear() }
            .store(in: &subscriptions)
        clipboardBar.copyRequests
            .sink { [weak self] in self?.copyClip($0) }
            .store(in: &subscriptions)
        clipboardBar.expandedChanges
            .sink { [weak self] _ in self?.updateClipboardSurface() }
            .store(in: &subscriptions)
        let surface = TrayGlass.surface(
            clipboardBar,
            cornerRadius: ClipboardBar.collapsedHeight / 2
        )
        surface.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(surface, positioned: .below, relativeTo: dropZoneSurface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: TrayMetrics.margin
            ),
            surface.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -TrayMetrics.margin
            ),
            surface.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Space.s16),
        ])
        clipboardSurface = surface
    }

    private func updateClipboardSurface() {
        guard let surface = clipboardSurface else {
            return
        }
        let visible = !clipboardBar.clips.isEmpty
        surface.isHidden = !visible
        dropZoneAtBottom?.isActive = !visible
        dropZoneAboveClipboard?.isActive = visible
        let radius = clipboardBar.isExpanded ? Space.s16 : ClipboardBar.collapsedHeight / 2
        TrayGlass.setCornerRadius(radius, of: surface)
        let height =
            clipboardBar.isExpanded ? ClipboardBar.expandedHeight : ClipboardBar.collapsedHeight
        layout.extraBottomInset = visible ? height + Space.s8 : 0
    }

    private func copyClip(_ clip: ClipboardClip) {
        clipboard.write(recordingInHistory: false) { $0.setString(clip.text, forType: .string) }
    }

    private func configureEmptyState(in content: NSView) {
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "tray", accessibilityDescription: nil) ?? NSImage()
        )
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: L10n.text("Nothing received yet"))
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let detail = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Share content on your iPhone and choose your Mac’s shortcut."
            )
        )
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        let stack = NSStackView(views: [icon, title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -64),
        ])
        emptyState = stack
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
        viewModel.dragged
            .sink { [weak self] _ in self?.updateControls() }
            .store(in: &subscriptions)
        viewModel.recycling
            .dropFirst()
            .sink { [weak self] in self?.recyclingChanged($0) }
            .store(in: &subscriptions)
        quickLook.holds
            .sink { [weak self] _ in self?.sendPresentationHold() }
            .store(in: &subscriptions)
        viewModel.recycleStarts
            .sink { [weak self] in self?.closePreview() }
            .store(in: &subscriptions)
        viewModel.errors
            .sink { [weak self] in self?.presentError($0) }
            .store(in: &subscriptions)
    }

    private func render(_ list: TrayList) {
        if let latest = list.latestURL, latest != renderedLatestURL,
           let item = list.contents.items.first(where: { $0.url == latest }) {
            cache[latest] = nil
            if let thumbnail = item.thumbnail {
                previews.store(thumbnail, for: latest)
            }
        }
        renderedLatestURL = list.latestURL
        let present = Set(list.contents.items.map(\.url))
        previews.forget(cache.keys.filter { !present.contains($0) })
        cache = cache.filter { present.contains($0.key) }
        entries = list.contents.visibleItems.map { item in
            if let cached = cache[item.url] {
                return cached
            }
            let entry = TrayEntry(item: item)
            cache[item.url] = entry
            return entry
        }
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
        updateControls()
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

    private func recyclingChanged(_: Bool) {
        sendPresentationHold()
        updateControls()
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

    private func watchForRelease() {
        releaseWatch?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTrashTargetIfReleased() }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatch = timer
    }

    private func hideTrashTargetIfReleased() {
        guard !viewModel.draggedURLs.isEmpty, NSEvent.pressedMouseButtons & 1 == 0 else {
            return
        }
        releaseWatch?.invalidate()
        releaseWatch = nil
        dropZoneSurface?.alphaValue = 0
    }

    private func updateControls() {
        let count = selectedEntries.count
        let dragging = !viewModel.draggedURLs.isEmpty
        if dragging {
            dropZone.show(L10n.text("Drop here to move to Trash"), armed: true)
        } else if count == 1, let entry = selectedEntries.first {
            let segments = detailSegments(of: entry).filter { !$0.isEmpty }
            let rest = segments.dropFirst().reduce("") { L10n.text("meta_separator", $0, $1) }
            dropZone.show(segments.first ?? "", suffix: rest, armed: false)
        } else {
            dropZone.show(count > 1 ? L10n.text("selected_count", count) : "", armed: false)
        }
        dropZoneSurface?.isHidden = !dragging && dropZone.label.stringValue.isEmpty
        dropZoneSurface?.alphaValue = 1
        emptyState?.isHidden = !viewModel.isEmpty
        scroll.isHidden = viewModel.isEmpty
    }

    private func detailSegments(of entry: TrayEntry) -> [String] {
        let time = timeText(entry.item.receivedAt)
        let size = entry.size.map { ByteCountFormatter.string(
            fromByteCount: $0,
            countStyle: .file
        ) }
        switch entry.kind {
        case .file: return [entry.displayName, size ?? "", time]
        case .image: return [entry.badge, size ?? "", time]
        case .text: return [L10n.text("character_count", entry.characterCount), time]
        case .link: return [entry.link?.absoluteString ?? entry.displayName]
        }
    }

    private func timeText(_ date: Date) -> String {
        timeFormatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d"
        return timeFormatter.string(from: date)
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
