import AppKit
import Carbon.HIToolbox
import Combine
import PockyFoundation

@MainActor
final class HotKeyRecorder: NSButton {
    override var acceptsFirstResponder: Bool {
        true
    }

    var hotKey: KeyCombination? {
        didSet { updateTitle() }
    }

    private(set) var isRecording = false

    private let recordingChangeSubject = PassthroughSubject<Bool, Never>()
    private let recordSubject = PassthroughSubject<KeyCombination, Never>()
    private let rejectionSubject = PassthroughSubject<Void, Never>()
    private var resignSubscription: AnyCancellable?

    var recordingChanges: AnyPublisher<Bool, Never> {
        recordingChangeSubject.eraseToAnyPublisher()
    }

    var records: AnyPublisher<KeyCombination, Never> {
        recordSubject.eraseToAnyPublisher()
    }

    var rejections: AnyPublisher<Void, Never> {
        rejectionSubject.eraseToAnyPublisher()
    }

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resignSubscription = window.map { window in
            NotificationCenter.default
                .publisher(for: NSWindow.didResignKeyNotification, object: window)
                .sink { [weak self] _ in
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
        guard let candidate = KeyCombination(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        ) else {
            rejectionSubject.send()
            return
        }
        endRecording()
        recordSubject.send(candidate)
    }

    func endRecording() {
        guard isRecording else {
            return
        }
        isRecording = false
        updateTitle()
        recordingChangeSubject.send(false)
    }

    @objc private func beginRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        window?.makeFirstResponder(self)
        updateTitle()
        recordingChangeSubject.send(true)
    }

    private func configure() {
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel(L10n.text("Wake shortcut"))
        updateTitle()
    }

    private func updateTitle() {
        let showsKeys = !isRecording && hotKey != nil
        let prompt = isRecording ? L10n.text("Type shortcut…") : showsKeys ? "" : L10n.text(
            "hotkey.placeholder"
        )
        attributedTitle = NSAttributedString(string: prompt, attributes: [
            .font: PKYTypographyRole.body.nsFont(in: PKYThemeFallback.system),
            .foregroundColor: NSColor.pkyContent(.secondary),
        ])
        image = showsKeys ? hotKey.map { KeyCapsImage.make(keys: $0.displayKeys) } : nil
        imagePosition = showsKeys ? .imageOnly : .noImage
        setAccessibilityValue(hotKey?.displayString)
    }
}
