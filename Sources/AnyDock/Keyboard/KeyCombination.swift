import AppKit
import Carbon.HIToolbox

enum HotKeyRejection: String {
    case modifierRequired = "hotkey.modifierRequired"
    case reservedForQuit = "hotkey.reservedForQuit"
}

struct KeyCombination: Equatable {
    static let quitCharacter = "q"

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .control,
        .option,
        .shift,
        .command,
    ]

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_Help: "?⃝",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    var isReservedForQuit: Bool {
        guard modifiers == .command else {
            return false
        }
        return matchesQuit(character: Self.layoutCharacter(for: keyCode))
            || matchesQuit(character: Self.layoutCharacter(
                for: keyCode,
                modifierKeyState: UInt32(cmdKey) >> 8
            ))
    }

    var preference: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers.rawValue)]
    }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.control) {
            result |= controlKey
        }
        if modifiers.contains(.option) {
            result |= optionKey
        }
        if modifiers.contains(.shift) {
            result |= shiftKey
        }
        if modifiers.contains(.command) {
            result |= cmdKey
        }
        return UInt32(result)
    }

    var displayString: String {
        displayKeys.joined()
    }

    var displayKeys: [String] {
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘"),
        ]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1) + [keyName]
    }

    private var keyName: String {
        if let name = Self.namedKeys[Int(keyCode)] {
            return name
        }
        return Self.layoutCharacter(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    init?(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        let modifiers = modifiers.intersection(Self.supportedModifiers)
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(preference: Any?) {
        guard let values = preference as? [String: Int], let keyCode = values["keyCode"],
              let modifiers = values["modifiers"], let code = UInt32(exactly: keyCode),
              let flags = UInt(exactly: modifiers)
        else {
            return nil
        }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    private static func layoutCharacter(
        for keyCode: UInt32,
        modifierKeyState: UInt32 = 0
    ) -> String? {
        guard let virtualKey = UInt16(exactly: keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(
                to: UCKeyboardLayout.self
            ) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                virtualKey,
                UInt16(modifierKeyState == 0 ? kUCKeyActionDisplay : kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        let text = String(utf16CodeUnits: characters, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    func matchesQuit(character: String?) -> Bool {
        modifiers == .command && character == Self.quitCharacter
    }
}
