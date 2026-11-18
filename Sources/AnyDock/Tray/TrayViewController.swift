import AnyDockCore
import AppKit
import Combine
import PockyFoundation
import Quartz
import SnapKit

@MainActor
final class TrayViewController: NSViewController {
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
    private let cache = TrayEntryCache()
    private let previews = TrayPreviewCache()
    private let presentationHoldSubject = PassthroughSubject<Bool, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var collections = TrayCollectionController(
        viewModel: viewModel,
        cache: cache,
        previews: previews
    )
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
        viewModel.incomingThumbnails
            .sink { [previews] in previews.store($0.data, for: $0.url) }
            .store(in: &subscriptions)
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
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        emptyState.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(TrayEmptyStateView.opticalCenterOffset)
            make.width.lessThanOrEqualTo(content.snp.width)
                .offset(-PKYLayout.Inset.page(.wide) * 2)
        }
        footer.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.bottom.equalToSuperview().inset(PKYLayout.Inset.page(.standard))
        }
        header.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.top.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
        }
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
        view.window?.makeKey()
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

    private func perform(_ command: TrayCommand) {
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
        }
    }

    private func sendPresentationHold() {
        presentationHoldSubject.send(holdsPresentation)
    }
}
