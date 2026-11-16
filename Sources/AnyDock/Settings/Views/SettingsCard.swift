import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class SettingsCard: NSView {
    enum Style {
        case standard
        case prominent
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    private let style: Style
    private let stack = NSStackView()
    private var separators = [ObjectIdentifier: NSView]()

    init(rows: [NSView], style: Style = .standard) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PKYShape.Radius.compact
        layer?.cornerCurve = .continuous
        layer?.borderWidth = PKYShape.Stroke.standard
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                stack.addArrangedSubview(separator)
                separator.snp.makeConstraints {
                    $0.width.equalTo(stack).offset(-2 * PKYLayout.Inset.row.horizontal())
                }
                separators[ObjectIdentifier(row)] = separator
            }
            stack.addArrangedSubview(row)
            row.snp.makeConstraints { $0.width.equalTo(stack) }
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateLayer() {
        switch style {
        case .standard:
            layer?.backgroundColor = NSColor.pkyBackground(.grouped(.secondary)).cgColor
            layer?.borderColor = NSColor.pkySeparator(.standard).cgColor
        case .prominent:
            layer?.backgroundColor = NSColor.pkyAccent(.primary).withAlphaComponent(
                PKYOpacity.tint
            ).cgColor
            layer?.borderColor = NSColor.pkySeparator(.standard).cgColor
        }
    }

    static func titled(_ title: String?, card: NSView, footer: NSView? = nil) -> NSStackView {
        let heading = title.map {
            SettingsLabel.make($0, font: PKYSectionHeaderRole.group.title.semibold)
        }
        let views = [heading, card, footer].compactMap(\.self)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = PKYLayout.Gap.content()
        for view in [card, footer].compactMap(\.self) {
            view.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        if let heading {
            heading.snp.makeConstraints { $0.width.equalTo(stack).offset(
                -PKYLayout.Inset.row.horizontal()
            ) }
        }
        return stack
    }

    func setRow(_ row: NSView, hidden: Bool) {
        row.isHidden = hidden
        separators[ObjectIdentifier(row)]?.isHidden = hidden
    }
}
