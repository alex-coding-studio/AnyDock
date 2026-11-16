import AppKit
import Combine
import PockyFoundation

@MainActor
final class ClipboardCell: NSView, NSDraggingSource {
    private static let textFontSize: CGFloat = 10
    private static let timeFontSize: CGFloat = 9
    private static let previewLength = 200
    private static let accessibilityLength = 80

    override var wantsUpdateLayer: Bool {
        true
    }

    private(set) var clip: ClipboardClip?

    private let copySubject = PassthroughSubject<ClipboardClip, Never>()

    private lazy var text: NSTextField = {
        let text = NSTextField(wrappingLabelWithString: "")
        text.isSelectable = false
        text.font = .systemFont(ofSize: Self.textFontSize)
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byWordWrapping
        text.cell?.truncatesLastVisibleLine = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        text.translatesAutoresizingMaskIntoConstraints = false
        return text
    }()

    private lazy var time: NSTextField = {
        let time = NSTextField(labelWithString: "")
        time.font = .monospacedDigitSystemFont(ofSize: Self.timeFontSize, weight: .regular)
        time.textColor = .secondaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        time.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return time
    }()

    private lazy var dot = LatestDot()

    private lazy var meta: NSStackView = {
        let meta = NSStackView(views: [dot, time])
        meta.spacing = PKYLayout.Space.s4
        meta.translatesAutoresizingMaskIntoConstraints = false
        return meta
    }()

    private lazy var formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    var copyRequests: AnyPublisher<ClipboardClip, Never> {
        copySubject.eraseToAnyPublisher()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        addSubview(text)
        addSubview(meta)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: topAnchor, constant: PKYLayout.Space.s4),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PKYLayout.Space.s8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PKYLayout.Space.s8),
            text.bottomAnchor.constraint(lessThanOrEqualTo: meta.topAnchor),
            meta.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PKYLayout.Space.s8),
            meta.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -PKYLayout.Space.s8
            ),
            meta.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PKYLayout.Space.s4),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.cornerRadius = PKYLayout.Space.s8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func accessibilityPerformPress() -> Bool {
        guard let clip else {
            return false
        }
        copySubject.send(clip)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let clip {
            copySubject.send(clip)
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
        text.stringValue = String(clip.text.prefix(Self.previewLength))
        time.stringValue = formatter.localizedString(for: clip.copiedAt, relativeTo: Date())
        dot.isHidden = !latest
        setAccessibilityLabel(String(clip.text.prefix(Self.accessibilityLength)))
        needsDisplay = true
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    private func configure() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(L10n.text("Double-click to copy"))
    }
}
