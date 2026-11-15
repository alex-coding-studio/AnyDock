import AppKit
import Foundation
import Testing

@testable import AnyDock
@testable import AnyDockCore

@MainActor
@Test(
  "PDF 卡片在缩略图生成后显示首页，文件名缺少扩展名时按文件头识别并显示 PDF 标签",
  arguments: [
    "AnyDock-1-report.pdf", "AnyDock-1-00000000-0000-0000-0000-000000000000-SECRETARY OF STATE",
  ])
func pdfCardShowsFirstPageThumbnail(filename: String) async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let url = folder.appendingPathComponent(filename)
  let data = NSMutableData()
  var box = CGRect(x: 0, y: 0, width: 612, height: 792)
  let consumer = try #require(CGDataConsumer(data: data))
  let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
  context.beginPDFPage(nil)
  context.setFillColor(NSColor.systemRed.cgColor)
  context.fill(CGRect(x: 50, y: 50, width: 400, height: 600))
  context.endPDFPage()
  context.closePDF()
  try (data as Data).write(to: url)
  let tray = ImageTrayController()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 520), styleMask: .borderless,
    backing: .buffered, defer: true)
  window.contentViewController = tray
  tray.replaceItems([
    ReceivedItem(url: url, kind: .file, thumbnail: nil, receivedAt: Date(), isPlainText: false)
  ])
  tray.view.layoutSubtreeIfNeeded()
  tray.collection.layoutSubtreeIfNeeded()
  let card = try #require(tray.collection.visibleItems().first as? FileCardItem)
  let placeholder = card.preview.image
  var current = placeholder
  for _ in 0..<50 where current === placeholder {
    try await Task.sleep(for: .milliseconds(100))
    current = (tray.collection.visibleItems().first as? FileCardItem)?.preview.image
  }
  #expect(current !== placeholder)
  #expect(
    TrayEntry(
      item: ReceivedItem(
        url: url, kind: .file, thumbnail: nil, receivedAt: Date(), isPlainText: false)
    ).badge == "PDF")
  withExtendedLifetime(window) {}
}
