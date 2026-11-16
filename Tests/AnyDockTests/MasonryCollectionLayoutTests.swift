import AppKit
import Testing
@testable import AnyDock

@MainActor
@Test("瀑布流保持高宽比方向、最短列和长图封顶，无效比例使用正方形")
func masonryPlacesItemsInShortestColumn() throws {
    let ratios: [CGFloat] = [1, 1, 3, 0.5, .nan, .infinity, 0, -1]
    let source = MasonryItems(count: ratios.count)
    defer { withExtendedLifetime(source) {} }
    let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
    let layout = MasonryCollectionLayout { ratios[$0.item] }
    layout.columnCount = 2
    collection.collectionViewLayout = layout
    collection.dataSource = source
    collection.reloadData()
    layout.prepare()
    let frames = try ratios.indices.map { index in
        try #require(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
    }
    #expect(frames[0].minX < frames[1].minX)
    #expect(frames[0].minY == frames[1].minY)
    #expect(frames[2].minX == frames[0].minX)
    #expect(frames[2].minY > frames[0].minY)
    #expect(frames[2].height > frames[2].width)
    #expect(frames[2].height < frames[2].width * ratios[2])
    #expect(frames[3].minX == frames[1].minX)
    #expect(frames[3].height < frames[3].width)
    for frame in frames.dropFirst(4) {
        #expect(frame.height == frame.width)
    }
}

@MainActor
private final class MasonryItems: NSObject, NSCollectionViewDataSource {
    private let count: Int

    init(count: Int) {
        self.count = count
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        count
    }

    func collectionView(
        _: NSCollectionView,
        itemForRepresentedObjectAt _: IndexPath
    ) -> NSCollectionViewItem {
        NSCollectionViewItem()
    }
}
