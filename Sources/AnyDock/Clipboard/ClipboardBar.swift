import AnyDockCore
import AppKit
import Combine

@MainActor
final class ClipboardBar: NSView {
    static let collapsedHeight = Space.s8 + headerHeight + Space.s8
    static let expandedHeight = collapsedHeight + cellRowHeight + Space.s8

    private static let headerHeight: CGFloat = 24
    private static let cellRowHeight: CGFloat = 52
    private static let iconPointSize: CGFloat = 11
    private static let chevronPointSize: CGFloat = 10
    private static let expandDuration: TimeInterval = 0.15

    private(set) var isExpanded = false
    private(set) var clips = [ClipboardClip]()

    private(set) lazy var title: NSTextField = {
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return title
    }()

    private(set) lazy var clearButton: NSButton = {
        let button = NSButton(
            title: L10n.text("Clear"),
            target: self,
            action: #selector(clearClicked)
        )
        button.bezelStyle = .inline
        button.controlSize = .small
        return button
    }()

    private(set) lazy var chevron: NSButton = {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(chevronClicked)
        return button
    }()

    private(set) lazy var header: NSStackView = {
        let header = NSStackView()
        header.setViews([icon, title, NSView(), clearButton, chevron], in: .leading)
        header.spacing = Space.s8
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }()

    private let clearSubject = PassthroughSubject<Void, Never>()
    private let expandedSubject = PassthroughSubject<Bool, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var icon: NSImageView = {
        let icon = NSImageView(
            image: NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Self.iconPointSize,
            weight: .medium
        )
        icon.contentTintColor = .secondaryLabelColor
        return icon
    }()

    private lazy var cells = (0 ..< ClipboardHistory.limit).map { _ in ClipboardCell() }

    private lazy var cellRow: NSStackView = {
        let row = NSStackView(views: cells)
        row.distribution = .fillEqually
        row.spacing = Space.s8
        row.detachesHiddenViews = false
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }()

    private lazy var height = heightAnchor.constraint(equalToConstant: Self.collapsedHeight)

    var clearRequests: AnyPublisher<Void, Never> {
        clearSubject.eraseToAnyPublisher()
    }

    var copyRequests: AnyPublisher<ClipboardClip, Never> {
        Publishers.MergeMany(cells.map(\.copyRequests)).eraseToAnyPublisher()
    }

    var expandedChanges: AnyPublisher<Bool, Never> {
        expandedSubject.eraseToAnyPublisher()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(header)
        addSubview(cellRow)
        NSLayoutConstraint.activate([
            height,
            header.topAnchor.constraint(equalTo: topAnchor, constant: Space.s8),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s12),
            cellRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Space.s8),
            cellRow.heightAnchor.constraint(equalToConstant: Self.cellRowHeight),
            cellRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s12),
            cellRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s12),
        ])
        refresh()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if !isExpanded {
            setExpanded(true)
        } else if header.frame.contains(convert(event.locationInWindow, from: nil)) {
            setExpanded(false)
        }
    }

    func update(_ next: [ClipboardClip]) {
        clips = next
        refresh()
        if clips.isEmpty {
            setExpanded(false, animated: false)
        }
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard expanded != isExpanded, !expanded || !clips.isEmpty else {
            return
        }
        isExpanded = expanded
        refresh()
        let target = expanded ? Self.expandedHeight : Self.collapsedHeight
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.expandDuration
                context.allowsImplicitAnimation = true
                height.animator().constant = target
                window?.contentView?.layoutSubtreeIfNeeded()
            }
        } else {
            height.constant = target
        }
        expandedSubject.send(expanded)
    }

    private func refresh() {
        title.stringValue = isExpanded
            ? L10n.text("clipboard_expanded_title")
            : L10n.text("clipboard_collapsed_title", clips.count)
        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        let label = isExpanded ? L10n.text("Collapse Clipboard") : L10n.text("Expand Clipboard")
        chevron.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: Self.chevronPointSize,
                weight: .semibold
            ))
        chevron.toolTip = label
        chevron.setAccessibilityLabel(label)
        cellRow.isHidden = !isExpanded
        for (index, cell) in cells.enumerated() {
            cell.show(clips.indices.contains(index) ? clips[index] : nil, latest: index == 0)
        }
    }

    @objc private func clearClicked() {
        clearSubject.send()
    }

    @objc private func chevronClicked() {
        setExpanded(!isExpanded)
    }
}
