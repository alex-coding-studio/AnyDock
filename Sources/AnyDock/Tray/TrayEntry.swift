import AnyDockCore
import AppKit
import UniformTypeIdentifiers

struct TrayEntry {
    private static let textPreviewCharacters = 1000
    private static let textPrefixBytes = 8192
    private static let filePrefixBytes = 4096
    private static let summaryCharacters = 80
    private static let plainTextBadgeColor = NSColor(white: 0.3, alpha: 1)

    let item: ReceivedItem
    var thumbnail: NSImage?
    let text: String?
    let link: URL?
    let size: Int64?
    let modified: Date?
    let pageAspectRatio: CGFloat?
    let contentType: UTType?

    var url: URL {
        item.url
    }

    var kind: ReceivedKind {
        item.kind
    }

    var fullText: String {
        (try? String(contentsOf: item.url, encoding: .utf8)) ?? text ?? ""
    }

    var characterCount: Int {
        fullText.count
    }

    var displayName: String {
        let name = url.lastPathComponent
        let pattern = #"^AnyDock-\d+-[0-9A-Fa-f-]{36}-"#
        guard let range = name.range(of: pattern, options: .regularExpression) else {
            return name
        }
        return String(name[range.upperBound...])
    }

    var badge: String {
        switch kind {
        case .text: return "TEXT"
        case .link: return "URL"
        case .image, .file:
            let suffix =
                url.pathExtension.isEmpty
                    ? contentType?.preferredFilenameExtension ?? "" : url.pathExtension
            return suffix.isEmpty ? L10n.text("File").uppercased() : suffix.uppercased()
        }
    }

    var badgeStyle: BadgeView.Style {
        switch kind {
        case .image: .media
        case .text: .solid(.systemGray)
        case .link: .solid(.systemBlue)
        case .file:
            if contentType?.conforms(to: .pdf) == true {
                .solid(.systemRed)
            } else if item.isPlainText {
                .solid(Self.plainTextBadgeColor)
            } else {
                .neutral
            }
        }
    }

    var summary: String {
        switch kind {
        case .image: L10n.text("Image")
        case .text: text.map { String($0.prefix(Self.summaryCharacters)) } ?? L10n.text("Text")
        case .link: link?.absoluteString ?? L10n.text("Link")
        case .file: displayName
        }
    }

    init(item: ReceivedItem) {
        self.item = item
        var thumbnail: NSImage?
        var text: String?
        var link: URL?
        var size: Int64?
        var pageAspectRatio: CGFloat?
        var contentType = UTType(filenameExtension: item.url.pathExtension)
        let values = try? item.url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        if item.kind == .image || item.kind == .file {
            size = values?.fileSize.map(Int64.init)
        }
        switch item.kind {
        case .image:
            break
        case .text:
            let handle = try? FileHandle(forReadingFrom: item.url)
            let prefix = (try? handle?.read(upToCount: Self.textPrefixBytes)) ?? Data()
            try? handle?.close()
            var decoded = String(decoding: prefix, as: UTF8.self)
            if prefix.count == Self.textPrefixBytes, decoded.last == "\u{FFFD}" {
                decoded.removeLast()
            }
            text = String(decoded.prefix(Self.textPreviewCharacters))
        case .link:
            if let data = try? Data(contentsOf: item.url),
               let property = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let address = (property as? [String: Any])?["URL"] as? String {
                link = URL(string: address)
            }
        case .file:
            let handle = try? FileHandle(forReadingFrom: item.url)
            let prefix = (try? handle?.read(upToCount: Self.filePrefixBytes)) ?? Data()
            try? handle?.close()
            if item.url.pathExtension.isEmpty, prefix.starts(with: Data("%PDF-".utf8)) {
                contentType = .pdf
            }
            thumbnail =
                contentType.map { NSWorkspace.shared.icon(for: $0) }
                    ?? NSWorkspace.shared.icon(forFile: item.url.path)
            if item.isPlainText {
                text = String(decoding: prefix, as: UTF8.self)
            }
            if contentType?.conforms(to: .pdf) == true {
                pageAspectRatio = Self.pageAspectRatio(of: item.url)
            }
        }
        self.thumbnail = thumbnail
        modified = values?.contentModificationDate
        self.pageAspectRatio = pageAspectRatio
        self.text = text
        self.link = link
        self.size = size
        self.contentType = contentType
    }

    private static func pageAspectRatio(of url: URL) -> CGFloat? {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1) else {
            return nil
        }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else {
            return nil
        }
        return page.rotationAngle % 180 == 0 ? box.height / box.width : box.width / box.height
    }
}
