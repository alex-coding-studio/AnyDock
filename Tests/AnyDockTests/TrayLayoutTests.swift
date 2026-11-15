import AppKit
import Foundation
import Testing

@testable import AnyDock
@testable import AnyDockCore

@MainActor
private func makeTray(texts: [String]) throws -> (ImageTrayController, NSWindow) {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  var items = try texts.enumerated().map { index, text in
    let url = folder.appendingPathComponent("AnyDock-\(index).txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return ReceivedItem(
      url: url, kind: .text, thumbnail: nil, receivedAt: Date(), isPlainText: false)
  }
  let link = folder.appendingPathComponent("AnyDock-link.webloc")
  try PropertyListSerialization.data(
    fromPropertyList: ["URL": "https://example.com/a"], format: .xml, options: 0
  ).write(to: link)
  items.append(
    ReceivedItem(url: link, kind: .link, thumbnail: nil, receivedAt: Date(), isPlainText: false))
  let tray = ImageTrayController()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 450, height: 520), styleMask: .borderless,
    backing: .buffered, defer: true)
  window.contentViewController = tray
  window.setContentSize(NSSize(width: 450, height: 520))
  tray.replaceItems(items)
  return (tray, window)
}

@MainActor
private func settle(_ tray: ImageTrayController) {
  tray.view.layoutSubtreeIfNeeded()
  tray.collection.layoutSubtreeIfNeeded()
  for item in tray.collection.visibleItems() { item.view.layoutSubtreeIfNeeded() }
}

@MainActor
private func cards(_ tray: ImageTrayController) -> [(TextCardItem, NSRect)] {
  tray.collection.visibleItems().compactMap { item in
    guard let card = item as? TextCardItem else { return nil }
    return (card, card.view.convert(card.view.bounds, to: tray.view))
  }
}

@MainActor
@Test("卡片留在托盘左右边距之内，胶囊栏与卡片左对齐且不遮挡第一排，文本和字数在卡片内")
func textCardsStayInsideTrayMargins() throws {
  let long = String(repeating: "随手坞把手机上的文字发到 Mac。", count: 20)
  for filter in [TrayFilter.all, .kind(.text)] {
    let (tray, window) = try makeTray(texts: [long, "短文本", long])
    settle(tray)
    tray.select(filter)
    settle(tray)
    let bounds = tray.view.bounds
    let bar = tray.filterBar.convert(tray.filterBar.bounds, to: tray.view)
    let visible = cards(tray)
    #expect(!visible.isEmpty)
    let leftmost = visible.map(\.1.minX).min() ?? 0
    #expect(abs(bar.minX - leftmost) < 1)
    #expect(abs((bounds.maxY - bar.maxY) - bar.minX) < 1)
    for (card, frame) in visible {
      #expect(frame.minX >= bar.minX - 1)
      #expect(abs((bounds.maxX - frame.maxX) - bar.minX) < 1 || filter == .all)
      #expect(frame.maxX <= bounds.maxX - bar.minX + 1)
      #expect(frame.maxY <= bar.minY - 1)
      let body = card.body.frame
      #expect(body.minX >= 0 && body.maxX <= card.view.bounds.maxX)
      #expect(abs(body.minX - (card.view.bounds.maxX - body.maxX)) < 1)
      let capsule = try #require(card.card.timeCapsule).frame
      #expect(abs(capsule.minX - capsule.minY) < 1)
      if filter == .kind(.text) {
        #expect(!card.count.isHidden && !card.count.stringValue.isEmpty)
        #expect(card.count.frame.maxX <= card.view.bounds.maxX)
        #expect(card.count.frame.minX >= capsule.maxX)
      }
    }
    withExtendedLifetime(window) {}
  }
}
