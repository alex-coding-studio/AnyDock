import AppKit
import PockyFoundation

@MainActor
enum SettingsLabel {
    static func make(
        _ text: String = "",
        font: PKYTypographyRole = .body,
        color: NSColor = .pkyContent(.primary),
        wraps: Bool = false
    ) -> NSTextField {
        let label = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(
            labelWithString: text
        )
        label.font = font.nsFont(in: PKYThemeFallback.system)
        label.textColor = color
        if wraps {
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return label
    }

    static func footnote(_ text: String = "") -> NSTextField {
        make(text, font: .supporting, color: .pkyContent(.secondary), wraps: true)
    }

    static func message() -> NSTextField {
        let label = make(font: .supporting, color: .pkyStatus(.destructive), wraps: true)
        label.isHidden = true
        return label
    }

    static func show(_ message: SettingsMessage?, in label: NSTextField) {
        label.stringValue = message?.text ?? ""
        label.textColor = message?.isError == false ? .pkyContent(.secondary) : .pkyStatus(
            .destructive
        )
        label.isHidden = message == nil
    }

    static func symbol(
        _ name: String,
        size: PKYIcon.Size,
        color: NSColor = .pkyContent(.secondary)
    ) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size.pointSize, weight: .regular))
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = color
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }

    static func noted(_ symbolName: String, _ text: String) -> NSStackView {
        let icon = symbol(symbolName, size: .accessory)
        let stack = NSStackView(views: [icon, footnote(text)])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = PKYLayout.Gap.content(.compact)
        return stack
    }
}
