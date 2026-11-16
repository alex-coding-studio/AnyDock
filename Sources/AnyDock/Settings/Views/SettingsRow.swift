import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class SettingsRow: NSView {
    let titleLabel: NSTextField
    let detailLabel: NSTextField

    init(icon: NSView? = nil, title: String, detail: String? = nil, accessories: [NSView]) {
        titleLabel = SettingsLabel.make(title, wraps: true)
        detailLabel = SettingsLabel.footnote(detail ?? "")
        detailLabel.isHidden = detail == nil
        super.init(frame: .zero)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = PKYLayout.Gap.content(.compact)
        for label in [titleLabel, detailLabel] {
            label.snp.makeConstraints { $0.width.equalTo(labels) }
        }
        let leading = NSStackView(views: [icon, labels].compactMap(\.self))
        leading.orientation = .horizontal
        leading.alignment = .centerY
        leading.spacing = PKYLayout.Gap.content()
        leading.distribution = .fill
        leading.setClippingResistancePriority(.defaultLow, for: .horizontal)
        leading.setHuggingPriority(.fittingSizeCompression, for: .horizontal)
        for accessory in accessories {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            if accessory.contentCompressionResistancePriority(for: .horizontal) > .defaultLow {
                accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
        }
        let controls = NSStackView(views: accessories)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = PKYLayout.Gap.content()
        controls.setHuggingPriority(.required, for: .horizontal)
        let content = NSView()
        content.addSubview(leading)
        content.addSubview(controls)
        leading.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.top.equalToSuperview().priority(.low)
            make.trailing.equalTo(controls.snp.leading).offset(-PKYLayout.Gap.group())
        }
        controls.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.top.equalToSuperview().priority(.low)
        }
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
