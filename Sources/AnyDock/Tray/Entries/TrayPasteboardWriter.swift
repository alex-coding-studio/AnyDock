import AppKit

@MainActor
struct TrayPasteboardWriter {
    let clipboard: ClipboardMonitor

    static func dragWriter(for entry: TrayEntry) -> any NSPasteboardWriting {
        switch entry.kind {
        case .image, .file:
            return entry.url as NSURL
        case .text:
            return entry.fullText as NSString
        case .link:
            let item = NSPasteboardItem()
            if let link = entry.link {
                item.setString(link.absoluteString, forType: .URL)
                item.setString(link.absoluteString, forType: .string)
            }
            item.setString(entry.url.absoluteString, forType: .fileURL)
            return item
        }
    }

    private static func copyItem(for entry: TrayEntry) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        switch entry.kind {
        case .image:
            item.setString(entry.url.absoluteString, forType: .fileURL)
            item.setDataProvider(PNGDataProvider(url: entry.url), forTypes: [.png])
        case .text:
            item.setString(entry.fullText, forType: .string)
        case .link:
            if let link = entry.link {
                item.setString(link.absoluteString, forType: .URL)
                item.setString(link.absoluteString, forType: .string)
            }
        case .file:
            item.setString(entry.url.absoluteString, forType: .fileURL)
        }
        return item
    }

    func copy(_ entries: [TrayEntry]) {
        guard !entries.isEmpty else {
            return
        }
        clipboard.write(recordingInHistory: true) { $0.writeObjects(
            entries.map(Self.copyItem(for:))
        ) }
    }
}

private final class PNGDataProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(
        _: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType _: NSPasteboard.PasteboardType
    ) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = NSBitmapImageRep(cgImage: image).representation(
                  using: .png,
                  properties: [:]
              )
        else {
            return
        }
        item.setData(png, forType: .png)
    }
}
