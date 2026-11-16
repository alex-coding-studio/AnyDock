import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyRecorder: NSButton {
    override var acceptsFirstResponder: Bool {
        true
    }

    var hotKey: KeyCombination? {
        didSet { updateTitle() }
    }

    var onRecordingChanged: ((Bool) -> Void)?
    var onRecord: ((KeyCombination) -> Void)?
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
        guard let candidate = KeyCombination.hotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        ) else {
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
