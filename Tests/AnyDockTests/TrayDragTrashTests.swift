import AppKit
import Foundation
import Testing

@testable import AnyDock
@testable import AnyDockCore

@MainActor
private func makeTray() throws -> (ImageTrayController, [ReceivedItem], NSWindow) {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let kinds: [ReceivedKind] = [.text, .text, .link, .text]
  let items = try kinds.enumerated().map { index, kind in
    let url = folder.appendingPathComponent("AnyDock-\(index).txt")
    try "item \(index)".write(to: url, atomically: true, encoding: .utf8)
    return ReceivedItem(
      url: url, kind: kind, thumbnail: nil, receivedAt: Date(), isPlainText: false)
  }
  let tray = ImageTrayController()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 450, height: 520), styleMask: .borderless,
    backing: .buffered, defer: true)
  window.contentViewController = tray
  tray.replaceItems(items)
  tray.loadItems = { items }
  return (tray, items, window)
}

@MainActor
@Test("拖到删除区只回收被拖动的项目，并清空选择")
func droppingOnTrashRecyclesOnlyDraggedItems() async throws {
  let (tray, items, window) = try makeTray()
  defer { try? FileManager.default.removeItem(at: items[0].url.deletingLastPathComponent()) }
  var recycled: [URL] = []
  tray.recycleItems = { recycled = $0 }
  var finished = false
  tray.didFinishDragging = { finished = true }
  tray.collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
  tray.beginDrag([IndexPath(item: 1, section: 0), IndexPath(item: 3, section: 0)])
  let task = try #require(tray.trashDraggedItems())
  tray.endDrag(operation: .delete)
  await task.value
  #expect(recycled == [items[1].url, items[3].url])
  #expect(tray.collection.selectionIndexPaths.isEmpty)
  #expect(!finished)
  _ = window
}

@MainActor
@Test("拖到托盘外不回收任何项目，并照常结束拖动")
func droppingOutsideRecyclesNothing() throws {
  let (tray, items, window) = try makeTray()
  defer { try? FileManager.default.removeItem(at: items[0].url.deletingLastPathComponent()) }
  var recycled: [URL]?
  tray.recycleItems = { recycled = $0 }
  var finished = false
  tray.didFinishDragging = { finished = true }
  tray.beginDrag([IndexPath(item: 1, section: 0)])
  tray.endDrag(operation: .copy)
  #expect(tray.trashDraggedItems() == nil)
  #expect(recycled == nil)
  #expect(finished)
  _ = window
}

@MainActor
@Test("双击某类筛选只选中该类的全部卡片")
func doubleClickingFilterSelectsOnlyThatKind() throws {
  let (tray, items, window) = try makeTray()
  defer { try? FileManager.default.removeItem(at: items[0].url.deletingLastPathComponent()) }
  tray.selectAll(in: .kind(.text))
  #expect(tray.collection.selectionIndexPaths.count == items.filter { $0.kind == .text }.count)
  #expect(tray.filterBar.selected == .kind(.text))
  tray.selectAll(in: .all)
  #expect(tray.collection.selectionIndexPaths.count == items.count)
  _ = window
}
