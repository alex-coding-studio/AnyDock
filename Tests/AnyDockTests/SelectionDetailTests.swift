import AppKit
import Foundation
import Testing

@testable import AnyDock
@testable import AnyDockCore

@MainActor
@Test("单选时底栏显示该项详情：长文件名只截断名字、大小和时间完整可见，图片不显示存储文件名，多选显示数量")
func singleSelectionShowsItemDetail() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let name = String(repeating: "State of California Annual Report ", count: 4) + ".pdf"
  let file = folder.appendingPathComponent("AnyDock-1-\(UUID().uuidString)-\(name)")
  try Data(repeating: 1, count: 2_000_000).write(to: file)
  let image = folder.appendingPathComponent("AnyDock-2-\(UUID().uuidString).png")
  try NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )?.representation(using: .png, properties: [:])?.write(to: image)
  let tray = ImageTrayController()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 450, height: 520), styleMask: .borderless,
    backing: .buffered, defer: true)
  window.contentViewController = tray
  tray.replaceItems([
    ReceivedItem(url: file, kind: .file, thumbnail: nil, receivedAt: Date(), isPlainText: false),
    ReceivedItem(url: image, kind: .image, thumbnail: nil, receivedAt: Date(), isPlainText: false),
  ])
  let zone = tray.dropZone

  tray.collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
  tray.collection.selectionChanged?()
  tray.view.layoutSubtreeIfNeeded()
  let row = try #require(zone.label.superview)
  let suffix = row.convert(zone.suffix.alignmentRect(forFrame: zone.suffix.frame), to: zone)
  let label = row.convert(zone.label.alignmentRect(forFrame: zone.label.frame), to: zone)
  #expect(zone.label.stringValue.hasPrefix("State of California"))
  #expect(suffix.width >= zone.suffix.intrinsicContentSize.width - 0.5)
  #expect(label.width < zone.label.intrinsicContentSize.width)
  #expect(zone.bounds.contains(suffix.insetBy(dx: 1, dy: 1)))
  #expect(label.maxX <= suffix.minX + 1)
  #expect(zone.window != nil && !zone.isHiddenOrHasHiddenAncestor)

  tray.collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
  tray.collection.selectionChanged?()
  let shown = zone.label.stringValue + zone.suffix.stringValue
  #expect(!shown.contains(image.deletingPathExtension().lastPathComponent))
  #expect(shown.contains("PNG"))

  tray.collection.selectionIndexPaths = [
    IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0),
  ]
  tray.collection.selectionChanged?()
  #expect(zone.label.stringValue.contains("2") && zone.suffix.isHidden)

  tray.collection.selectionIndexPaths = []
  tray.collection.selectionChanged?()
  #expect(zone.isHiddenOrHasHiddenAncestor)
  withExtendedLifetime(window) {}
}
