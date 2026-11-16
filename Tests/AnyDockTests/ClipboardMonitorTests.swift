import AppKit
import Combine
import Testing
@testable import AnyDock

@MainActor
private func withPasteboard(
    _ body: (NSPasteboard, ClipboardMonitor, CurrentValueSubject<Bool, Never>) -> Void
) {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let enabled = CurrentValueSubject<Bool, Never>(true)
    let monitor = ClipboardMonitor(pasteboard: pasteboard, isEnabled: enabled.eraseToAnyPublisher())
    defer { enabled.send(false) }
    body(pasteboard, monitor, enabled)
}

@MainActor
private func write(
    _ text: String,
    to pasteboard: NSPasteboard,
    extra: [NSPasteboard.PasteboardType] = []
) {
    pasteboard.declareTypes([.string] + extra, owner: nil)
    pasteboard.setString(text, forType: .string)
    for type in extra {
        pasteboard.setString("", forType: type)
    }
}

@MainActor
@Test("记录纯文本，跳过密码管理器标记的内容和文件")
func monitorSkipsConcealedAndFiles() {
    withPasteboard { pasteboard, monitor, _ in
        write("secret", to: pasteboard, extra: [ClipboardMonitor.concealedType])
        monitor.poll()
        write("file.txt", to: pasteboard, extra: [.fileURL])
        monitor.poll()
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        write("voice text", to: pasteboard, extra: [transient])
        monitor.poll()
        #expect(monitor.clips.map(\.text) == ["voice text"])
    }
}

@MainActor
@Test("重新复制历史条目不会再生成一条")
func recopyDoesNotDuplicate() {
    withPasteboard { pasteboard, monitor, _ in
        write("a", to: pasteboard)
        monitor.poll()
        write("b", to: pasteboard)
        monitor.poll()
        monitor.poll()
        monitor.write(recordingInHistory: false) { $0.setString("a", forType: .string) }
        monitor.poll()
        #expect(monitor.clips.map(\.text) == ["b", "a"])
    }
}

@MainActor
@Test("关闭开关后停止记录并清空历史")
func disablingClearsHistory() {
    withPasteboard { pasteboard, monitor, enabled in
        var published: [String]?
        let subscription = monitor.clipsPublisher.sink { published = $0.map(\.text) }
        defer { subscription.cancel() }
        write("a", to: pasteboard)
        monitor.poll()
        enabled.send(false)
        write("b", to: pasteboard)
        monitor.poll()
        #expect(monitor.clips.isEmpty)
        #expect(published == [])
    }
}
