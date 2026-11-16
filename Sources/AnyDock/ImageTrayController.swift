import AnyDockCore
import AppKit
import Combine
import Quartz

@MainActor
final class ImageTrayController: NSViewController, NSCollectionViewDataSource,
    NSCollectionViewDelegate, @MainActor QLPreviewPanelDelegate {
    let collection = ImageCollectionView()
    let dropZone = TrayDropZone()
    let clipboardBar = ClipboardBar()
    private(set) var clipboardSurface: NSView?
    private(set) lazy var filterBar = TrayScopeBar(
        surface: glassSurface(NSView(), cornerRadius: TrayMetrics.scopeBarHeight / 2)
    )
    private(set) var dropZoneSurface: NSView?
    private(set) var controlGroup: NSView?
    var presentationHeld: ((Bool) -> Void)?
    var loadItems: (() async throws -> [ReceivedItem])?
    var recycleItems: (([URL]) async throws -> Void)?
    var openFolder: (() -> Void)?
    var openSettings: (() -> Void)?
    var didFinishDragging: (() -> Void)?

    private let clipboard: ClipboardMonitor
    private var subscriptions = Set<AnyCancellable>()
    private let layout = MasonryCollectionLayout()
    private let scroll = NSScrollView()
    private let timeFormatter = DateFormatter()
    private var dropZoneAboveClipboard: NSLayoutConstraint?
    private var dropZoneAtBottom: NSLayoutConstraint?
    private var emptyState: NSView?
    private var contents = TrayContents()
    private var entries = [TrayEntry]()
    private var cache = [URL: TrayEntry]()
    private let previews = TrayPreviewCache()
    private var subscriptions = Set<AnyCancellable>()
    private var latestReceivedURL: URL?
    private var previewSource: ImagePreviewSource?
    private var isTrashing = false
    private var draggedURLs = [URL]()
    private var droppedOnTrash = false
    private var releaseWatch: Timer?

    var holdsPresentation: Bool {
        previewSource != nil || isTrashing
    }

    private var singleColumn: Bool {
        contents.filter == .kind(.text)
    }

    private var selectedEntries: [TrayEntry] {
        collection.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap {
            entries.indices.contains($0.item) ? entries[$0.item] : nil
        }
    }

    init(clipboard: ClipboardMonitor) {
        self.clipboard = clipboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
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
        collection.copyImages = { [weak self] in self?.copySelection() }
        collection.revealImages = { [weak self] in self?.revealSelection() }
        collection.previewImages = { [weak self] in self?.previewSelection() }
        collection.deleteImages = { [weak self] in
            guard let self else {
                return
            }
            trash(selectedEntries.map(\.url))
        }
        collection.selectionChanged = { [weak self] in self?.updateControls() }
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
        let group = configureControls(in: content)
        configureFilterBar(in: content, before: group)
        updateControls()
    }

    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { previewSource != nil }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = previewSource
            panel.delegate = self
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
            finishPreview()
        }
    }

    func select(_ filter: TrayFilter) {
        contents.select(filter)
        reloadEntries()
        scrollToLatestImage()
    }

    func toggleSelectAll(in filter: TrayFilter) {
        if contents.filter != filter {
            select(filter)
        }
        let all = Set(entries.indices.map { IndexPath(item: $0, section: 0) })
        collection.selectionIndexPaths = collection.selectionIndexPaths == all ? [] : all
        updateControls()
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

    func replaceItems(_ next: [ReceivedItem]) {
        loadViewIfNeeded()
        contents.replace(next)
        reloadEntries()
    }

    func append(_ item: ReceivedItem) {
        loadViewIfNeeded()
        latestReceivedURL = item.url
        cache[item.url] = nil
        if let thumbnail = item.thumbnail {
            previews.store(thumbnail, for: item.url)
        }
        contents.receive(item)
        reloadEntries()
    }

    func focusImages() {
        view.window?.makeFirstResponder(collection)
    }

    func clearSelection() {
        collection.selectionIndexPaths = []
        updateControls()
    }

    func scrollToLatestImage() {
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
        let latest = entry.url == latestReceivedURL
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
        updateControls()
    }

    func collectionView(
        _: NSCollectionView,
        didDeselectItemsAt _: Set<IndexPath>
    ) {
        updateControls()
    }

    func collectionView(
        _: NSCollectionView,
        canDragItemsAt indexPaths: Set<IndexPath>,
        with _: NSEvent
    ) -> Bool {
        collection.dragStartedOnImage && !indexPaths.isEmpty
    }

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        let entry = entries[indexPath.item]
        switch entry.kind {
        case .image, .file:
            return entry.url as NSURL
        case .text:
            return entry.fullText as NSString
        case .link:
            let item = NSPasteboardItem()
            if let link = entry.link {
                item.setString(link.absoluteString, forType: .URL)
                item.setString(link.absoluteString, forType: .string)
            }
            item.setString(entry.url.absoluteString, forType: .fileURL)
            return item
        }
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
        draggedURLs = indexPaths.sorted { $0.item < $1.item }.compactMap {
            entries.indices.contains($0.item) ? entries[$0.item].url : nil
        }
        droppedOnTrash = false
        updateControls()
        watchForRelease()
    }

    func endDrag(operation: NSDragOperation) {
        let trashed = droppedOnTrash
        releaseWatch?.invalidate()
        releaseWatch = nil
        draggedURLs = []
        droppedOnTrash = false
        updateControls()
        if !trashed, !operation.isEmpty {
            didFinishDragging?()
        }
    }

    @discardableResult
    func trashDraggedItems() -> Task<Void, Never>? {
        guard !draggedURLs.isEmpty, !isTrashing else {
            return nil
        }
        let targets = draggedURLs
        draggedURLs = []
        droppedOnTrash = true
        collection.selectionIndexPaths = []
        let task = trash(targets)
        updateControls()
        return task
    }

    func copyToPasteboard(_ item: ReceivedItem) {
        let entry = cache[item.url] ?? TrayEntry(item: item)
        clipboard.write(recordingInHistory: true) { $0.writeObjects([pasteboardItem(for: entry)]) }
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else {
            return false
        }
        if event.charactersIgnoringModifiers == " " {
            closePreview()
            return true
        }
        guard let source = previewSource, !source.urls.isEmpty else {
            return false
        }
        let step: Int
        switch event.keyCode {
        case 123, 126: step = -1
        case 124, 125: step = 1
        default: return false
        }
        panel.currentPreviewItemIndex = max(
            0,
            min(source.urls.count - 1, panel.currentPreviewItemIndex + step)
        )
        return true
    }

    func windowWillClose(_: Notification) {
        finishPreview()
    }

    func closePreview() {
        guard previewSource != nil else {
            return
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
           panel.currentController as AnyObject? === self {
            panel.close()
        }
        finishPreview()
    }

    private func configureFilterBar(in content: NSView, before group: NSView) {
        filterBar.onSelect = { [weak self] filter in self?.select(filter) }
        filterBar.onSelectAll = { [weak self] filter in self?.toggleSelectAll(in: filter) }
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(filterBar)
        NSLayoutConstraint.activate([
            filterBar.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: TrayMetrics.margin
            ),
            filterBar.trailingAnchor.constraint(
                lessThanOrEqualTo: group.leadingAnchor,
                constant: -Space.s8
            ),
            filterBar.topAnchor.constraint(
                equalTo: content.topAnchor,
                constant: TrayMetrics.margin
            ),
        ])
    }

    private func updateFilterBar() {
        filterBar.isHidden = contents.items.isEmpty
        filterBar.update(
            contents.availableFilters.map { filter in
                let count = kindCount(filter)
                return TrayScopeBar.Segment(
                    title: "\(filterTitle(filter)) \(count)",
                    accessibilityLabel: L10n.text(
                        "filter_accessibility",
                        filterTitle(filter),
                        count
                    ),
                    filter: filter
                )
            },
            selected: contents.filter
        )
    }

    private func kindCount(_ filter: TrayFilter) -> Int {
        guard case let .kind(kind) = filter else {
            return contents.items.count
        }
        return contents.count(of: kind)
    }

    private func filterTitle(_ filter: TrayFilter) -> String {
        switch filter {
        case .all: L10n.text("All")
        case .kind(.image): L10n.text("Images")
        case .kind(.text): L10n.text("Text")
        case .kind(.link): L10n.text("Links")
        case .kind(.file): L10n.text("Files")
        }
    }

    private func configureControls(in content: NSView) -> NSView {
        let folder = iconButton(
            symbol: "folder",
            title: L10n.text("Open Folder"),
            action: #selector(folderClicked)
        )
        let settings = iconButton(
            symbol: "gearshape",
            title: L10n.text("Settings"),
            action: #selector(settingsClicked)
        )
        let buttons = NSStackView(views: [folder, settings])
        buttons.spacing = 0
        buttons.edgeInsets = NSEdgeInsets(
            top: TrayMetrics.scopeBarInset,
            left: TrayMetrics.scopeBarInset,
            bottom: TrayMetrics.scopeBarInset,
            right: TrayMetrics.scopeBarInset
        )
        let group = glassSurface(buttons, cornerRadius: TrayMetrics.scopeBarHeight / 2)
        controlGroup = group
        dropZone.canAccept = { [weak self] source in
            guard let self else {
                return false
            }
            return source === collection && !draggedURLs.isEmpty && !isTrashing
        }
        dropZone.performDrop = { [weak self] in self?.trashDraggedItems() != nil }
        let zone = glassSurface(dropZone, cornerRadius: 17)
        zone.heightAnchor.constraint(equalToConstant: 34).isActive = true
        dropZoneSurface = zone
        for element in [group, zone] {
            element.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(element)
        }
        NSLayoutConstraint.activate([
            group.heightAnchor.constraint(equalToConstant: TrayMetrics.scopeBarHeight),
            group.topAnchor.constraint(equalTo: content.topAnchor, constant: TrayMetrics.margin),
            group.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -TrayMetrics.margin
            ),
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
        return group
    }

    private func configureClipboardBar(in content: NSView) {
        clipboardBar.onClear = { [weak self] in self?.clipboard.clear() }
        clipboard.clipsPublisher
            .sink { [weak self] in self?.replaceClips($0) }
            .store(in: &subscriptions)
        clipboardBar.onCopy = { [weak self] clip in self?.copyClip(clip) }
        clipboardBar.onExpandedChange = { [weak self] _ in self?.updateClipboardSurface() }
        let surface = glassSurface(clipboardBar, cornerRadius: ClipboardBar.collapsedHeight / 2)
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
        if #available(macOS 26, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            surface.layer?.cornerRadius = radius
        }
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

    private func iconButton(symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        button.target = self
        button.action = action
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }

    private func glassSurface(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            surface = effect
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        return surface
    }

    private func reloadEntries() {
        let selected = Set(selectedEntries.map(\.url))
        let present = Set(contents.items.map(\.url))
        previews.forget(cache.keys.filter { !present.contains($0) })
        cache = cache.filter { present.contains($0.key) }
        entries = contents.visibleItems.map { item in
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
        collection.reloadData()
        collection.selectionIndexPaths = Set(
            entries.enumerated().compactMap {
                selected.contains($0.element.url) ? IndexPath(item: $0.offset, section: 0) : nil
            }
        )
        updateFilterBar()
        updateControls()
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
        guard !draggedURLs.isEmpty, NSEvent.pressedMouseButtons & 1 == 0 else {
            return
        }
        releaseWatch?.invalidate()
        releaseWatch = nil
        dropZoneSurface?.alphaValue = 0
    }

    private func updateControls() {
        let count = selectedEntries.count
        let dragging = !draggedURLs.isEmpty
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
        emptyState?.isHidden = !contents.items.isEmpty
        scroll.isHidden = contents.items.isEmpty
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

    @discardableResult
    private func trash(_ targets: [URL]) -> Task<Void, Never>? {
        guard !isTrashing, !targets.isEmpty, let loadItems, let recycleItems else {
            return nil
        }
        isTrashing = true
        presentationHeld?(holdsPresentation)
        updateControls()
        return Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                isTrashing = false
                presentationHeld?(holdsPresentation)
                updateControls()
            }
            do {
                let allowed = try await Set(loadItems().map(\.url))
                let urls = targets.filter { allowed.contains($0) }
                guard !urls.isEmpty else {
                    return
                }
                closePreview()
                try await recycleItems(urls)
            } catch {
                presentError(error)
            }
        }
    }

    private func pasteboardItem(for entry: TrayEntry) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        switch entry.kind {
        case .image:
            item.setString(entry.url.absoluteString, forType: .fileURL)
            item.setDataProvider(ImageClipboardProvider(url: entry.url), forTypes: [.png])
        case .text:
            item.setString(entry.fullText, forType: .string)
        case .link:
            if let link = entry.link {
                item.setString(link.absoluteString, forType: .URL)
                item.setString(link.absoluteString, forType: .string)
            }
        case .file:
            item.setString(entry.url.absoluteString, forType: .fileURL)
        }
        return item
    }

    private func copySelection() {
        let selected = selectedEntries
        guard !selected.isEmpty else {
            return
        }
        clipboard.write(recordingInHistory: true) { $0.writeObjects(
            selected.map(pasteboardItem(for:))
        ) }
    }

    private func revealSelection() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedEntries.map(\.url))
    }

    private func previewSelection() {
        if previewSource != nil {
            closePreview()
            return
        }
        let urls = selectedEntries.map(\.url)
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }
        previewSource = ImagePreviewSource(urls: urls)
        presentationHeld?(holdsPresentation)
        focusImages()
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finishPreview() {
        guard previewSource != nil else {
            return
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
           panel.currentController as AnyObject? === self {
            panel.dataSource = nil
            panel.delegate = nil
        }
        previewSource = nil
        if NSApp.isActive, NSApp.keyWindow is QLPreviewPanel {
            view.window?.makeKey()
        }
        focusImages()
        presentationHeld?(holdsPresentation)
    }

    @objc private func folderClicked() {
        openFolder?()
    }

    @objc private func settingsClicked() {
        openSettings?()
    }
}

