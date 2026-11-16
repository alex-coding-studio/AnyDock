import CoreGraphics
import Testing
@testable import AnyDockCore

@Test("每张图放进当前最短列，等高时放左列，长图高度封顶 2.5 倍列宽")
func masonryPlacesItemsInShortestColumn() {
    let placement = MasonryLayout.frames(
        heightRatios: [1, 1, 3, 0.5],
        columns: 2,
        width: 210,
        spacing: 10
    )
    #expect(
        placement.frames == [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 110, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 110, width: 100, height: 250),
            CGRect(x: 110, y: 110, width: 100, height: 50),
        ]
    )
    #expect(placement.height == 360)
}
