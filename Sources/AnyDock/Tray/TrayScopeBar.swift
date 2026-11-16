import AnyDockCore
import AppKit
import Combine
import QuartzCore

@MainActor
final class TrayScopeBar: NSView {
    struct Segment: Equatable {
        let title: String
        let accessibilityLabel: String
        let filter: TrayFilter
    }

    private static let indicatorDuration: TimeInterval = 0.2
    private static let maxFadeFraction: CGFloat = 0.5
    private static let scrollEdgeTolerance: CGFloat = 0.5
    private static let fadeStartPoint = CGPoint(x: 0, y: 0.5)
    private static let fadeEndPoint = CGPoint(x: 1, y: 0.5)

    private(set) var segments = [Segment]()
    private(set) var selected = TrayFilter.all

    private let surface: NSView
    private let fade = CAGradientLayer()
    private lazy var indicator = ScopeIndicator()
    private var buttons = [ScopeSegmentButton]()

    private lazy var scroll: NSScrollView = {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = content
        scroll.wantsLayer = true
        scroll.layer?.mask = fade
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private lazy var content: FlippedView = {
        let content = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false
        return content
    }()

    private lazy var stack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var widthConstraint: NSLayoutConstraint = {
        let width = widthAnchor.constraint(equalToConstant: 0)
        width.priority = .defaultHigh
        return width
    }()

    private var isAnimating = false
    private let selectionSubject = PassthroughSubject<TrayFilter, Never>()
    private let selectAllSubject = PassthroughSubject<TrayFilter, Never>()

    var selections: AnyPublisher<TrayFilter, Never> {
        selectionSubject.eraseToAnyPublisher()
    }

    var selectAllRequests: AnyPublisher<TrayFilter, Never> {
        selectAllSubject.eraseToAnyPublisher()
    }

    var selectedButtonFrame: NSRect? {
        guard let index = segments.firstIndex(where: { $0.filter == selected }) else {
            return nil
        }
        return buttons[index].convert(buttons[index].bounds, to: self)
    }

    var indicatorFrame: NSRect {
        indicator.convert(indicator.bounds, to: self)
    }

    init(surface: NSView) {
        self.surface = surface
        super.init(frame: .zero)
        configure()
        addSubview(surface)
        content.addSubview(indicator)
        content.addSubview(stack)
        addSubview(scroll)
        let inset = TrayMetrics.scopeBarInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: TrayMetrics.scopeBarHeight),
            widthConstraint,
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        if !isAnimating {
            moveIndicator(animated: false)
        }
        updateFade()
    }

    func update(_ next: [Segment], selected filter: TrayFilter) {
        let animate =
            next.map(\.filter) == segments.map(\.filter) && filter != selected
                && window != nil
        if next != segments {
            for button in buttons {
                button.removeFromSuperview()
            }
            buttons = next.enumerated().map { index, segment in
                let button = ScopeSegmentButton(
                    title: segment.title,
                    target: self,
                    action: #selector(tapped)
                )
                button.tag = index
                button.setAccessibilityLabel(segment.accessibilityLabel)
                stack.addArrangedSubview(button)
                return button
            }
            segments = next
        }
        selected = filter
        for (button, segment) in zip(buttons, segments) {
            button.isChosen = segment.filter == filter
        }
        layoutSubtreeIfNeeded()
        widthConstraint.constant = stack.fittingSize.width + TrayMetrics.scopeBarInset * 2
        layoutSubtreeIfNeeded()
        moveIndicator(animated: animate)
        reveal(animated: animate)
        updateFade()
    }

    private func moveIndicator(animated: Bool) {
        guard let index = segments.firstIndex(where: { $0.filter == selected }),
              buttons.indices.contains(index)
        else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        let target = buttons[index].frame
        guard animated, indicator.frame != .zero else {
            indicator.frame = target
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.indicatorDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            indicator.animator().frame = target
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.isAnimating = false }
        }
    }

    private func reveal(animated: Bool) {
        guard let index = segments.firstIndex(where: { $0.filter == selected }),
              buttons.indices.contains(index)
        else {
            return
        }
        let target = buttons[index].frame.insetBy(dx: -TrayMetrics.scopeFade, dy: 0)
        if animated {
            NSAnimationContext.runAnimationGroup { _ in
                content.animator().scrollToVisible(target)
            }
        } else {
            content.scrollToVisible(target)
        }
    }

    private func configure() {
        surface.translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.tabGroup)
    }

    private func subscribeEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
    }

    @objc private func scrolled() {
        updateFade()
    }

    private func updateFade() {
        let visible = scroll.contentView.bounds
        let width = max(scroll.bounds.width, 1)
        let length = min(TrayMetrics.scopeFade / width, Self.maxFadeFraction)
        let leading = visible.minX > Self.scrollEdgeTolerance
        let trailing = content.frame.width - visible.maxX > Self.scrollEdgeTolerance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        fade.startPoint = Self.fadeStartPoint
        fade.endPoint = Self.fadeEndPoint
        fade.colors = [
            leading ? NSColor.clear.cgColor : NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            trailing ? NSColor.clear.cgColor : NSColor.black.cgColor,
        ]
        fade.locations = [
            0,
            NSNumber(value: Double(length)),
            NSNumber(value: Double(1 - length)),
            1,
        ]
        CATransaction.commit()
    }

    @objc private func tapped(_ sender: NSButton) {
        guard segments.indices.contains(sender.tag) else {
            return
        }
        let filter = segments[sender.tag].filter
        if Self.togglesSelection(NSApp.currentEvent) {
            selectAllSubject.send(filter)
        } else {
            selectionSubject.send(filter)
        }
    }
}

extension TrayScopeBar {
    nonisolated static func togglesSelection(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .leftMouseUp || event.type == .leftMouseDown else {
            return false
        }
        return event.clickCount >= 2 && event.clickCount % 2 == 0
    }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
private final class ScopeIndicator: NSView {
    private static let darkFill = NSColor(white: 1, alpha: 0.18)

    override var wantsUpdateLayer: Bool {
        true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layer?.cornerRadius = newSize.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor =
            (dark ? Self.darkFill : NSColor.white).cgColor
        layer?.apply(dark ? .none : .scopeIndicator)
    }

    private func configure() {
        wantsLayer = true
    }
}

@MainActor
private final class ScopeSegmentButton: NSButton {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(
            width: size.width + Space.s12 * 2,
            height: TrayMetrics.scopeBarHeight - TrayMetrics.scopeBarInset * 2
        )
    }

    var isChosen = false {
        didSet { refreshTitle() }
    }

    private var plainTitle = ""

    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        plainTitle = title
        self.target = target
        self.action = action
        configure()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTitle()
    }

    private func configure() {
        isBordered = false
        setButtonType(.momentaryChange)
        refreshTitle()
    }

    private func refreshTitle() {
        attributedTitle = NSAttributedString(
            string: plainTitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: isChosen ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ]
        )
        setAccessibilitySelected(isChosen)
    }
}
