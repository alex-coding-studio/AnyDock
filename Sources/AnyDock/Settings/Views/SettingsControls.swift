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
        button.controlSize = .regular
        if #available(macOS 26, *) {
            button.bezelStyle = .glass
            button.borderShape = .capsule
            button.tintProminence = role == .primary ? .primary : .none
        } else {
            button.bezelStyle = .push
            button.bezelColor = role == .primary ? .pkyAccent(.primary) : nil
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
