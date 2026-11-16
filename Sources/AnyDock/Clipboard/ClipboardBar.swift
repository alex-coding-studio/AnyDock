import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class ClipboardBar: NSView {
    static let collapsedHeight = headerHeight + PKYLayout.Inset.container(.compact) * 2
    static let expandedHeight = collapsedHeight + cellRowHeight + PKYLayout.Gap.content(.standard)

    private static let headerHeight: CGFloat = 24
    private static let cellRowHeight: CGFloat = 52

    private(set) var isExpanded = false
    private(set) var clips = [ClipboardClip]()

    private(set) lazy var title: NSTextField = {
        let title = NSTextField(labelWithString: "")
        title.font = PKYTypographyRole.supporting.semibold.nsFont(in: PKYThemeFallback.system)
        title.textColor = .pkyContent(.secondary)
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
        header.spacing = PKYLayout.Gap.content(.standard)
        header.alignment = .centerY
        return header
    }()

    private let clearSubject = PassthroughSubject<Void, Never>()
    private let expandedSubject = PassthroughSubject<Bool, Never>()

    private lazy var icon: NSImageView = {
        let icon = NSImageView(
            image: NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: PKYIcon.Size.accessory.pointSize,
            weight: .medium
        )
        icon.contentTintColor = .pkyContent(.secondary)
        return icon
    }()

    private lazy var cells = (0 ..< ClipboardHistory.limit).map { _ in ClipboardCell() }

    private lazy var cellRow: NSStackView = {
        let row = NSStackView(views: cells)
        row.distribution = .fillEqually
        row.spacing = PKYLayout.Gap.content(.standard)
        row.detachesHiddenViews = false
        return row
    }()

    private var height: Constraint?

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
        configure()
        addSubview(header)
        addSubview(cellRow)
        snp.makeConstraints { make in
            height = make.height.equalTo(Self.collapsedHeight).constraint
        }
        header.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(PKYLayout.Inset.container(.compact))
            make.height.equalTo(Self.headerHeight)
            make.directionalHorizontalEdges.equalToSuperview()
                .inset(PKYLayout.Inset.row.horizontal(.compact))
        }
        cellRow.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(PKYLayout.Gap.content(.standard))
            make.height.equalTo(Self.cellRowHeight)
            make.directionalHorizontalEdges.equalToSuperview()
                .inset(PKYLayout.Inset.row.horizontal(.compact))
        }
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
                context.duration = PKYMotion.Duration.quick
                context.allowsImplicitAnimation = true
                height?.layoutConstraints.first?.animator().constant = target
                window?.contentView?.layoutSubtreeIfNeeded()
            }
        } else {
            height?.update(offset: target)
        }
        expandedSubject.send(expanded)
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        refresh()
    }

    private func refresh() {
        title.stringValue = isExpanded
            ? L10n.text("clipboard_expanded_title")
            : L10n.text("clipboard_collapsed_title", clips.count)
        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        let label = isExpanded ? L10n.text("Collapse Clipboard") : L10n.text("Expand Clipboard")
        chevron.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: PKYIcon.Size.accessory.pointSize,
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
