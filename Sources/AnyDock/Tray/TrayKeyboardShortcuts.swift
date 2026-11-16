import Carbon.HIToolbox

enum TrayKeyboardShortcuts {
    static let copy = KeyCombination(keyCode: kVK_ANSI_C, modifiers: .command)
    static let trash = KeyCombination(keyCode: kVK_Delete, modifiers: .command)
    static let preview = KeyCombination(keyCode: kVK_Space)
    static let escape = KeyCombination(keyCode: kVK_Escape)
}
