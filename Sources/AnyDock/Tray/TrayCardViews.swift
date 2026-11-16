import AppKit

@MainActor
final class BadgeView: NSView {
    enum Style {
        case solid(NSColor)
        case neutral
        case media
    }

    private static let fontSize = NSFont.smallSystemFontSize - 2
    private static let mediaBackground = NSColor(white: 0, alpha: 0.6)

    private let label = NSTextField(labelWithString: "")
    private var style = Style.neutral

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s4),
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
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TrayMetrics.dot),
            heightAnchor.constraint(equalToConstant: TrayMetrics.dot),
        ])
        layer?.cornerRadius = TrayMetrics.dot / 2
        updateColors()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
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
    private static let selectedBorderWidth: CGFloat = 2
    private static let polaroidBorderWidth: CGFloat = 0.5

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
        wantsLayer = true
        layer?.cornerRadius = TrayMetrics.cornerRadius
        updateColors()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor =
                polaroid ? (dark ? Self.polaroidDark : Self.polaroidLight).cgColor : nil
            layer?.borderWidth =
                selected ? Self.selectedBorderWidth : (polaroid ? Self.polaroidBorderWidth : 0)
            layer?.borderColor =
                (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.apply(polaroid ? (dark ? .cardDark : .card) : .none)
            checkmark?.isHidden = !selected
        }
    }
}
