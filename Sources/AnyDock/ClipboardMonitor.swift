import AnyDockCore
import AppKit

@MainActor
final class ClipboardMonitor: NSObject {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var onChange: (([ClipboardClip]) -> Void)?

    private let pasteboard: NSPasteboard
    private var history = ClipboardHistory()
    private var lastChangeCount: Int
    private var timer: Timer?

    var clips: [ClipboardClip] {
        history.clips
    }

    var isEnabled: Bool {
        timer != nil
    }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }
        if enabled {
            lastChangeCount = pasteboard.changeCount
            let timer = Timer(
                timeInterval: 0.5,
                target: self,
                selector: #selector(timerFired),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            history.clear()
            onChange?(history.clips)
        }
    }

    func poll() {
        guard isEnabled, pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount
        guard let types = pasteboard.types, !types.contains(Self.concealedType),
              !types.contains(.fileURL), let text = pasteboard.string(forType: .string),
              history.record(text)
        else {
            return
        }
        onChange?(history.clips)
    }

    func ignoreCurrentContents() {
        lastChangeCount = pasteboard.changeCount
    }

    func clear() {
        history.clear()
        onChange?(history.clips)
    }

    @objc private func timerFired() {
        poll()
    }
}
