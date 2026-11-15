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
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 520), styleMask: .borderless,
    backing: .buffered, defer: true)
  window.contentViewController = tray
  window.setContentSize(NSSize(width: 480, height: 520))
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
private func cards(_ tray: ImageTrayController) -> [(TrayCardItem, NSRect)] {
  tray.collection.visibleItems().compactMap { item in
    guard let card = item as? TrayCardItem else { return nil }
    return (card, card.view.convert(card.view.bounds, to: tray.view))
  }
}

@MainActor
@Test("筛选栏与卡片左对齐且不遮挡第一排，卡片在内容区内，扩展名标签在卡片左上角")
func cardsStayInsideTrayMarginsWithBadgesAtTopLeft() throws {
  let long = String(repeating: "随手坞把手机上的文字发到 Mac。", count: 20)
  for filter in [TrayFilter.all, .kind(.text)] {
    let (tray, window) = try makeTray(texts: [long, "短文本", long])
    settle(tray)
    tray.select(filter)
    settle(tray)
    let bounds = tray.view.bounds
    let bar = tray.filterBar.convert(tray.filterBar.bounds, to: tray.view)
    let visible = cards(tray)
    #expect(visible.count == (filter == .all ? 4 : 3))
    let leftmost = visible.map(\.1.minX).min() ?? 0
    #expect(abs(bar.minX - leftmost) < 1)
    #expect(abs((bounds.maxY - bar.maxY) - bar.minX) < 1)
    #expect(bar.maxX <= bounds.maxX - bar.minX + 1)
    for (card, frame) in visible {
      #expect(frame.minX >= bar.minX - 1)
      #expect(frame.maxX <= bounds.maxX - bar.minX + 1)
      #expect(frame.maxY <= bar.minY - 1)
      if filter == .kind(.text) {
        #expect(abs((bounds.maxX - frame.maxX) - bar.minX) < 1)
      }
      let badge = card.badge.convert(card.badge.bounds, to: card.view)
      let cardBounds = card.view.bounds
      #expect(badge.width > 0 && badge.height > 0)
      #expect(abs(badge.minX - (cardBounds.maxY - badge.maxY)) < 1)
      #expect(badge.minX < cardBounds.midX && badge.maxY > cardBounds.midY)
      guard let polaroid = card as? PolaroidCardItem else { continue }
      let caption = polaroid.caption.convert(polaroid.caption.bounds, to: card.view)
      let preview = polaroid.previewArea.frame
      #expect(cardBounds.contains(caption.insetBy(dx: 1, dy: 1)))
      #expect(caption.maxY <= preview.minY + 1)
      #expect(abs(preview.minX - (cardBounds.maxX - preview.maxX)) < 1)
      if let link = card as? LinkCardItem {
        let domain = link.domain.convert(link.domain.bounds, to: card.view)
        let address = link.address.convert(link.address.bounds, to: card.view)
        #expect(domain.height > 0 && !link.domain.stringValue.isEmpty)
        #expect(domain.minY >= address.maxY - 1)
      }
      if let text = card as? TextCardItem {
        #expect(preview.contains(text.body.frame.offsetBy(dx: preview.minX, dy: preview.minY)))
        #expect(polaroid.caption.stringValue.rangeOfCharacter(from: .decimalDigits) != nil)
      }
    }
    withExtendedLifetime(window) {}
  }
}

@MainActor
@Test("选中胶囊跟随当前筛选移动到对应分段")
func scopeIndicatorFollowsSelection() async throws {
  let (tray, window) = try makeTray(texts: ["一", "二"])
  settle(tray)
  #expect(tray.filterBar.selectedButtonFrame == tray.filterBar.indicatorFrame)
  tray.select(.kind(.link))
  settle(tray)
  try await Task.sleep(for: .milliseconds(400))
  let expected = try #require(tray.filterBar.selectedButtonFrame)
  #expect(abs(tray.filterBar.indicatorFrame.minX - expected.minX) < 1)
  #expect(abs(tray.filterBar.indicatorFrame.width - expected.width) < 1)
  withExtendedLifetime(window) {}
}

@MainActor
private func frame(of view: NSView?, in tray: ImageTrayController) throws -> NSRect {
  let view = try #require(view)
  return view.convert(view.bounds, to: tray.view)
}

@MainActor
@Test("顶行筛选栏与按钮组互不重叠且都在托盘内")
func filterBarAndControlGroupShareTopRow() throws {
  let (tray, window) = try makeTray(texts: ["一", "二"])
  settle(tray)
  let bounds = tray.view.bounds
  let bar = try frame(of: tray.filterBar, in: tray)
  let group = try frame(of: tray.controlGroup, in: tray)
  #expect(!bar.intersects(group))
  #expect(bar.maxX < group.minX)
  #expect(bounds.contains(bar))
  #expect(bounds.contains(group))
  #expect(abs(bar.midY - group.midY) < 1)
  withExtendedLifetime(window) {}
}

@MainActor
@Test("选中详情胶囊浮在剪贴板条上方，出现和消失都不改变内容区")
func floatingDetailLeavesContentFrameUnchanged() throws {
  let (tray, window) = try makeTray(texts: ["一", "二"])
  tray.replaceClips([ClipboardClip(text: "clip", copiedAt: Date())])
  settle(tray)
  let scroll = try #require(tray.collection.enclosingScrollView)
  let before = scroll.frame
  #expect(tray.dropZoneSurface?.isHidden == true)
  tray.collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
  tray.collection.selectionChanged?()
  settle(tray)
  #expect(tray.dropZoneSurface?.isHidden == false)
  #expect(scroll.frame == before)
  let pill = try frame(of: tray.dropZoneSurface, in: tray)
  let clipboard = try frame(of: tray.clipboardSurface, in: tray)
  #expect(pill.minY >= clipboard.maxY)
  #expect(abs(pill.midX - tray.view.bounds.midX) < 1)
  tray.clearSelection()
  settle(tray)
  #expect(tray.dropZoneSurface?.isHidden == true)
  #expect(scroll.frame == before)
  withExtendedLifetime(window) {}
}

@MainActor
@Test("滚到底时最后一张卡片完整露在剪贴板条和选中胶囊上方")
func lastCardClearsBottomControlsWhenScrolledToEnd() throws {
  let (tray, window) = try makeTray(texts: (0..<24).map { "第 \($0) 条" })
  tray.replaceClips([ClipboardClip(text: "clip", copiedAt: Date())])
  tray.clipboardBar.setExpanded(true, animated: false)
  tray.collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
  tray.collection.selectionChanged?()
  settle(tray)
  let scroll = try #require(tray.collection.enclosingScrollView)
  let documentHeight = tray.collection.frame.height
  let visibleHeight = scroll.contentView.bounds.height
  #expect(documentHeight > visibleHeight)
  scroll.contentView.scroll(to: NSPoint(x: 0, y: documentHeight - visibleHeight))
  scroll.reflectScrolledClipView(scroll.contentView)
  settle(tray)
  let lowest = try #require(cards(tray).map(\.1).min { $0.minY < $1.minY })
  let clipboard = try frame(of: tray.clipboardSurface, in: tray)
  let pill = try frame(of: tray.dropZoneSurface, in: tray)
  #expect(lowest.minY >= clipboard.maxY)
  #expect(lowest.minY >= pill.maxY)
  withExtendedLifetime(window) {}
}
