import AppKit
import PockyFoundation
import SnapKit

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

    private(set) lazy var badge = BadgeView()

    private(set) lazy var dot = LatestDot()

    private lazy var check: NSImageView = {
        let check = NSImageView(
            image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                ?? NSImage()
        )
        check.symbolConfiguration = NSImage.SymbolConfiguration(
            paletteColors: [.white, .controlAccentColor]
        )
        return check
    }()

    override func loadView() {
        buildContent(in: card)
        card.addSubview(check)
        check.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(PKYLayout.Gap.content(.compact))
            make.size.equalTo(Self.checkmarkSide)
        }
        view = card
        updateSelection()
    }

    func buildContent(in _: NSView) {}

    func showThumbnail(_: NSImage) {}

    func configure(_ entry: TrayEntry, singleColumn _: Bool, time _: String, latest: Bool) {
        badge.show(entry.badge, style: entry.badgeStyle)
        dot.isHidden = !latest
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
        row.spacing = PKYLayout.Gap.content(.compact)
        row.edgeInsets = NSEdgeInsets(
            top: 0,
            left: PKYLayout.Inset.container(.compact),
            bottom: 0,
            right: PKYLayout.Inset.container(.compact)
        )
        return row
    }()

    private lazy var timeCapsule: BadgeView = {
        let capsule = BadgeView()
        capsule.show("", style: .media)
        return capsule
    }()

    override func buildContent(in container: NSView) {
        container.addSubview(placeholder)
        container.addSubview(preview)
        let row = timeRow
        let capsule = timeCapsule
        capsule.addSubview(row)
        container.addSubview(capsule)
        container.addSubview(badge)
        placeholder.snp.makeConstraints { $0.directionalHorizontalEdges.equalToSuperview() }
        preview.snp.makeConstraints { $0.edges.equalToSuperview() }
        row.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        capsule.snp.makeConstraints {
            $0.leading.bottom.equalToSuperview().inset(PKYLayout.Gap.content(.compact))
        }
        badge.snp.makeConstraints {
            $0.top.leading.equalToSuperview().inset(PKYLayout.Gap.content(.compact))
        }
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
