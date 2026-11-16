import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class ShortcutField: NSView {
    let recorder = HotKeyRecorder()

    private let well = ShortcutWell()
    private let clear = NSButton()
    private let clearSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()

    var clears: AnyPublisher<Void, Never> {
        clearSubject.eraseToAnyPublisher()
    }

    init() {
        super.init(frame: .zero)
        recorder.isBordered = false
        recorder.setContentHuggingPriority(.required, for: .horizontal)
        well.addSubview(recorder)
        recorder.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(
                PKYLayout.Inset.control.horizontal(.compact)
            )
            make.top.bottom.equalToSuperview().inset(PKYLayout.Inset.control.vertical(.compact))
            make.height.greaterThanOrEqualTo(SettingsMetrics.keyCapHeight)
        }
        clear.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: L10n.text("hotkey.clear.accessibility")
        )?.withSymbolConfiguration(.init(
            pointSize: PKYIcon.Size.accessory.pointSize,
            weight: .semibold
        ))
        clear.isBordered = false
        clear.contentTintColor = .pkyContent(.secondary)
        clear.toolTip = L10n.text("hotkey.clear")
        clear.setAccessibilityLabel(L10n.text("hotkey.clear.accessibility"))
        clear.target = self
        clear.action = #selector(clearShortcut)
        clear.isHidden = true
        let stack = NSStackView(views: [well, clear])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = PKYLayout.Gap.content(.compact)
        stack.setHuggingPriority(.required, for: .horizontal)
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        recorder.recordingChanges
            .sink { [weak self] in self?.well.isRecording = $0 }
            .store(in: &subscriptions)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func show(_ hotKey: KeyCombination?) {
        recorder.hotKey = hotKey
        clear.isHidden = hotKey == nil
    }

    @objc private func clearShortcut() {
        recorder.endRecording()
        clearSubject.send()
    }
}

@MainActor
private final class ShortcutWell: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    var isRecording = false {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PKYShape.Radius.tile
        layer?.cornerCurve = .continuous
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func mouseDown(with _: NSEvent) {
        subviews.compactMap { $0 as? NSButton }.first?.performClick(nil)
    }

    override func updateLayer() {
        layer?.backgroundColor = PKYThemeFallback.system.color.filled.quiet(.tertiary).cgColor
        layer?.borderWidth = isRecording ? PKYShape.Stroke.strong : 0
        layer?.borderColor = NSColor.pkyAccent(.primary).cgColor
    }
}
