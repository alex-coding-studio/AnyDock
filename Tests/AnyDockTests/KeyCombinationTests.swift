import AppKit
import Carbon.HIToolbox
import Testing
@testable import AnyDock

@Test("唤醒快捷键存入偏好后能原样读回，只保留四个修饰键")
func hotKeyRoundTripsThroughPreference() throws {
    let hotKey = try #require(
        KeyCombination.hotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: [.option, .shift, .capsLock, .function]
        )
    )
    let restored = try #require(KeyCombination(preference: hotKey.preference))
    #expect(restored == hotKey)
    #expect(restored.modifiers == [.option, .shift])
    #expect(KeyCombination(preference: ["keyCode": 49]) == nil)
    #expect(KeyCombination(preference: ["keyCode": -1, "modifiers": 0]) == nil)
    #expect(KeyCombination(preference: "⌥Space") == nil)
}

@Test("快捷键显示为标准修饰键符号加键名")
func hotKeyDisplaysStandardSymbols() throws {
    let all = try #require(
        KeyCombination.hotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: [.command, .shift, .option, .control]
        )
    )
    #expect(all.displayString == "⌃⌥⇧⌘Space")
    #expect(
        KeyCombination.hotKey(keyCode: UInt32(kVK_F5), modifiers: .command)?.displayString == "⌘F5"
    )
    #expect(KeyCombination.hotKey(
        keyCode: UInt32(kVK_DownArrow),
        modifiers: .control
    )?.displayString == "⌃↓")
}

@Test("没有 ⌘、⌥ 或 ⌃ 的组合不被接受，单独 ⇧ 也不行")
func hotKeyRequiresCommandOptionOrControl() {
    #expect(KeyCombination.hotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: []) == nil)
    #expect(KeyCombination.hotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: .shift) == nil)
    #expect(KeyCombination.hotKey(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: [.shift, .capsLock]
    ) == nil)
    #expect(KeyCombination.hotKey(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: [.shift, .control]
    ) != nil)
}
