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
    let model = TrayViewModel(inbox: TestInbox(list: { listed }, recycle: { recycled.append($0) }))
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
    let model = TrayViewModel(inbox: TestInbox(list: { items }))
    model.replace(items)
    model.select(urls: items.map(\.url))
    model.select(.kind(.image))
    #expect(model.selectedURLs == [items[1].url])
    model.select(.all)
    #expect(model.selectedURLs == [items[1].url])
}

@MainActor
@Test("托盘 view model 自己订阅收件箱：重列结果替换列表，新收到的项目排在最前并标为最新")
func viewModelFollowsInboxEvents() {
    let inbox = TestInbox()
    let model = TrayViewModel(inbox: inbox)
    let listed = [item("a", .text), item("b", .image)]
    inbox.itemsSubject.send(listed)
    #expect(model.contents.items.map(\.url) == listed.map(\.url))
    let arrival = item("c", .link)
    inbox.receivedSubject.send(arrival)
    #expect(model.contents.items.first?.url == arrival.url)
    #expect(model.latestURL == arrival.url)
}

@MainActor
@Test("新图片先提供即时预览，列表和自动复制仅收到元数据")
func imageArrivalPublishesPreviewBeforeMetadata() {
    let inbox = TestInbox()
    let model = TrayViewModel(inbox: inbox)
    var image = item("arrival.png", .image)
    let payload = Data([1, 2, 3])
    image.thumbnail = payload
    var previews = [Data]()
    let preview = model.incomingThumbnails.sink {
        #expect($0.url == image.url)
        previews.append($0.data)
    }
    var arrivals = [ReceivedItem]()
    let arrival = model.arrivals.sink { item in
        #expect(previews == [payload])
        arrivals.append(item)
    }
    defer {
        preview.cancel()
        arrival.cancel()
    }
    inbox.receivedSubject.send(image)
    #expect(model.contents.items.count == 1)
    #expect(model.contents.items.first?.thumbnail == nil)
    #expect(arrivals.map(\.url) == [image.url])
    #expect(arrivals.first?.thumbnail == nil)
}
