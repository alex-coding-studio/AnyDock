import AppKit
import PockyFoundation

@MainActor
enum SettingsControls {
    enum Role {
        case primary
        case secondary
    }

    static func button(
        _ title: String,
        symbol: String? = nil,
        role: Role = .secondary,
        target: AnyObject?,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        style(button, role: role)
        return button
    }

    static func style(_ button: NSButton, role: Role) {
        button.bezelStyle = .push
        button.isBordered = true
        button.controlSize = .regular
        if role == .primary {
            button.bezelColor = .pkyAccent(.primary)
            if #available(macOS 26, *) {
                button.tintProminence = .primary
            }
            button.image = button.image?.withSymbolConfiguration(
                .init(paletteColors: [.pkyOnAccent])
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .foregroundColor: NSColor.pkyOnAccent,
                .font: button.font ?? PKYTypographyRole.body.nsFont(in: PKYThemeFallback.system),
                .paragraphStyle: paragraph,
            ])
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    static func textField() -> NSTextField {
        let field = NSTextField()
        field.controlSize = .regular
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        return field
    }
}
