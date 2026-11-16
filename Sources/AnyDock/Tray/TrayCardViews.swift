import AppKit
import PockyFoundation

@MainActor
final class BadgeView: NSView {
    enum Style {
        case solid(NSColor)
        case neutral
        case media
    }

    private static let fontSize = NSFont.smallSystemFontSize - 2
    private static let mediaBackground = NSColor(white: 0, alpha: PKYOpacity.dimmed)

    private var style = Style.neutral

    private lazy var label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PKYLayout.Space.s4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PKYLayout.Space.s4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: TrayMetrics.badgeHeight),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func show(_ text: String, style: Style) {
        label.stringValue = text
        self.style = style
        updateColors()
    }

    private func configure() {
        wantsLayer = true
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case let .solid(color):
                layer?.backgroundColor = color.cgColor
                label.textColor = .white
            case .neutral:
                layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
                label.textColor = .secondaryLabelColor
            case .media:
                layer?.backgroundColor = Self.mediaBackground.cgColor
                label.textColor = .white
            }
        }
    }
}

@MainActor
final class LatestDot: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TrayMetrics.dot),
            heightAnchor.constraint(equalToConstant: TrayMetrics.dot),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func configure() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = TrayMetrics.dot / 2
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}

@MainActor
final class PreviewArea: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    }
}

@MainActor
final class TopAlignedImageView: NSImageView {
    private static let opaqueFraction: CGFloat = 1

    override func draw(_: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return
        }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: isFlipped ? 0 : bounds.height - size.height,
            width: size.width,
            height: size.height
        )
        NSBezierPath(rect: bounds).addClip()
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: Self.opaqueFraction,
            respectFlipped: true,
            hints: nil
        )
    }
}

@MainActor
final class ThumbnailView: NSView {
    private static let polaroidLight = NSColor(white: 0.985, alpha: 1)
    private static let polaroidDark = NSColor(white: 0.24, alpha: 1)

    var checkmark: NSImageView?
    var selected = false {
        didSet {
            setAccessibilitySelected(selected)
            updateColors()
        }
    }

    var polaroid = false {
        didSet { updateColors() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = PKYShape.Radius.card
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor =
                polaroid ? (dark ? Self.polaroidDark : Self.polaroidLight).cgColor : nil
            layer?.borderWidth =
                selected ? PKYShape.Stroke.strong : (polaroid ? PKYShape.Stroke.standard : 0)
            layer?.borderColor =
                (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.pkyApplyElevation(
                polaroid ? .subtle : .none,
                color: CGColor.black,
                appearance: dark ? .dark : .light
            )
            checkmark?.isHidden = !selected
        }
    }
}
