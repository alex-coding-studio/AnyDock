import AppKit
import Foundation
import Testing
@testable import AnyDock
@testable import AnyDockCore

@MainActor
private func expectFullyVisible(_ field: NSTextField, in card: TrayCardItem) {
    guard !field.isHidden else {
        return
    }
    let frame = field.convert(field.bounds, to: card.view)
    #expect(card.view.bounds.contains(frame.insetBy(dx: 1, dy: 1)))
    #expect(
        frame.height >= field.intrinsicContentSize.height - 0.5,
        "\(type(of: card)) \(field.stringValue): \(frame.height)"
    )
}

@MainActor
@Test("拍立得卡片的说明行完整显示在卡片内，不与预览区和最新圆点重叠，长域名不折行，缩略图到达后也一样")
func polaroidCaptionsStayFullyVisible() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("AnyDock-file-State of California Annual Report.pdf")
    try Data(repeating: 0, count: 11_000_000).write(to: file)
    let link = folder.appendingPathComponent("AnyDock-link.webloc")
    try PropertyListSerialization.data(
        fromPropertyList: ["URL": "https://www.very-long-example-domain-name.example.com/a/b"],
        format: .xml,
        options: 0
    ).write(to: link)
    let text = folder.appendingPathComponent("AnyDock-text.txt")
    try String(repeating: "随手坞 ", count: 80).write(to: text, atomically: true, encoding: .utf8)
    let items = [
        ReceivedItem(
            url: file,
            kind: .file,
            thumbnail: nil,
            receivedAt: Date(),
            isPlainText: false
        ),
        ReceivedItem(
            url: link,
            kind: .link,
            thumbnail: nil,
            receivedAt: Date(),
            isPlainText: false
        ),
        ReceivedItem(
            url: text,
            kind: .text,
            thumbnail: nil,
            receivedAt: Date(),
            isPlainText: false
        ),
    ]
    let tray = ImageTrayController()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )
    window.contentViewController = tray
    tray.replaceItems(Array(items.dropFirst()))
    tray.append(items[0])
    for thumbnail in [nil, NSImage(size: NSSize(width: 480, height: 620))] {
        tray.view.layoutSubtreeIfNeeded()
        tray.collection.layoutSubtreeIfNeeded()
        let cards = tray.collection.visibleItems().compactMap { $0 as? PolaroidCardItem }
        #expect(cards.count == 3)
        for card in cards {
            if let thumbnail, let fileCard = card as? FileCardItem {
                fileCard.showThumbnail(
                    thumbnail
                )
            }
            card.view.layoutSubtreeIfNeeded()
            expectFullyVisible(card.caption, in: card)
            let preview = card.previewArea.frame
            let caption = card.caption.convert(card.caption.bounds, to: card.view)
            #expect(caption.maxY <= preview.minY + 1)
            if let link = card as? LinkCardItem {
                let oneLine = NSTextField(labelWithString: link.domain.stringValue)
                oneLine.font = link.domain.font
                #expect(link.domain.frame.height <= oneLine.intrinsicContentSize.height + 1)
            }
            if !card.dot.isHidden {
                let dot = card.dot.convert(card.dot.bounds, to: card.view)
                #expect(card.view.bounds.contains(dot))
                #expect(dot.maxX <= caption.minX + 1)
            }
        }
    }
    withExtendedLifetime(window) {}
}
