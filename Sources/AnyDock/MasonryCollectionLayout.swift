import AnyDockCore
import AppKit

final class MasonryCollectionLayout: NSCollectionViewLayout {
  static let margin = Space.s24
  private static let spacing = Space.s12
  private static let bottomInset: CGFloat = 64

  var columnCount = 3 {
    didSet {
      if columnCount != oldValue {
        invalidateLayout()
      }
    }
  }

  var topInset: CGFloat = 24 {
    didSet {
      if topInset != oldValue {
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

  var aspectRatio: (IndexPath) -> CGFloat = { _ in 1 }

  private var attributes: [NSCollectionViewLayoutAttributes] = []
  private var contentSize = CGSize.zero
  private var preparedWidth: CGFloat = 0

  override init() {
    super.init()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
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
    let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
    let indexPaths = (0..<count).map { IndexPath(item: $0, section: 0) }
    let placement = MasonryLayout.frames(
      heightRatios: indexPaths.map(aspectRatio),
      columns: columnCount,
      width: width - Self.margin * 2,
      spacing: Self.spacing
    )
    attributes = zip(indexPaths, placement.frames).map { indexPath, frame in
      let item = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
      item.frame = collectionView.backingAlignedRect(
        frame.offsetBy(dx: Self.margin, dy: topInset), options: .alignAllEdgesNearest)
      return item
    }
    contentSize = CGSize(
      width: width,
      height: topInset + placement.height + Self.bottomInset + extraBottomInset)
  }

  var availableWidth: CGFloat {
    max(preparedWidth - Self.margin * 2, 0)
  }

  override var collectionViewContentSize: NSSize {
    contentSize
  }

  override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
    attributes.filter { $0.frame.intersects(rect) }
  }

  override func layoutAttributesForItem(at indexPath: IndexPath)
    -> NSCollectionViewLayoutAttributes?
  {
    guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else {
      return nil
    }
    return attributes[indexPath.item]
  }

  override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
    abs(newBounds.width - preparedWidth) > 0.5
  }
}
