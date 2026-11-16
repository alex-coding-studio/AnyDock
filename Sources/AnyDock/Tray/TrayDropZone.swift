import AppKit
import Combine
import PockyFoundation

@MainActor
final class TrayDropZone: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    var canAccept: ((AnyObject?) -> Bool)?
    private(set) lazy var label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.dragThatCannotResizeWindow, for: .horizontal)
        return label
    }()

    private(set) lazy var suffix: NSTextField = {
        let suffix = NSTextField(labelWithString: "")
        suffix.setContentCompressionResistancePriority(.required, for: .horizontal)
        return suffix
    }()

    private(set) var isArmed = false
    private(set) var isTargeted = false {
        didSet { refresh() }
    }

    private let dropSubject = PassthroughSubject<Void, Never>()

    private lazy var row: NSStackView = {
        let row = NSStackView(views: [label, suffix])
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }()

    var drops: AnyPublisher<Void, Never> {
        dropSubject.eraseToAnyPublisher()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PKYLayout.Space.s12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PKYLayout.Space.s12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateLayer() {
        layer?.backgroundColor = isTargeted ? NSColor.systemRed.cgColor : NSColor.clear.cgColor
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isArmed, canAccept?(sender.draggingSource as AnyObject?) == true else {
            return []
        }
        isTargeted = true
        return .delete
    }

    override func draggingUpdated(_: any NSDraggingInfo) -> NSDragOperation {
        isTargeted ? .delete : []
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        isTargeted = false
    }

    override func prepareForDragOperation(_: any NSDraggingInfo) -> Bool {
        isTargeted
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { isTargeted = false }
        guard isTargeted, canAccept?(sender.draggingSource as AnyObject?) == true else {
            return false
        }
        dropSubject.send()
        return true
    }

    override func draggingEnded(_: any NSDraggingInfo) {
        isTargeted = false
    }

    func show(_ text: String, suffix detail: String = "", armed: Bool) {
        label.stringValue = text
        suffix.stringValue = detail
        suffix.isHidden = detail.isEmpty
        isArmed = armed
        if !armed {
            isTargeted = false
        }
        refresh()
    }

    private func configure() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    private func refresh() {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: isTargeted ? .semibold : .medium
        )
        for field in [label, suffix] {
            field.textColor = isTargeted ? .white : isArmed ? .systemRed : .labelColor
            field.font = font
        }
        needsDisplay = true
    }
}
