import AnyDockCore
import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class CapsuleView: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    init(views: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        let content = NSStackView(views: views)
        content.orientation = .horizontal
        content.spacing = PKYLayout.Gap.content(.compact)
        addSubview(content)
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(
                PKYLayout.Inset.control.horizontal(.compact)
            )
            make.top.bottom.equalToSuperview().inset(PKYLayout.Inset.control.vertical(.compact))
        }
    }

    convenience init(kind: ReceivedKind) {
        let symbol = switch kind {
        case .image: "photo"
        case .text: "text.alignleft"
        case .link: "link"
        case .file: "doc"
        }
        self.init(views: [
            SettingsLabel.symbol(symbol, size: .accessory),
            SettingsLabel.make(
                kind.directoryName,
                font: .supporting,
                color: .pkyContent(.secondary)
            ),
        ])
        toolTip = kind.directoryName + "/"
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateLayer() {
        layer?.backgroundColor = PKYThemeFallback.system.color.filled.quiet(.tertiary).cgColor
    }
}
