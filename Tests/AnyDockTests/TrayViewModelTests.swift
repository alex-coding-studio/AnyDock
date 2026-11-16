import Foundation
import Testing
@testable import AnyDock
@testable import AnyDockCore

private func item(_ name: String, _ kind: ReceivedKind) -> ReceivedItem {
    ReceivedItem(
        url: URL(fileURLWithPath: "/tmp/AnyDock-\(name)"),
        kind: kind,
        thumbnail: nil,
        receivedAt: Date(),
        isPlainText: false
    )
}

@MainActor
@Test("回收只处理收件箱当前列出的项目，全都不在列表里时不调用回收")
func recyclingIsLimitedToListedItems() async {
    let listed = [item("a", .text), item("b", .image)]
    var recycled = [[URL]]()
    let model = TrayViewModel(inbox: TrayInbox(list: { listed }, recycle: { recycled.append($0) }))
    let stranger = URL(fileURLWithPath: "/tmp/elsewhere.txt")
    await model.recycle([listed[1].url, stranger])?.value
    #expect(recycled == [[listed[1].url]])
    await model.recycle([stranger])?.value
    #expect(recycled.count == 1)
    #expect(!model.isRecycling)
}

@MainActor
@Test("切换筛选后，看不到的项目不再算作选中")
func switchingFilterDropsHiddenSelection() {
    let items = [item("a", .text), item("b", .image)]
    let model = TrayViewModel(inbox: TrayInbox(list: { items }, recycle: { _ in }))
    model.replace(items)
    model.select(urls: items.map(\.url))
    model.select(.kind(.image))
    #expect(model.selectedURLs == [items[1].url])
    model.select(.all)
    #expect(model.selectedURLs == [items[1].url])
}
