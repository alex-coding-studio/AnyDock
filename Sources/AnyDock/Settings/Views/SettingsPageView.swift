import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class SettingsPageView: NSView {
    private let scroll = NSScrollView()
    private let footer: NSView?
    private var scrollBottom: Constraint?

    init(title: String, subtitle: String, sections: [NSView], footer: NSView? = nil) {
        self.footer = footer
        super.init(frame: NSRect(origin: .zero, size: SettingsMetrics.windowContentSize))
        let header = NSStackView(views: [
            SettingsLabel.make(title, font: PKYSectionHeaderRole.page.title),
            SettingsLabel.make(
                subtitle,
                font: PKYSectionHeaderRole.page.detail,
                color: .pkyContent(.secondary)
            ),
        ])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = PKYLayout.Gap.content(.compact)
        let stack = NSStackView(views: [header] + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PKYLayout.Gap.section(.compact)
        for view in sections {
            view.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        let document = FlippedView()
        document.addSubview(stack)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = true
        scroll.documentView = document
        addSubview(scroll)
        scroll.snp.makeConstraints { $0.top.leading.trailing.equalToSuperview() }
        if let footer {
            addSubview(footer)
            footer.snp.makeConstraints { $0.bottom.leading.trailing.equalToSuperview() }
        }
        setFooterHidden(true)
        document.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(scroll.contentView)
        }
        stack.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.width.lessThanOrEqualTo(PKYLayout.ContentWidth.maximum)
            make.leading.equalToSuperview().inset(PKYLayout.Inset.page(.wide)).priority(.high)
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func setFooterHidden(_ hidden: Bool) {
        let hidden = hidden || footer == nil
        footer?.isHidden = hidden
        scrollBottom?.deactivate()
        scroll.snp.makeConstraints { make in
            if hidden {
                scrollBottom = make.bottom.equalToSuperview().constraint
            } else if let footer {
                scrollBottom = make.bottom.equalTo(footer.snp.top).constraint
            }
        }
    }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
