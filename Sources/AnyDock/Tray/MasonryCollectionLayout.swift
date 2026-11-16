import AnyDockCore
import AppKit

final class MasonryCollectionLayout: NSCollectionViewLayout {
    private static let widthChangeTolerance: CGFloat = 0.5

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    var columnCount = TrayMetrics.multiColumnCount {
        didSet {
            if columnCount != oldValue {
                invalidateLayout()
            }
        }
    }

    var extraBottomInset: CGFloat = 0 {
        didSet {
            if extraBottomInset != oldValue {
                invalidateLayout()
            }
        }
    }

    private let aspectRatio: (IndexPath) -> CGFloat

    private var attributes = [NSCollectionViewLayoutAttributes]()
    private var contentSize = CGSize.zero
    private var preparedWidth: CGFloat = 0

    var availableWidth: CGFloat {
        max(preparedWidth - TrayMetrics.margin * 2, 0)
    }

    var columnWidth: CGFloat {
        let columns = CGFloat(max(columnCount, 1))
        return max((availableWidth - TrayMetrics.cardSpacing * (columns - 1)) / columns, 0)
    }

    init(aspectRatio: @escaping (IndexPath) -> CGFloat) {
        self.aspectRatio = aspectRatio
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else {
            attributes = []
            contentSize = .zero
            return
        }
        let width =
            collectionView.enclosingScrollView?.contentView.bounds.width
                ?? collectionView.bounds.width
        preparedWidth = width
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(
            inSection: 0
        ) : 0
        let indexPaths = (0 ..< count).map { IndexPath(item: $0, section: 0) }
        let placement = MasonryLayout.frames(
            heightRatios: indexPaths.map(aspectRatio),
            columns: columnCount,
            width: width - TrayMetrics.margin * 2,
            spacing: TrayMetrics.cardSpacing
        )
        attributes = zip(indexPaths, placement.frames).map { indexPath, frame in
            let item = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            item.frame = collectionView.backingAlignedRect(
                frame.offsetBy(dx: TrayMetrics.margin, dy: TrayMetrics.contentTopInset),
                options: .alignAllEdgesNearest
            )
            return item
        }
        contentSize = CGSize(
            width: width,
            height: TrayMetrics.contentTopInset + placement.height
                + TrayMetrics.floatingControlsClearance + extraBottomInset
        )
    }

    override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath)
        -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else {
            return nil
        }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - preparedWidth) > Self.widthChangeTolerance
    }
}
