import AppKit
import Carbon.HIToolbox
import Testing
@testable import AnyDock

@MainActor
private func keyEvent(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
    )
}

@Test("托盘快捷键按键位和必需修饰键匹配：⌘C、⌘⌫、空格、Esc")
@MainActor
func trayShortcutsMatchTheirKeys() throws {
    #expect(try TrayKeyboardShortcuts.copy.matches(keyEvent(kVK_ANSI_C, .command)))
    #expect(try TrayKeyboardShortcuts.copy.matches(keyEvent(kVK_ANSI_C, [.command, .shift])))
    #expect(try TrayKeyboardShortcuts.trash.matches(keyEvent(kVK_Delete, .command)))
    #expect(try TrayKeyboardShortcuts.preview.matches(keyEvent(kVK_Space)))
    #expect(try TrayKeyboardShortcuts.escape.matches(keyEvent(kVK_Escape)))
    #expect(try !TrayKeyboardShortcuts.copy.matches(keyEvent(kVK_ANSI_V, .command)))
}

@Test("缺少必需修饰键时不触发：单按 C 不复制，⌥⌫ 不删除")
@MainActor
func trayShortcutsRequireTheirModifiers() throws {
    #expect(try !TrayKeyboardShortcuts.copy.matches(keyEvent(kVK_ANSI_C)))
    #expect(try !TrayKeyboardShortcuts.trash.matches(keyEvent(kVK_Delete, .option)))
    #expect(try !TrayKeyboardShortcuts.trash.matches(keyEvent(kVK_Delete)))
}

@Test("右键菜单显示的快捷键来自同一张托盘快捷键表")
@MainActor
func contextMenuShortcutsComeFromTheTable() throws {
    let menu = TrayCollectionView().contextMenu()
    let copy = try #require(
        menu.items.first { $0.action == #selector(TrayCollectionView.copy(_:)) }
    )
    #expect(copy.keyEquivalent == TrayKeyboardShortcuts.copy.keyEquivalent)
    #expect(copy.keyEquivalentModifierMask == TrayKeyboardShortcuts.copy.modifiers)
    let trash = try #require(menu.items.last)
    #expect(trash.keyEquivalent == TrayKeyboardShortcuts.trash.keyEquivalent)
    #expect(trash.keyEquivalentModifierMask == TrayKeyboardShortcuts.trash.modifiers)
    #expect(trash.keyEquivalent == String(Character(Unicode.Scalar(UInt8(NSBackspaceCharacter)))))
}
