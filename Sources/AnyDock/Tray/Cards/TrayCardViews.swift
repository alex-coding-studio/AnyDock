import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class BadgeView: NSView {
    private var fill = NSColor.clear

    private lazy var label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = PKYTypographyRole.caption.semibold
            .withReferenceSize(TrayMetrics.denseBadgeFontSize)
            .nsFont(in: PKYThemeFallback.system)
        return label
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        addSubview(label)
        label.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview()
                .inset(PKYLayout.Inset.container(.compact))
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(TrayMetrics.badgeHeight) }
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

    func show(_ text: String, fill: NSColor, textColor: NSColor = .white) {
        label.stringValue = text
        self.fill = fill
        label.textColor = textColor
        updateColors()
    }

    private func configure() {
        wantsLayer = true
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
        }
    }
}

@MainActor
final class LatestDot: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
        snp.makeConstraints { $0.size.equalTo(PKYLayout.Size.dot(.compact)) }
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
        layer?.cornerRadius = PKYLayout.Size.dot(.compact) / 2
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.pkyAccent(.primary).cgColor
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
        layer?.backgroundColor = PKYThemeFallback.system.color.media.placeholder.cgColor
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
        layer?.cornerRadius = PKYShape.Radius.tile
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
                (selected ? NSColor.pkyAccent(.primary) : NSColor.pkySeparator(.standard)).cgColor
            layer?.pkyApplyElevation(
                polaroid ? .subtle : .none,
                color: CGColor.black,
                appearance: dark ? .dark : .light
            )
            checkmark?.isHidden = !selected
        }
    }
}