private final class ImagePreviewSource: NSObject, QLPreviewPanelDataSource {
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}

private final class ImageClipboardProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(
        _: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType _: NSPasteboard.PasteboardType
    ) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = NSBitmapImageRep(cgImage: image).representation(
                  using: .png,
                  properties: [:]
              )
        else {
            return
        }
        item.setData(png, forType: .png)
    }
}

@MainActor
final class ImageCollectionView: NSCollectionView {
    var copyImages: (() -> Void)?
    var revealImages: (() -> Void)?
    var previewImages: (() -> Void)?
    var deleteImages: (() -> Void)?
    var selectionChanged: (() -> Void)?
    var escapePressed: (() -> Bool)?
    private(set) var dragStartedOnImage = false

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            collectionViewLayout?.invalidateLayout()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let path = indexPathForItem(at: point) else {
            return nil
        }
        if !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
        }
        selectionChanged?()
        let menu = NSMenu()
        let count = selectionIndexPaths.count
        let copy = NSMenuItem(
            title: count > 1 ? L10n.text("copy_count", count) : L10n.text("Copy"),
            action: #selector(copy(_:)),
            keyEquivalent: "c"
        )
        copy.target = self
        menu.addItem(copy)
        let reveal = NSMenuItem(
            title: L10n.text("Show in Finder"),
            action: #selector(reveal),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())
        let trash = NSMenuItem(
            title: count > 1 ? L10n.text("trash_count", count) : L10n.text("Move to Trash"),
            action: #selector(trash),
            keyEquivalent: "\u{8}"
        )
        trash.target = self
        menu.addItem(trash)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        let clickedImage = indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil
        dragStartedOnImage = clickedImage
        super.mouseDown(with: event)
        if event.clickCount == 2, clickedImage {
            previewImages?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "c", event.modifierFlags.contains(.command) {
            copyImages?()
        } else if event.modifierFlags.contains(.command), event.keyCode == 51 {
            deleteImages?()
        } else if event.charactersIgnoringModifiers == " " {
            previewImages?()
        } else if event.keyCode == 53, escapePressed?() == true {
            return
        } else if event.keyCode == 53, !selectionIndexPaths.isEmpty {
            deselectAll(nil)
            selectionChanged?()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_: Any?) {
        copyImages?()
    }

    @objc private func reveal() {
        revealImages?()
    }

    @objc private func trash() {
        deleteImages?()
    }
}
