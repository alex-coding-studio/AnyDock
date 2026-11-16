import AnyDockCore
import AppKit
import UniformTypeIdentifiers

struct TrayEntry {
    private static let textPreviewCharacters = 1000
    private static let textPrefixBytes = 8192

    let item: ReceivedItem
    var thumbnail: NSImage?
    let text: String?
    let link: URL?
    let size: Int64?
    let contentType: UTType?

    var url: URL {
        item.url
    }

    var kind: ReceivedKind {
        item.kind
    }

    var fullText: String {
        (try? String(contentsOf: item.url, encoding: .utf8)) ?? text ?? ""
    }

    var characterCount: Int {
        fullText.count
    }

    var displayName: String {
        let name = url.lastPathComponent
        let pattern = #"^AnyDock-\d+-[0-9A-Fa-f-]{36}-"#
        guard let range = name.range(of: pattern, options: .regularExpression) else {
            return name
        }
        return String(name[range.upperBound...])
    }

    var badge: String {
        switch kind {
        case .text: return "TEXT"
        case .link: return "URL"
        case .image, .file:
            let suffix =
                url.pathExtension.isEmpty
                    ? contentType?.preferredFilenameExtension ?? "" : url.pathExtension
            return suffix.isEmpty ? L10n.text("File").uppercased() : suffix.uppercased()
        }
    }

    var badgeStyle: BadgeView.Style {
        switch kind {
        case .image: .media
        case .text: .solid(.systemGray)
        case .link: .solid(.systemBlue)
        case .file:
            if contentType?.conforms(to: .pdf) == true {
                .solid(.systemRed)
            } else if item.isPlainText {
                .solid(NSColor(white: 0.3, alpha: 1))
            } else {
                .neutral
            }
        }
    }

    var summary: String {
        switch kind {
        case .image: L10n.text("Image")
        case .text: text.map { String($0.prefix(80)) } ?? L10n.text("Text")
        case .link: link?.absoluteString ?? L10n.text("Link")
        case .file: displayName
        }
    }

    init(item: ReceivedItem) {
        self.item = item
        var thumbnail: NSImage?
        var text: String?
        var link: URL?
        var size: Int64?
        var contentType = UTType(filenameExtension: item.url.pathExtension)
        if item.kind == .image || item.kind == .file {
            size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(\.self)
                .map(Int64.init)
        }
        switch item.kind {
        case .image:
            break
        case .text:
            let handle = try? FileHandle(forReadingFrom: item.url)
            let prefix = (try? handle?.read(upToCount: Self.textPrefixBytes)) ?? Data()
            try? handle?.close()
            var decoded = String(decoding: prefix, as: UTF8.self)
            if prefix.count == Self.textPrefixBytes, decoded.last == "\u{FFFD}" {
                decoded.removeLast()
            }
            text = String(decoded.prefix(Self.textPreviewCharacters))
        case .link:
            if let data = try? Data(contentsOf: item.url),
               let property = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let address = (property as? [String: Any])?["URL"] as? String {
                link = URL(string: address)
            }
        case .file:
            let handle = try? FileHandle(forReadingFrom: item.url)
            let prefix = (try? handle?.read(upToCount: 4096)) ?? Data()
            try? handle?.close()
            if item.url.pathExtension.isEmpty, prefix.starts(with: Data("%PDF-".utf8)) {
                contentType = .pdf
            }
            thumbnail =
                contentType.map { NSWorkspace.shared.icon(for: $0) }
                    ?? NSWorkspace.shared.icon(forFile: item.url.path)
            if item.isPlainText {
                text = String(decoding: prefix, as: UTF8.self)
            }
        }
        self.thumbnail = thumbnail
        self.text = text
        self.link = link
        self.size = size
        self.contentType = contentType
    }
}

@MainActor
final class BadgeView: NSView {
    enum Style {
        case solid(NSColor)
        case neutral
        case media
    }

