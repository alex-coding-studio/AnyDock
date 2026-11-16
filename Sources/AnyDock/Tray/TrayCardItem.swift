import AppKit
import PockyFoundation

@MainActor
class TrayCardItem: NSCollectionViewItem {
    private static let checkmarkSide: CGFloat = 16

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

    private(set) lazy var card: ThumbnailView = {
        let card = ThumbnailView()
        card.checkmark = check
        return card
    }()

    private(set) lazy var badge: BadgeView = {
        let badge = BadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }()

    private(set) lazy var dot = LatestDot()

    private lazy var check: NSImageView = {
        let check = NSImageView(
            image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                ?? NSImage()
        )
        check.symbolConfiguration = NSImage.SymbolConfiguration(
            paletteColors: [.white, .controlAccentColor]
        )
        check.translatesAutoresizingMaskIntoConstraints = false
        return check
    }()

    override func loadView() {
        buildContent(in: card)
        card.addSubview(check)
        NSLayoutConstraint.activate([
            check.topAnchor.constraint(equalTo: card.topAnchor, constant: PKYLayout.Space.s4),
            check.trailingAnchor.constraint(
                equalTo: card.trailingAnchor,
                constant: -PKYLayout.Space.s4
            ),
            check.widthAnchor.constraint(equalToConstant: Self.checkmarkSide),
            check.heightAnchor.constraint(equalToConstant: Self.checkmarkSide),
        ])
        view = card
        updateSelection()
    }

    func buildContent(in _: NSView) {}

    func showThumbnail(_: NSImage) {}

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

    func label(font: NSFont, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isSelectable = false
        field.font = font
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
    private static let timeFontSize: CGFloat = 9

    private lazy var placeholder: PreviewArea = {
        let placeholder = PreviewArea()
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = PKYShape.Radius.card
        return placeholder
    }()

    private lazy var preview: TopAlignedImageView = {
        let preview = TopAlignedImageView()
        preview.wantsLayer = true
        preview.layer?.cornerRadius = PKYShape.Radius.card
        preview.layer?.masksToBounds = true
        return preview
    }()

    private lazy var time: NSTextField = {
        let time = NSTextField(labelWithString: "")
        time.font = .monospacedDigitSystemFont(ofSize: Self.timeFontSize, weight: .medium)
        time.textColor = .white
        return time
    }()

    private lazy var timeRow: NSStackView = {
        let row = NSStackView(views: [dot, time])
        row.spacing = PKYLayout.Space.s4
        row.edgeInsets = NSEdgeInsets(
            top: 0,
            left: PKYLayout.Space.s4,
            bottom: 0,
            right: PKYLayout.Space.s4
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }()

    private lazy var timeCapsule: BadgeView = {
        let capsule = BadgeView()
        capsule.show("", style: .media)
        capsule.translatesAutoresizingMaskIntoConstraints = false
        return capsule
    }()

    override func buildContent(in container: NSView) {
        pin(placeholder, in: container, inset: 0)
        pin(preview, in: container, inset: 0)
        let row = timeRow
        let capsule = timeCapsule
        capsule.addSubview(row)
        container.addSubview(capsule)
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            capsule.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: PKYLayout.Space.s4
            ),
            capsule.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -PKYLayout.Space.s4
            ),
            badge.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: PKYLayout.Space.s4
            ),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: PKYLayout.Space.s4),
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

    override func showThumbnail(_ image: NSImage) {
        preview.image = image
        placeholder.isHidden = true
    }
}
