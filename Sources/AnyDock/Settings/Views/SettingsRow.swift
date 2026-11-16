import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class SettingsRow: NSView {
    let titleLabel: NSTextField
    let detailLabel: NSTextField

    init(title: String, detail: String? = nil, accessories: [NSView]) {
        titleLabel = SettingsLabel.make(title)
        detailLabel = SettingsLabel.footnote(detail ?? "")
        detailLabel.isHidden = detail == nil
        super.init(frame: .zero)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = PKYLayout.Gap.content(.compact)
        labels.setHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel.snp.makeConstraints { $0.width.equalTo(labels) }
        let content = NSStackView(views: [labels] + accessories)
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = PKYLayout.Gap.content()
        embed(content)
    }

    init(content: NSView) {
        titleLabel = SettingsLabel.make()
        detailLabel = SettingsLabel.footnote()
        super.init(frame: .zero)
        embed(content)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    private func embed(_ content: NSView) {
        addSubview(content)
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.row.horizontal())
            make.centerY.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(PKYLayout.Inset.row.vertical()).priority(.high)
            make.top.greaterThanOrEqualToSuperview().inset(PKYLayout.Inset.row.vertical())
        }
        snp.makeConstraints { $0.height.greaterThanOrEqualTo(PKYLayout.Size.row(.compact)) }
    }
}