    private let label = NSTextField(labelWithString: "")
    private var style = Style.neutral

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 2, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: TrayMetrics.badgeHeight),
        ])
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

    func show(_ text: String, style: Style) {
        label.stringValue = text
        self.style = style
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case let .solid(color):
                layer?.backgroundColor = color.cgColor
                label.textColor = .white
            case .neutral:
                layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
                label.textColor = .secondaryLabelColor
            case .media:
                layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
                label.textColor = .white
            }
        }
    }
}

@MainActor
final class LatestDot: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TrayMetrics.dot),
            heightAnchor.constraint(equalToConstant: TrayMetrics.dot),
        ])
        layer?.cornerRadius = TrayMetrics.dot / 2
        updateColors()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}

@MainActor
class TrayCardItem: NSCollectionViewItem {
    override var isSelected: Bool {
        didSet { updateSelection() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelection() }
    }

    override var draggingImageComponents: [NSDraggingImageComponent] {
        guard let snapshot = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return super.draggingImageComponents
        }
        view.cacheDisplay(in: view.bounds, to: snapshot)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(snapshot)
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = image
        component.frame = view.bounds
        return [component]
    }

    let card = ThumbnailView()
    let badge = BadgeView()
    let dot = LatestDot()

    override func loadView() {
        let check = NSImageView(
            image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                ?? NSImage()
        )
        check.symbolConfiguration = NSImage.SymbolConfiguration(
            paletteColors: [.white, .controlAccentColor]
        )
        check.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        buildContent(in: card)
        card.addSubview(check)
        NSLayoutConstraint.activate([
            check.topAnchor.constraint(equalTo: card.topAnchor, constant: Space.s4),
            check.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Space.s4),
            check.widthAnchor.constraint(equalToConstant: 16),
            check.heightAnchor.constraint(equalToConstant: 16),
        ])
        card.checkmark = check
        view = card
        updateSelection()
    }

    func buildContent(in _: NSView) {}

    func configure(_ entry: TrayEntry, singleColumn _: Bool, time _: String, latest: Bool) {
        badge.show(entry.badge, style: entry.badgeStyle)
        dot.isHidden = !latest
    }

    func pin(_ subview: NSView, in container: NSView, inset: CGFloat) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            subview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
        ])
    }

    func label(size: CGFloat, weight: NSFont.Weight = .regular, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isSelectable = false
        field.font = .systemFont(ofSize: size, weight: weight)
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingMiddle : .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func updateSelection() {
        guard isViewLoaded else {
            return
        }
        card.selected =
            highlightState == .forSelection || (isSelected && highlightState != .forDeselection)
    }
}

@MainActor
final class ImageCardItem: TrayCardItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCard")

    private let placeholder = PreviewArea()
    private let preview = TopAlignedImageView()
    private let time = NSTextField(labelWithString: "")

    override func buildContent(in container: NSView) {
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = TrayMetrics.cornerRadius
        pin(placeholder, in: container, inset: 0)
        preview.wantsLayer = true
        preview.layer?.cornerRadius = TrayMetrics.cornerRadius
        preview.layer?.masksToBounds = true
        pin(preview, in: container, inset: 0)
        time.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        time.textColor = .white
        let row = NSStackView(views: [dot, time])
        row.spacing = Space.s4
        row.edgeInsets = NSEdgeInsets(top: 0, left: Space.s4, bottom: 0, right: Space.s4)
        let capsule = BadgeView()
        capsule.show("", style: .media)
        capsule.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(row)
        container.addSubview(capsule)
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            capsule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Space.s4),
            capsule.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Space.s4),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Space.s4),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: Space.s4),
        ])
        imageView = preview
        textField = time
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        card.polaroid = false
        preview.image = entry.thumbnail
        placeholder.isHidden = false
        self.time.stringValue = time
    }

    func showThumbnail(_ image: NSImage) {
        preview.image = image
        placeholder.isHidden = true
    }
}

@MainActor
class PolaroidCardItem: TrayCardItem {
    let previewArea = PreviewArea()
    let caption = NSTextField(labelWithString: "")

