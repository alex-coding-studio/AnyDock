import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class StatusDot: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    var tone = ListenerStatus.Tone.pending {
        didSet { needsDisplay = true }
    }

    init(size: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size / 2
        snp.makeConstraints { $0.size.equalTo(size) }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateLayer() {
        let color: NSColor = switch tone {
        case .pending: .pkyContent(.tertiary)
        case .listening: .pkyStatus(.success)
        case .failed: .pkyStatus(.destructive)
        }
        layer?.backgroundColor = color.cgColor
    }
}

@MainActor
final class ListenerBanner: NSView {
    var status = ListenerStatus(.starting) {
        didSet { render() }
    }

    private let dot = StatusDot(size: PKYLayout.Size.dot(.wide))
    private let title = SettingsLabel.make(font: PKYTypographyRole.body.semibold, wraps: true)
    private let detail = SettingsLabel.footnote()

    init() {
        super.init(frame: .zero)
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = PKYLayout.Gap.content(.compact)
        for label in [title, detail] {
            label.snp.makeConstraints { $0.width.equalTo(labels) }
        }
        let content = NSStackView(views: [dot, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = PKYLayout.Gap.content()
        let card = SettingsCard(rows: [SettingsRow(content: content)])
        addSubview(card)
        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        render()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    private func render() {
        dot.tone = status.tone
        title.stringValue = status.title
        title.textColor = status.tone == .failed ? .pkyStatus(.destructive) : .pkyContent(.primary)
        detail.stringValue = status.detail
        detail.isHidden = status.detail.isEmpty
        setAccessibilityLabel(
            [status.title, status.detail].filter { !$0.isEmpty }.joined(separator: ", ")
        )
    }
}
