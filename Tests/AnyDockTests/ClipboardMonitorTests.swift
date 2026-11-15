import AppKit
import Testing

@testable import AnyDock

@MainActor
private func withPasteboard(_ body: (NSPasteboard, ClipboardMonitor) -> Void) {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
  defer { pasteboard.releaseGlobally() }
  let monitor = ClipboardMonitor(pasteboard: pasteboard)
  monitor.setEnabled(true)
  defer { monitor.setEnabled(false) }
  body(pasteboard, monitor)
}

@MainActor
private func write(
  _ text: String, to pasteboard: NSPasteboard, extra: [NSPasteboard.PasteboardType] = []
) {
  pasteboard.declareTypes([.string] + extra, owner: nil)
  pasteboard.setString(text, forType: .string)
  for type in extra { pasteboard.setString("", forType: type) }
}

@MainActor
@Test("记录纯文本，跳过密码管理器标记的内容和文件")
func monitorSkipsConcealedAndFiles() {
  withPasteboard { pasteboard, monitor in
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
  withPasteboard { pasteboard, monitor in
    write("a", to: pasteboard)
    monitor.poll()
    write("b", to: pasteboard)
    monitor.poll()
    monitor.poll()
    write("a", to: pasteboard)
    monitor.ignoreCurrentContents()
    monitor.poll()
    #expect(monitor.clips.map(\.text) == ["b", "a"])
  }
}

@MainActor
@Test("关闭开关后停止记录并清空历史")
func disablingClearsHistory() {
  withPasteboard { pasteboard, monitor in
    var published: [String]?
    monitor.onChange = { published = $0.map(\.text) }
    write("a", to: pasteboard)
    monitor.poll()
    monitor.setEnabled(false)
    write("b", to: pasteboard)
    monitor.poll()
    #expect(monitor.clips.isEmpty)
    #expect(published == [])
  }
}
