import AppKit
import PockyFoundation
import SnapKit

@MainActor
class PolaroidCardItem: TrayCardItem {
    private(set) lazy var previewArea: PreviewArea = {
        let area = PreviewArea()
        area.setContentHuggingPriority(.defaultLow, for: .vertical)
        area.wantsLayer = true
        area.layer?.cornerRadius = PKYShape.Radius.content
        area.layer?.masksToBounds = true
        return area
    }()

    private(set) lazy var caption: NSTextField = {
        let caption = NSTextField(labelWithString: "")
        caption.font = TrayCardSizing.captionFont
        caption.lineBreakMode = .byTruncatingMiddle
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        caption.setContentCompressionResistancePriority(.required, for: .vertical)
        return caption
    }()

    private lazy var strip: NSStackView = {
        let strip = NSStackView(views: [dot, caption])
        strip.spacing = PKYLayout.Gap.content(.compact)
        strip.setHuggingPriority(.defaultHigh, for: .vertical)
        return strip
    }()

    override func buildContent(in container: NSView) {
        container.addSubview(previewArea)
        container.addSubview(strip)
        previewArea.addSubview(badge)
        buildPreview(in: previewArea)
        previewArea.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
                .inset(PKYLayout.Inset.container(.compact))
            make.bottom.equalTo(strip.snp.top).offset(-PKYLayout.Gap.content(.compact))
        }
        strip.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
                .inset(PKYLayout.Inset.container(.compact))
        }
        badge.snp.makeConstraints {
            $0.top.leading.equalToSuperview().inset(PKYLayout.Gap.content(.compact))
        }
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        card.polaroid = true
    }

    func buildPreview(in _: NSView) {}

    func showTime(_ time: String) {
        caption.font = TrayCardSizing.timeFont
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        caption.stringValue = time
    }

    fileprivate func fill(
        _ subview: NSView,
        in area: NSView,
        top target: ConstraintItem,
        offset: CGFloat
    ) {
        area.addSubview(subview, positioned: .below, relativeTo: badge)
        subview.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview()
                .inset(PKYLayout.Inset.container(.compact))
            make.top.equalTo(target).offset(offset)
            make.bottom.lessThanOrEqualToSuperview()
                .inset(PKYLayout.Inset.container(.compact))
        }
    }
}

@MainActor
final class TextCardItem: PolaroidCardItem {
    lazy var body = label(font: TrayCardSizing.bodyFont, lines: 0)

    override func buildPreview(in area: NSView) {
        fill(body, in: area, top: area.snp.top, offset: TrayCardSizing.badgeClearance)
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        body.stringValue = entry.text ?? ""
        showTime(time)
    }
}

@MainActor
final class LinkCardItem: PolaroidCardItem {
    private(set) lazy var domain: NSTextField = {
        let domain = label(font: TrayCardSizing.domainFont, lines: 1)
        domain.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return domain
    }()

    private(set) lazy var address: NSTextField = {
        let address = label(font: TrayCardSizing.addressFont, lines: 0)
        address.textColor = .secondaryLabelColor
        return address
    }()

    override func buildPreview(in area: NSView) {
        fill(domain, in: area, top: area.snp.top, offset: TrayCardSizing.badgeClearance)
        fill(address, in: area, top: domain.snp.bottom, offset: PKYLayout.Gap.content(.compact))
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        domain.stringValue = entry.link?.host(percentEncoded: false) ?? entry.displayName
        address.stringValue = entry.link?.absoluteString ?? ""
        showTime(time)
    }
}

@MainActor
final class FileCardItem: PolaroidCardItem {
    private(set) lazy var preview: NSImageView = {
        let preview = NSImageView()
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return preview
    }()

    private lazy var lines: NSTextField = {
        let lines = label(font: TrayCardSizing.fileLinesFont, lines: 0)
        lines.textColor = .secondaryLabelColor
        return lines
    }()

    override func buildPreview(in area: NSView) {
        area.addSubview(preview, positioned: .below, relativeTo: badge)
        preview.snp.makeConstraints { $0.edges.equalToSuperview() }
        fill(lines, in: area, top: area.snp.top, offset: TrayCardSizing.badgeClearance)
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        let plainText = entry.item.isPlainText
        preview.isHidden = plainText
        lines.isHidden = !plainText
        preview.image = plainText ? nil : entry.thumbnail
        lines.stringValue = plainText ? entry.text ?? "" : ""
        caption.font = TrayCardSizing.captionFont
        caption.textColor = .labelColor
        caption.lineBreakMode = .byTruncatingMiddle
        caption.stringValue = entry.displayName
    }

    override func showThumbnail(_ image: NSImage) {
        guard !preview.isHidden else {
            return
        }
        preview.image = image
    }
}