    override func buildContent(in container: NSView) {
        previewArea.wantsLayer = true
        previewArea.layer?.cornerRadius = TrayMetrics.innerCornerRadius
        previewArea.layer?.masksToBounds = true
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.lineBreakMode = .byTruncatingMiddle
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        caption.setContentCompressionResistancePriority(.required, for: .vertical)
        let strip = NSStackView(views: [dot, caption])
        strip.spacing = Space.s4
        pin(previewArea, in: container, inset: TrayMetrics.framePadding)
        pin(strip, in: container, inset: TrayMetrics.framePadding)
        previewArea.addSubview(badge)
        buildPreview(in: previewArea)
        NSLayoutConstraint.activate([
            previewArea.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: TrayMetrics.framePadding
            ),
            previewArea.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -Space.s4),
            strip.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -TrayMetrics.framePadding
            ),
            badge.leadingAnchor.constraint(equalTo: previewArea.leadingAnchor, constant: Space.s4),
            badge.topAnchor.constraint(equalTo: previewArea.topAnchor, constant: Space.s4),
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
        fill(subview, in: area, topAnchor: anchor.bottomAnchor, offset: Space.s4)
    }

    func showTime(_ time: String) {
        caption.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
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
            subview.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: Space.s8),
            subview.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -Space.s8),
            subview.topAnchor.constraint(equalTo: topAnchor, constant: offset),
            subview.bottomAnchor.constraint(
                lessThanOrEqualTo: area.bottomAnchor,
                constant: -Space.s8
            ),
        ])
    }
}

@MainActor
final class TextCardItem: PolaroidCardItem {
    static let identifier = NSUserInterfaceItemIdentifier("TextCard")

    lazy var body = label(size: 12, lines: 0)

    override func buildPreview(in area: NSView) {
        fill(body, in: area, top: Space.s24)
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        body.stringValue = entry.text ?? ""
        showTime(time)
    }
}

@MainActor
final class LinkCardItem: PolaroidCardItem {
    static let identifier = NSUserInterfaceItemIdentifier("LinkCard")

    lazy var domain = label(size: 13, weight: .bold, lines: 1)
    lazy var address = label(size: 11, lines: 0)

    override func buildPreview(in area: NSView) {
        address.textColor = .secondaryLabelColor
        domain.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        fill(domain, in: area, top: Space.s24)
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
    static let identifier = NSUserInterfaceItemIdentifier("FileCard")

    let preview = NSImageView()

    private lazy var lines = label(size: 9, lines: 0)

    override func buildPreview(in area: NSView) {
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.translatesAutoresizingMaskIntoConstraints = false
        area.addSubview(preview, positioned: .below, relativeTo: badge)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            preview.topAnchor.constraint(equalTo: area.topAnchor),
            preview.bottomAnchor.constraint(equalTo: area.bottomAnchor),
        ])
        lines.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        lines.textColor = .secondaryLabelColor
        fill(lines, in: area, top: Space.s24)
    }

    override func configure(_ entry: TrayEntry, singleColumn: Bool, time: String, latest: Bool) {
        super.configure(entry, singleColumn: singleColumn, time: time, latest: latest)
        let plainText = entry.item.isPlainText
        preview.isHidden = plainText
        lines.isHidden = !plainText
        preview.image = plainText ? nil : entry.thumbnail
        lines.stringValue = plainText ? entry.text ?? "" : ""
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = .labelColor
        caption.lineBreakMode = .byTruncatingMiddle
        caption.stringValue = entry.displayName
    }

    func showThumbnail(_ image: NSImage) {
        guard !preview.isHidden else {
            return
        }
        preview.image = image
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
        layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    }
}

@MainActor
final class TopAlignedImageView: NSImageView {
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
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
}

@MainActor
final class ThumbnailView: NSView {
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
        wantsLayer = true
        layer?.cornerRadius = TrayMetrics.cornerRadius
        updateColors()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor =
                polaroid
                    ? (dark ? NSColor(white: 0.24, alpha: 1) : NSColor(
                        white: 0.985,
                        alpha: 1
                    )).cgColor : nil
            layer?.borderWidth = selected ? 2 : (polaroid ? 0.5 : 0)
            layer?.borderColor =
                (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = polaroid ? (dark ? 0.35 : 0.14) : 0
            layer?.shadowRadius = Space.s4
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            checkmark?.isHidden = !selected
        }
    }
}
