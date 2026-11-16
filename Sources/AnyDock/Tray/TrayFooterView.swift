import AppKit
import Combine

@MainActor
final class TrayFooterView: NSView {
    private static let dropZoneHeight: CGFloat = 34
    private static let releasePollInterval: TimeInterval = 1.0 / 60
    private static let primaryButtonMask = 1

    private(set) lazy var dropZone = TrayDropZone()
    private(set) lazy var clipboardBar = ClipboardBar()

    private(set) lazy var dropZoneSurface: NSView = {
        let surface = TrayGlass.surface(dropZone, cornerRadius: Self.dropZoneHeight / 2)
        surface.translatesAutoresizingMaskIntoConstraints = false
        return surface
    }()

    private(set) lazy var clipboardSurface: NSView = {
        let surface = TrayGlass.surface(
            clipboardBar,
            cornerRadius: ClipboardBar.collapsedHeight / 2
        )
        surface.translatesAutoresizingMaskIntoConstraints = false
        return surface
    }()

    private let viewModel: TrayViewModel
    private let clipboard: ClipboardMonitor
    private let entries: TrayEntryCache
    private let bottomInsetSubject = CurrentValueSubject<CGFloat, Never>(0)
    private weak var dragSource: AnyObject?
    private var releaseWatch: Timer?
    private var subscriptions = Set<AnyCancellable>()

    private lazy var dropZoneAtBottom = dropZoneSurface.bottomAnchor.constraint(
        equalTo: bottomAnchor
    )
    private lazy var dropZoneAboveClipboard = dropZoneSurface.bottomAnchor.constraint(
        equalTo: clipboardSurface.topAnchor,
        constant: -Space.s8
    )

    var bottomInsets: AnyPublisher<CGFloat, Never> {
        bottomInsetSubject.eraseToAnyPublisher()
    }

    var clipboardExpansions: AnyPublisher<Bool, Never> {
        clipboardBar.expandedChanges
    }

    init(
        viewModel: TrayViewModel,
        clipboard: ClipboardMonitor,
        entries: TrayEntryCache,
        dragSource: AnyObject
    ) {
        self.viewModel = viewModel
        self.clipboard = clipboard
        self.entries = entries
        self.dragSource = dragSource
        super.init(frame: .zero)
        addSubview(clipboardSurface)
        addSubview(dropZoneSurface)
        NSLayoutConstraint.activate([
            clipboardSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipboardSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipboardSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            dropZoneSurface.heightAnchor.constraint(equalToConstant: Self.dropZoneHeight),
            dropZoneSurface.centerXAnchor.constraint(equalTo: centerXAnchor),
            dropZoneSurface.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            dropZoneSurface.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            dropZoneSurface.topAnchor.constraint(equalTo: topAnchor),
        ])
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private static func detailSegments(of entry: TrayEntry) -> [String] {
        let time = TrayTimeFormat.short(entry.item.receivedAt)
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

    func replaceClips(_ clips: [ClipboardClip]) {
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
        clipboardBar.setExpanded(false, animated: false)
    }

    private func subscribeEvents() {
        dropZone.canAccept = { [weak self] source in self?.canAccept(source) ?? false }
        dropZone.drops
            .sink { [weak self] in self?.viewModel.trashDraggedItems() }
            .store(in: &subscriptions)
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
        viewModel.dragged
            .sink { [weak self] in self?.draggedChanged($0) }
            .store(in: &subscriptions)
        Publishers.Merge3(
            viewModel.list.map { _ in () },
            viewModel.selection.map { _ in () },
            viewModel.recycling.map { _ in () }
        )
        .sink { [weak self] in self?.updateCapsule() }
        .store(in: &subscriptions)
    }

    private func canAccept(_ source: AnyObject?) -> Bool {
        source === dragSource && viewModel.canDropOnTrash()
    }

    private func copyClip(_ clip: ClipboardClip) {
        clipboard.write(recordingInHistory: false) { $0.setString(clip.text, forType: .string) }
    }

    private func updateClipboardSurface() {
        let visible = !clipboardBar.clips.isEmpty
        clipboardSurface.isHidden = !visible
        dropZoneAtBottom.isActive = !visible
        dropZoneAboveClipboard.isActive = visible
        let radius = clipboardBar.isExpanded ? Space.s16 : ClipboardBar.collapsedHeight / 2
        TrayGlass.setCornerRadius(radius, of: clipboardSurface)
        let height =
            clipboardBar.isExpanded ? ClipboardBar.expandedHeight : ClipboardBar.collapsedHeight
        bottomInsetSubject.send(visible ? height + Space.s8 : 0)
    }

    private func draggedChanged(_ urls: [URL]) {
        if urls.isEmpty {
            releaseWatch?.invalidate()
            releaseWatch = nil
        }
        updateCapsule()
        if !urls.isEmpty {
            watchForRelease()
        }
    }

    private func updateCapsule() {
        let selected = viewModel.selectedURLs
        let dragging = !viewModel.draggedURLs.isEmpty
        if dragging {
            dropZone.show(L10n.text("Drop here to move to Trash"), armed: true)
        } else if selected.count == 1, let entry = entry(for: selected[0]) {
            let segments = Self.detailSegments(of: entry).filter { !$0.isEmpty }
            let rest = segments.dropFirst().reduce("") { L10n.text("meta_separator", $0, $1) }
            dropZone.show(segments.first ?? "", suffix: rest, armed: false)
        } else {
            dropZone.show(
                selected.count > 1 ? L10n.text("selected_count", selected.count) : "",
                armed: false
            )
        }
        dropZoneSurface.isHidden = !dragging && dropZone.label.stringValue.isEmpty
        dropZoneSurface.alphaValue = 1
    }

    private func entry(for url: URL) -> TrayEntry? {
        viewModel.contents.items.first { $0.url == url }.map(entries.entry(for:))
    }

    private func watchForRelease() {
        releaseWatch?.invalidate()
        let timer = Timer(timeInterval: Self.releasePollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTrashTargetIfReleased() }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatch = timer
    }

    private func hideTrashTargetIfReleased() {
        guard !viewModel.draggedURLs.isEmpty,
              NSEvent.pressedMouseButtons & Self.primaryButtonMask == 0
        else {
            return
        }
        releaseWatch?.invalidate()
        releaseWatch = nil
        dropZoneSurface.alphaValue = 0
    }
}
