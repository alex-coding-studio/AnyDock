import AnyDockCore
import AppKit
import Combine

@MainActor
final class ClipboardMonitor: NSObject {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private static let pollInterval: TimeInterval = 0.5
    private static let pollTolerance: TimeInterval = 0.25

    private let pasteboard: NSPasteboard
    private let clipsSubject = CurrentValueSubject<[ClipboardClip], Never>([])
    private var history = ClipboardHistory()
    private var lastChangeCount: Int
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    var clips: [ClipboardClip] {
        clipsSubject.value
    }

    var clipsPublisher: AnyPublisher<[ClipboardClip], Never> {
        clipsSubject.eraseToAnyPublisher()
    }

    var isEnabled: Bool {
        timer != nil
    }

    init(pasteboard: NSPasteboard = .general, isEnabled: AnyPublisher<Bool, Never>) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        super.init()
        isEnabled
            .removeDuplicates()
            .sink { [weak self] in self?.setEnabled($0) }
            .store(in: &subscriptions)
    }

    func write(recordingInHistory: Bool, _ body: (NSPasteboard) -> Void) {
        poll()
        pasteboard.clearContents()
        body(pasteboard)
        if !recordingInHistory {
            lastChangeCount = pasteboard.changeCount
        }
    }

    func clear() {
        history.clear()
        publish()
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
        publish()
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }
        if enabled {
            lastChangeCount = pasteboard.changeCount
            let timer = Timer(
                timeInterval: Self.pollInterval,
                target: self,
                selector: #selector(timerFired),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = Self.pollTolerance
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            clear()
        }
    }

    private func publish() {
        clipsSubject.send(history.clips)
    }

    @objc private func timerFired() {
        poll()
    }
}
