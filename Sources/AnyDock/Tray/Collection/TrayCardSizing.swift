import AnyDockCore
import AppKit
import PockyFoundation
import UniformTypeIdentifiers

@MainActor
final class TrayCardSizing {
    private struct Key: Hashable {
        let url: URL
        let modified: Date?
        let width: CGFloat
        let singleColumn: Bool
    }

    static let bodyFont = PKYTypographyRole.body.withReferenceSize(TrayMetrics.cardBodyFontSize)
        .nsFont(in: PKYThemeFallback.system)
    static let domainFont = PKYTypographyRole.heading.bold.nsFont(in: PKYThemeFallback.system)
    static let addressFont = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
    static let fileLinesFont = NSFont.monospacedSystemFont(
        ofSize: TrayMetrics.fileLinesFontSize,
        weight: .regular
    )
    static let captionFont = PKYTypographyRole.supporting.medium.nsFont(in: PKYThemeFallback.system)
    static let timeFont = PKYTypographyRole.caption.monospacedDigits.nsFont(
        in: PKYThemeFallback.system
    )
    static let badgeClearance = TrayMetrics.badgeHeight + PKYLayout.Gap.content(.compact) * 2

    private static let squareRatio: CGFloat = 1
    private static let documentCardRatio: CGFloat = 1.4
    private static let genericPreviewHeight: CGFloat = 56
    private static let maximumRatio: CGFloat = 1.6
    private static let singleColumnMaximumHeight: CGFloat = 160
    private static let lineSample = "Ag"

    private var heights = [Key: CGFloat]()

    private static func textBlock(_ content: CGFloat) -> CGFloat {
        badgeClearance + content + PKYLayout.Inset.container(.compact)
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        textHeight(lineSample, font: font, width: .greatestFiniteMagnitude)
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let cell = NSTextFieldCell(textCell: text)
        cell.font = font
        cell.wraps = true
        cell.lineBreakMode = .byWordWrapping
        let bounds = NSRect(x: 0, y: 0, width: max(width, 1), height: .greatestFiniteMagnitude)
        return ceil(cell.cellSize(forBounds: bounds).height)
    }

    func heightRatio(of entry: TrayEntry, columnWidth: CGFloat, singleColumn: Bool) -> CGFloat {
        guard columnWidth > 0 else {
            return Self.squareRatio
        }
        if entry.kind == .image {
            return entry.item.aspectRatio.map { CGFloat($0) } ?? Self.squareRatio
        }
        let key = Key(
            url: entry.url,
            modified: entry.modified,
            width: columnWidth,
            singleColumn: singleColumn
        )
        if let height = heights[key] {
            return height / columnWidth
        }
        let height = cardHeight(of: entry, columnWidth: columnWidth, singleColumn: singleColumn)
        heights[key] = height
        return height / columnWidth
    }

    func forget(_ urls: some Sequence<URL>) {
        let removed = Set(urls)
        heights = heights.filter { !removed.contains($0.key.url) }
    }

    private func cardHeight(
        of entry: TrayEntry,
        columnWidth: CGFloat,
        singleColumn: Bool
    ) -> CGFloat {
        let previewWidth = columnWidth - PKYLayout.Inset.container(.compact) * 2
        let maximum = singleColumn
            ? Self.singleColumnMaximumHeight
            : columnWidth * Self.maximumRatio
        guard let preview = previewHeight(of: entry, width: previewWidth) else {
            return min(columnWidth * Self.documentCardRatio, maximum)
        }
        let caption = entry.kind == .file ? Self.captionFont : Self.timeFont
        let strip = max(Self.lineHeight(caption), PKYLayout.Size.dot(.compact))
        let height = PKYLayout.Inset.container(.compact) * 2
            + preview + PKYLayout.Gap.content(.compact) + strip
        return min(height, maximum)
    }

    private func previewHeight(of entry: TrayEntry, width: CGFloat) -> CGFloat? {
        let textWidth = width - PKYLayout.Inset.container(.compact) * 2
        switch entry.kind {
        case .image:
            return nil
        case .text:
            return Self.textBlock(Self.textHeight(
                entry.text ?? "",
                font: Self.bodyFont,
                width: textWidth
            ))
        case .link:
            let domain = Self.lineHeight(Self.domainFont)
            let address = Self.textHeight(
                entry.link?.absoluteString ?? "",
                font: Self.addressFont,
                width: textWidth
            )
            return Self.textBlock(domain + PKYLayout.Gap.content(.compact) + address)
        case .file:
            if entry.item.isPlainText {
                return Self.textBlock(
                    Self.textHeight(entry.text ?? "", font: Self.fileLinesFont, width: textWidth)
                )
            }
            if let ratio = entry.pageAspectRatio {
                return width * ratio
            }
            if let type = entry.contentType, type.conforms(to: .content), !type.conforms(
                to: .audio
            ) {
                return nil
            }
            return Self.genericPreviewHeight
        }
    }
}
