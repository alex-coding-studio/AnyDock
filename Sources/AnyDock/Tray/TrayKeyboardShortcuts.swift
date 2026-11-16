import AppKit
import Carbon.HIToolbox

struct TrayShortcut {
    enum Key {
        case character(String)
        case code(Int)
    }

    let key: Key
    var modifiers: NSEvent.ModifierFlags = []

    var keyEquivalent: String {
        switch key {
        case let .character(character):
            character
        case .code(kVK_Delete):
            String(Character(Unicode.Scalar(UInt8(NSBackspaceCharacter))))
        case .code:
            ""
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isSuperset(of: modifiers) else {
            return false
        }
        switch key {
        case let .character(character):
            return event.charactersIgnoringModifiers == character
        case let .code(code):
            return Int(event.keyCode) == code
        }
    }
}

enum TrayKeyboardShortcuts {
    static let copy = TrayShortcut(key: .character("c"), modifiers: .command)
    static let trash = TrayShortcut(key: .code(kVK_Delete), modifiers: .command)
    static let preview = TrayShortcut(key: .character(" "))
    static let escape = TrayShortcut(key: .code(kVK_Escape))
}
