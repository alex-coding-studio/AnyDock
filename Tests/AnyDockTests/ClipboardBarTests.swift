import AnyDockCore
import AppKit
import Testing

@testable import AnyDock

@MainActor
private func makeTray(with texts: [String]) -> (
  ImageTrayController, ClipboardMonitor, NSPasteboard
) {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
  let monitor = ClipboardMonitor(pasteboard: pasteboard)
  let tray = ImageTrayController()
  tray.loadViewIfNeeded()
  monitor.onChange = { tray.replaceClips($0) }
  tray.clearClips = { monitor.clear() }
  monitor.setEnabled(true)
  for text in texts {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    monitor.poll()
  }
  return (tray, monitor, pasteboard)
}

@MainActor
@Test("清空后历史为空，剪贴板条隐藏")
func clearingEmptiesHistoryAndHidesBar() {
  let (tray, monitor, pasteboard) = makeTray(with: ["a", "b"])
  defer {
    monitor.setEnabled(false)
    pasteboard.releaseGlobally()
  }
  #expect(tray.clipboardSurface?.isHidden == false)
  tray.clipboardBar.clearButton.performClick(nil)
  #expect(monitor.clips.isEmpty)
  #expect(tray.clipboardSurface?.isHidden == true)
}

@MainActor
@Test("每次关闭托盘后剪贴板条回到收起状态，Esc 先收起")
func barCollapsesForEachOpening() {
  let (tray, monitor, pasteboard) = makeTray(with: ["a"])
  defer {
    monitor.setEnabled(false)
    pasteboard.releaseGlobally()
  }
  #expect(!tray.clipboardBar.isExpanded)
  tray.clipboardBar.setExpanded(true, animated: false)
  #expect(tray.collapseClipboard())
  #expect(!tray.clipboardBar.isExpanded)
  tray.clipboardBar.setExpanded(true, animated: false)
  tray.trayDidClose()
  #expect(!tray.clipboardBar.isExpanded)
}
