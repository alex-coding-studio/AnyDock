import AppKit
import PockyFoundation

@MainActor
enum KeyCapsImage {
    static func make(keys: [String]) -> NSImage {
        let font = PKYTypographyRole.supporting.medium.nsFont(in: PKYThemeFallback.system)
        let padding = PKYLayout.Gap.content(.compact)
        let spacing = PKYLayout.Gap.content(.compact)
        let height = SettingsMetrics.keyCapHeight
        let widths = keys.map { key in
            max(height, (key as NSString).size(withAttributes: [.font: font]).width + 2 * padding)
        }
        let size = NSSize(
            width: widths.reduce(0, +) + spacing * CGFloat(max(keys.count - 1, 0)),
            height: height
        )
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (key, width) in zip(keys, widths) {
                let cap = NSRect(x: x, y: 0, width: width, height: height)
                    .insetBy(dx: PKYShape.Stroke.standard, dy: PKYShape.Stroke.standard)
                let shape = NSBezierPath(
                    roundedRect: cap,
                    xRadius: SettingsMetrics.keyCapCornerRadius,
                    yRadius: SettingsMetrics.keyCapCornerRadius
                )
                NSColor.pkyBackground(.standard(.secondary)).setFill()
                shape.fill()
                shape.lineWidth = PKYShape.Stroke.standard
                NSColor.pkySeparator(.standard).setStroke()
                shape.stroke()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.pkyContent(.primary),
                ]
                let text = (key as NSString).size(withAttributes: attributes)
                (key as NSString).draw(
                    at: NSPoint(x: cap.midX - text.width / 2, y: cap.midY - text.height / 2),
                    withAttributes: attributes
                )
                x += width + spacing
            }
            return true
        }
        image.accessibilityDescription = keys.joined()
        return image
    }
}
