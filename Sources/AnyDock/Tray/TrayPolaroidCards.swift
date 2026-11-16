import AppKit
import PockyFoundation

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
        strip.spacing = PKYLayout.Space.s4
        strip.setHuggingPriority(.defaultHigh, for: .vertical)
        return strip
    }()

    override func buildContent(in container: NSView) {
        pin(previewArea, in: container, inset: TrayMetrics.framePadding)
        pin(strip, in: container, inset: TrayMetrics.framePadding)
        previewArea.addSubview(badge)
        buildPreview(in: previewArea)
        NSLayoutConstraint.activate([
            previewArea.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: TrayMetrics.framePadding
            ),
            previewArea.bottomAnchor.constraint(
                equalTo: strip.topAnchor,
                constant: -TrayCardSizing.lineGap
            ),
            strip.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -TrayMetrics.framePadding
            ),
            badge.leadingAnchor.constraint(
                equalTo: previewArea.leadingAnchor,
                constant: PKYLayout.Space.s4
            ),
            badge.topAnchor.constraint(
                equalTo: previewArea.topAnchor,
                constant: PKYLayout.Space.s4
            ),
        ])
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        card.polaroid = true
    }

    func buildPreview(in _: NSView) {}

    func fill(_ subview: NSView, in area: NSView, top: CGFloat) {
        fill(subview, in: area, topAnchor: area.topAnchor, offset: top)
    }

    func fill(_ subview: NSView, in area: NSView, below anchor: NSView) {
        fill(subview, in: area, topAnchor: anchor.bottomAnchor, offset: TrayCardSizing.lineGap)
    }

    func showTime(_ time: String) {
        caption.font = TrayCardSizing.timeFont
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        caption.stringValue = time
    }

    private func fill(
        _ subview: NSView,
        in area: NSView,
        topAnchor: NSLayoutYAxisAnchor,
        offset: CGFloat
    ) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        area.addSubview(subview, positioned: .below, relativeTo: badge)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(
                equalTo: area.leadingAnchor,
                constant: TrayCardSizing.textInset
            ),
            subview.trailingAnchor.constraint(
                equalTo: area.trailingAnchor,
                constant: -TrayCardSizing.textInset
            ),
            subview.topAnchor.constraint(equalTo: topAnchor, constant: offset),
            subview.bottomAnchor.constraint(
                lessThanOrEqualTo: area.bottomAnchor,
                constant: -TrayCardSizing.textInset
            ),
        ])
    }
}

@MainActor
final class TextCardItem: PolaroidCardItem {
    lazy var body = label(font: TrayCardSizing.bodyFont, lines: 0)

    override func buildPreview(in area: NSView) {
        fill(body, in: area, top: TrayCardSizing.textTop)
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
        fill(domain, in: area, top: TrayCardSizing.textTop)
        fill(address, in: area, below: domain)
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
        preview.translatesAutoresizingMaskIntoConstraints = false
        return preview
    }()

    private lazy var lines: NSTextField = {
        let lines = label(font: TrayCardSizing.fileLinesFont, lines: 0)
        lines.textColor = .secondaryLabelColor
        return lines
    }()

    override func buildPreview(in area: NSView) {
        area.addSubview(preview, positioned: .below, relativeTo: badge)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            preview.topAnchor.constraint(equalTo: area.topAnchor),
            preview.bottomAnchor.constraint(equalTo: area.bottomAnchor),
        ])
        fill(lines, in: area, top: TrayCardSizing.textTop)
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
