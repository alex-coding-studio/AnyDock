import AppKit
import Carbon.HIToolbox
import Combine

struct HotKey: Equatable {
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
        var symbols = ""
        if modifiers.contains(.control) {
            symbols += "⌃"
        }
        if modifiers.contains(.option) {
            symbols += "⌥"
        }
        if modifiers.contains(.shift) {
            symbols += "⇧"
        }
        if modifiers.contains(.command) {
            symbols += "⌘"
        }
        return symbols + keyName
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

    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
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
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
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
}

@MainActor
final class HotKeyCenter {
    private let pressSubject = PassthroughSubject<Void, Never>()
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var presses: AnyPublisher<Void, Never> {
        pressSubject.eraseToAnyPublisher()
    }

    var isRegistered: Bool {
        registration != nil
    }

    func register(_ hotKey: HotKey?) -> Bool {
        if let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        guard let hotKey else {
            return true
        }
        guard installHandler() else {
            return false
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            EventHotKeyID(signature: 0x414E_444B, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            return false
        }
        registration = reference
        return true
    }

    private func installHandler() -> Bool {
        guard handler == nil else {
            return true
        }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { center.pressSubject.send() }
                return noErr
            },
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        return status == noErr
    }
}

@MainActor
final class HotKeyRecorder: NSButton {
    override var acceptsFirstResponder: Bool {
        true
    }

    var hotKey: HotKey? {
        didSet { updateTitle() }
    }

    var onRecordingChanged: ((Bool) -> Void)?
    var onRecord: ((HotKey) -> Void)?
    var onRejected: (() -> Void)?
    private(set) var isRecording = false

    private var resignObserver: (any NSObjectProtocol)?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel(L10n.text("Wake shortcut"))
        updateTitle()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = window.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.endRecording() }
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            return super.keyDown(with: event)
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = modifiers.isDisjoint(with: [.control, .option, .command])
        if Int(event.keyCode) == kVK_Escape, plain {
            endRecording()
            return
        }
        guard let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            onRejected?()
            return
        }
        endRecording()
        onRecord?(candidate)
    }

    func endRecording() {
        guard isRecording else {
            return
        }
        isRecording = false
        updateTitle()
        onRecordingChanged?(false)
    }

    @objc private func beginRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        window?.makeFirstResponder(self)
        updateTitle()
        onRecordingChanged?(true)
    }

    private func updateTitle() {
        title =
            isRecording
                ? L10n.text("Type shortcut…") : hotKey?.displayString ?? L10n.text(
                    "Record Shortcut"
                )
    }
}
