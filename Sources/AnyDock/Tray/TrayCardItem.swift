import AppKit

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
            check.widthAnchor.constraint(equalToConstant: Self.checkmarkSide),
            check.heightAnchor.constraint(equalToConstant: Self.checkmarkSide),
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

    private static let timeFontSize: CGFloat = 9

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
        time.font = .monospacedDigitSystemFont(ofSize: Self.timeFontSize, weight: .medium)
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
