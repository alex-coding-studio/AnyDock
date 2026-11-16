import AnyDockCore
import AppKit

@MainActor
final class ClipboardBar: NSView {
    static let collapsedHeight = Space.s8 + 24 + Space.s8
    static let expandedHeight = collapsedHeight + 52 + Space.s8

    var onClear: (() -> Void)?
    var onCopy: ((ClipboardClip) -> Void)?
    var onExpandedChange: ((Bool) -> Void)?
    private(set) var isExpanded = false
    private(set) var clips = [ClipboardClip]()
    let title = NSTextField(labelWithString: "")
    let clearButton = NSButton()
    let chevron = NSButton()
    let header = NSStackView()

    private let cells = (0 ..< ClipboardHistory.limit).map { _ in ClipboardCell() }
    private let cellRow = NSStackView()
    private var height: NSLayoutConstraint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil)
                ?? NSImage()
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        clearButton.title = L10n.text("Clear")
        clearButton.bezelStyle = .inline
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        chevron.isBordered = false
        chevron.imagePosition = .imageOnly
        chevron.target = self
        chevron.action = #selector(chevronClicked)
        header.setViews([icon, title, NSView(), clearButton, chevron], in: .leading)
        header.spacing = Space.s8
        header.alignment = .centerY
        cellRow.distribution = .fillEqually
        cellRow.spacing = Space.s8
        cellRow.detachesHiddenViews = false
        for cell in cells {
            cell.onCopy = { [weak self] clip in self?.onCopy?(clip) }
            cellRow.addArrangedSubview(cell)
        }
        for element in [header, cellRow] {
            element.translatesAutoresizingMaskIntoConstraints = false
            addSubview(element)
        }
        let height = heightAnchor.constraint(equalToConstant: Self.collapsedHeight)
        self.height = height
        NSLayoutConstraint.activate([
            height,
            header.topAnchor.constraint(equalTo: topAnchor, constant: Space.s8),
            header.heightAnchor.constraint(equalToConstant: 24),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s12),
            cellRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Space.s8),
            cellRow.heightAnchor.constraint(equalToConstant: 52),
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
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                height?.animator().constant = target
                window?.contentView?.layoutSubtreeIfNeeded()
            }
        } else {
            height?.constant = target
        }
        onExpandedChange?(expanded)
    }

    private func refresh() {
        title.stringValue =
            isExpanded
                ? L10n.text("clipboard_expanded_title") : L10n.text(
                    "clipboard_collapsed_title",
                    clips.count
                )
        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        let label = isExpanded ? L10n.text("Collapse Clipboard") : L10n.text("Expand Clipboard")
        chevron.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevron.toolTip = label
        chevron.setAccessibilityLabel(label)
        cellRow.isHidden = !isExpanded
        for (index, cell) in cells.enumerated() {
            cell.show(clips.indices.contains(index) ? clips[index] : nil, latest: index == 0)
        }
    }

    @objc private func clearClicked() {
        onClear?()
    }

    @objc private func chevronClicked() {
        setExpanded(!isExpanded)
    }
}

@MainActor
final class ClipboardCell: NSView, NSDraggingSource {
    override var wantsUpdateLayer: Bool {
        true
    }

    var onCopy: ((ClipboardClip) -> Void)?
    private(set) var clip: ClipboardClip?

    private let text = NSTextField(wrappingLabelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let dot = LatestDot()
    private let formatter = RelativeDateTimeFormatter()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        text.isSelectable = false
        text.font = .systemFont(ofSize: 10)
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byWordWrapping
        text.cell?.truncatesLastVisibleLine = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        time.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        time.textColor = .secondaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        time.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let meta = NSStackView(views: [dot, time])
        meta.spacing = Space.s4
        for element in [text, meta] {
            element.translatesAutoresizingMaskIntoConstraints = false
            addSubview(element)
        }
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: topAnchor, constant: Space.s4),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s8),
            text.bottomAnchor.constraint(lessThanOrEqualTo: meta.topAnchor),
            meta.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s8),
            meta.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Space.s8),
            meta.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Space.s4),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(L10n.text("Double-click to copy"))
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.cornerRadius = Space.s8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func accessibilityPerformPress() -> Bool {
        guard let clip else {
            return false
        }
        onCopy?(clip)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let clip {
            onCopy?(clip)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let clip, let snapshot = bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }
        cacheDisplay(in: bounds, to: snapshot)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(snapshot)
        let item = NSDraggingItem(pasteboardWriter: clip.text as NSString)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func show(_ clip: ClipboardClip?, latest: Bool) {
        self.clip = clip
        alphaValue = clip == nil ? 0 : 1
        setAccessibilityElement(clip != nil)
        guard let clip else {
            return
        }
        text.stringValue = String(clip.text.prefix(200))
        time.stringValue = formatter.localizedString(for: clip.copiedAt, relativeTo: Date())
        dot.isHidden = !latest
        setAccessibilityLabel(String(clip.text.prefix(80)))
        needsDisplay = true
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
