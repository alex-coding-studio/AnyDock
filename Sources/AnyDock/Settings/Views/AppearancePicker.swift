import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class AppearancePicker: NSView {
    var selectedMode: PKYAppearance.Mode? {
        didSet {
            for tile in tiles {
                tile.isSelected = tile.mode == selectedMode
            }
        }
    }

    private let selectionSubject = PassthroughSubject<PKYAppearance.Mode, Never>()
    private var tiles = [AppearanceTile]()

    var selections: AnyPublisher<PKYAppearance.Mode, Never> {
        selectionSubject.eraseToAnyPublisher()
    }

    init() {
        super.init(frame: .zero)
        tiles = PKYAppearance.Mode.allCases.map { mode in
            let tile = AppearanceTile(mode: mode)
            tile.target = self
            tile.action = #selector(select(_:))
            return tile
        }
        let stack = NSStackView(views: tiles)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = PKYLayout.Gap.group()
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(L10n.text("Appearance"))
    }

    required init?(coder _: NSCoder) {
        nil
    }

    @objc private func select(_ sender: AppearanceTile) {
        selectedMode = sender.mode
        selectionSubject.send(sender.mode)
    }
}

@MainActor
private final class AppearanceTile: NSControl {
    let mode: PKYAppearance.Mode
    var isSelected = false {
        didSet {
            preview.isSelected = isSelected
            label.font = (isSelected ? PKYTypographyRole.supporting.semibold : .supporting)
                .nsFont(in: PKYThemeFallback.system)
            label.textColor = .pkyContent(isSelected ? .primary : .secondary)
            setAccessibilityValue(isSelected)
        }
    }

    private let preview: AppearancePreview
    private let label: NSTextField

    init(mode: PKYAppearance.Mode) {
        self.mode = mode
        preview = AppearancePreview(mode: mode)
        label = SettingsLabel.make(
            Self.title(of: mode),
            font: .supporting,
            color: .pkyContent(.secondary)
        )
        super.init(frame: .zero)
        addSubview(preview)
        addSubview(label)
        preview.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(SettingsMetrics.appearancePreviewHeight)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(preview.snp.bottom).offset(PKYLayout.Gap.content())
            make.centerX.bottom.equalToSuperview()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(Self.title(of: mode))
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func mouseDown(with _: NSEvent) {
        sendAction(action, to: target)
    }

    override func accessibilityPerformPress() -> Bool {
        sendAction(action, to: target)
    }

    private static func title(of mode: PKYAppearance.Mode) -> String {
        switch mode {
        case .system: L10n.text("Follow System")
        case .light: L10n.text("Light")
        case .dark: L10n.text("Dark")
        }
    }
}

@MainActor
private final class AppearancePreview: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private let mode: PKYAppearance.Mode

    init(mode: PKYAppearance.Mode) {
        self.mode = mode
        super.init(frame: .zero)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: PKYShape.Stroke.strong, dy: PKYShape.Stroke.strong),
            xRadius: PKYShape.Radius.tile,
            yRadius: PKYShape.Radius.tile
        )
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        switch mode {
        case .system:
            drawWindow(appearance: .aqua, clip: nil)
            let split = NSBezierPath()
            split.move(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            split.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
            split.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
            split.close()
            drawWindow(appearance: .darkAqua, clip: split)
        case .light:
            drawWindow(appearance: .aqua, clip: nil)
        case .dark:
            drawWindow(appearance: .darkAqua, clip: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        outline.lineWidth = isSelected ? PKYShape.Stroke.strong : PKYShape.Stroke.standard
        (isSelected ? NSColor.pkyAccent(.primary) : NSColor.pkySeparator(.standard)).setStroke()
        outline.stroke()
    }

    private func drawWindow(appearance name: NSAppearance.Name, clip: NSBezierPath?) {
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            clip?.addClip()
            NSColor.pkyBackground(.standard(.tertiary)).setFill()
            bounds.fill()
            let pane = bounds.insetBy(
                dx: PKYLayout.Inset.container(.compact),
                dy: PKYLayout.Inset.container(.compact)
            )
            let window = NSBezierPath(
                roundedRect: pane,
                xRadius: PKYShape.Radius.tile,
                yRadius: PKYShape.Radius.tile
            )
            NSColor.pkyBackground(.standard(.primary)).setFill()
            window.fill()
            let sidebar = NSRect(
                x: pane.minX,
                y: pane.minY,
                width: pane.width / 3,
                height: pane.height
            )
            NSColor.pkyBackground(.standard(.secondary)).setFill()
            NSBezierPath(
                roundedRect: sidebar,
                xRadius: PKYShape.Radius.tile,
                yRadius: PKYShape.Radius.tile
            ).fill()
            let accent = NSRect(
                x: sidebar.maxX + PKYLayout.Gap.content(),
                y: pane.maxY - PKYLayout.Gap.content() - PKYLayout.Size.dot(),
                width: pane.width / 3,
                height: PKYLayout.Size.dot()
            )
            NSColor.pkyAccent(.primary).setFill()
            NSBezierPath(
                roundedRect: accent,
                xRadius: accent.height / 2,
                yRadius: accent.height / 2
            ).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
