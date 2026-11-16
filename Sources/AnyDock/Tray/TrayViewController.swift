import AnyDockCore
import AppKit
import Combine
import PockyFoundation
import Quartz

@MainActor
final class TrayViewController: NSViewController {
    let viewModel: TrayViewModel

    private(set) lazy var header: TrayHeaderView = {
        let header = TrayHeaderView(viewModel: viewModel)
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }()

    private(set) lazy var footer: TrayFooterView = {
        let footer = TrayFooterView(
            viewModel: viewModel,
            clipboard: clipboard,
            entries: cache,
            dragSource: collection
        )
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }()

    private let clipboard: ClipboardMonitor
    private let pasteboard: TrayPasteboardWriter
    private let cache = TrayEntryCache()
    private let presentationHoldSubject = PassthroughSubject<Bool, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var collections = TrayCollectionController(viewModel: viewModel, cache: cache)
    private lazy var emptyState = TrayEmptyStateView(viewModel: viewModel)
    private lazy var quickLook = TrayQuickLookController(owner: self, focusTarget: collection)

    var collection: TrayCollectionView {
        collections.collection
    }

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
        let scroll = collections.scroll
        collection.frame = content.bounds
        for element in [scroll, emptyState, footer, header] {
            content.addSubview(element)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
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
            footer.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: -PKYLayout.Space.s16
            ),
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

    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel?) -> Bool {
        MainActor.assumeIsolated { quickLook.isShowing }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            if let panel {
                quickLook.beginControl(panel)
            }
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            if let panel {
                quickLook.endControl(panel)
            }
        }
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
        collections.scrollToLatest()
    }

    func beginDrag(_ indexPaths: Set<IndexPath>) {
        collections.beginDrag(indexPaths)
    }

    func endDrag(operation: NSDragOperation) {
        collections.endDrag(operation: operation)
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
        collections.commands
            .sink { [weak self] in self?.perform($0) }
            .store(in: &subscriptions)
        footer.bottomInsets
            .sink { [weak self] in self?.collections.setBottomInset($0) }
            .store(in: &subscriptions)
        footer.clipboardExpansions
            .sink { [weak self] in self?.collection.consumesEscape = $0 }
            .store(in: &subscriptions)
        quickLook.holds
            .sink { [weak self] _ in self?.sendPresentationHold() }
            .store(in: &subscriptions)
        viewModel.recycling
            .dropFirst()
            .sink { [weak self] _ in self?.sendPresentationHold() }
            .store(in: &subscriptions)
        viewModel.recycleStarts
            .sink { [weak self] in self?.closePreview() }
            .store(in: &subscriptions)
        viewModel.errors
            .sink { [weak self] in self?.presentError($0) }
            .store(in: &subscriptions)
    }

    private func perform(_ command: TrayCollectionView.Command) {
        switch command {
        case .copy:
            pasteboard.copy(collections.selectedEntries)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(collections.selectedEntries.map(\.url))
        case .preview:
            quickLook.toggle(collections.selectedEntries.map(\.url))
        case .trash:
            viewModel.recycleSelection()
        case .collapseClipboard:
            footer.collapseClipboard()
        case .selectionChanged:
            break
        }
    }

    private func sendPresentationHold() {
        presentationHoldSubject.send(holdsPresentation)
    }
}
