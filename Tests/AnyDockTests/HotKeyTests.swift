import AppKit
import Carbon.HIToolbox
import Testing

@testable import AnyDock

@Test("唤醒快捷键存入偏好后能原样读回，只保留四个修饰键")
func hotKeyRoundTripsThroughPreference() throws {
  let hotKey = try #require(
    HotKey(keyCode: UInt32(kVK_Space), modifiers: [.option, .shift, .capsLock, .function]))
  let restored = try #require(HotKey(preference: hotKey.preference))
  #expect(restored == hotKey)
  #expect(restored.modifiers == [.option, .shift])
  #expect(HotKey(preference: ["keyCode": 49]) == nil)
  #expect(HotKey(preference: ["keyCode": -1, "modifiers": 0]) == nil)
  #expect(HotKey(preference: "⌥Space") == nil)
}

@Test("快捷键显示为标准修饰键符号加键名")
func hotKeyDisplaysStandardSymbols() throws {
  let all = try #require(
    HotKey(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift, .option, .control]))
  #expect(all.displayString == "⌃⌥⇧⌘Space")
  #expect(HotKey(keyCode: UInt32(kVK_F5), modifiers: .command)?.displayString == "⌘F5")
  #expect(HotKey(keyCode: UInt32(kVK_DownArrow), modifiers: .control)?.displayString == "⌃↓")
}

@Test("没有 ⌘、⌥ 或 ⌃ 的组合不被接受，单独 ⇧ 也不行")
func hotKeyRequiresCommandOptionOrControl() {
  #expect(HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: []) == nil)
  #expect(HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: .shift) == nil)
  #expect(HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.shift, .capsLock]) == nil)
  #expect(HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.shift, .control]) != nil)
}
