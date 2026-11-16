import AppKit
import Foundation
import Testing
@testable import AnyDock
@testable import AnyDockCore

@MainActor
@Test(
    "单选旧文本、无扩展名文件、带扩展名文件、图片、链接时，底栏详情文字完整显示且没有多余分隔符",
    arguments: ["text", "bare", "file", "image", "link"]
)
func singleSelectionDetailIsVisibleForEveryKind(kind: String) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = Date(timeIntervalSinceNow: -86400 * 3)
    let prefix = "AnyDock-1-\(UUID().uuidString)-"
    let item: ReceivedItem
    switch kind {
    case "text":
        let url = folder.appendingPathComponent("AnyDock-1-\(UUID().uuidString).txt")
        try "旧文本内容".write(to: url, atomically: true, encoding: .utf8)
        item = ReceivedItem(
            url: url,
            kind: .text,
            thumbnail: nil,
            receivedAt: old,
            isPlainText: false
        )
    case "bare", "file":
        let url = folder.appendingPathComponent(
            prefix + (kind == "bare" ? "SECRETARY OF STATE" : "report.pdf")
        )
        try Data("%PDF-1.4".utf8).write(to: url)
        item = ReceivedItem(
            url: url,
            kind: .file,
            thumbnail: nil,
            receivedAt: old,
            isPlainText: false
        )
    case "image":
        let url = folder.appendingPathComponent(prefix + "photo.png")
        try Data(repeating: 1, count: 1200).write(to: url)
        item = ReceivedItem(
            url: url,
            kind: .image,
            thumbnail: nil,
            receivedAt: old,
            isPlainText: false
        )
    default:
        let url = folder.appendingPathComponent(prefix + "link.webloc")
        try PropertyListSerialization.data(
            fromPropertyList: ["URL": "https://www.cnn.com/"],
            format: .xml,
            options: 0
        ).write(to: url)
        item = ReceivedItem(
            url: url,
            kind: .link,
            thumbnail: nil,
            receivedAt: old,
            isPlainText: false
        )
    }
    let tray = makeTestTray()
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: TrayMetrics.popoverSize),
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )
    window.contentViewController = tray
    tray.replaceItems([item])
    tray.collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
    tray.collection.selectionChanged?()
    tray.view.layoutSubtreeIfNeeded()
    let zone = tray.dropZone
    let shown = zone.label.stringValue + (zone.suffix.isHidden ? "" : zone.suffix.stringValue)
    #expect(!zone.isHiddenOrHasHiddenAncestor)
    #expect(!zone.label.stringValue.isEmpty)
    #expect(!shown.hasPrefix(" ") && !shown.hasPrefix("·") && !shown.contains("·  ·"))
    #expect(!shown.contains(prefix))
    #expect(!(zone.superview?.hasAmbiguousLayout ?? true))
    #expect(zone.label.frame.width >= zone.label.intrinsicContentSize.width - 0.5)
    withExtendedLifetime(window) {}
}
