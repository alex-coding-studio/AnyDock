import AppKit
import Combine
import Testing
@testable import AnyDock
@testable import AnyDockCore

@MainActor
private func makeTray(with texts: [String]) -> (
    TrayViewController,
    CurrentValueSubject<Bool, Never>,
    NSPasteboard
) {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AnyDockTests-\(UUID().uuidString)"))
    let enabled = CurrentValueSubject<Bool, Never>(true)
    let monitor = ClipboardMonitor(pasteboard: pasteboard, isEnabled: enabled.eraseToAnyPublisher())
    let tray = TrayViewController(clipboard: monitor)
    tray.loadViewIfNeeded()
    for text in texts {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        monitor.poll()
    }
    return (tray, enabled, pasteboard)
}

@MainActor
@Test("清空后历史为空，剪贴板条隐藏")
func clearingEmptiesHistoryAndHidesBar() {
    let (tray, enabled, pasteboard) = makeTray(with: ["a", "b"])
    defer {
        enabled.send(false)
        pasteboard.releaseGlobally()
    }
    #expect(tray.clipboardSurface?.isHidden == false)
    tray.clipboardBar.clearButton.performClick(nil)
    #expect(tray.clipboardBar.clips.isEmpty)
    #expect(tray.clipboardSurface?.isHidden == true)
}

@MainActor
@Test("每次关闭托盘后剪贴板条回到收起状态，Esc 先收起")
func barCollapsesForEachOpening() {
    let (tray, enabled, pasteboard) = makeTray(with: ["a"])
    defer {
        enabled.send(false)
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

@MainActor
@Test("展开后点击剪贴板标题行会收起，和收起时点整行展开对称")
func clickingHeaderCollapsesExpandedBar() throws {
    let bar = ClipboardBar()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
        styleMask: [],
        backing: .buffered,
        defer: true
    )
    window.contentView?.addSubview(bar)
    bar.translatesAutoresizingMaskIntoConstraints = false
    bar.widthAnchor.constraint(equalToConstant: 400).isActive = true
    bar.update([ClipboardClip(text: "clip", copiedAt: Date())])
    let click = { (point: NSPoint) in
        window.contentView?.layoutSubtreeIfNeeded()
        let location = bar.header.convert(point, to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        bar.mouseDown(with: event)
    }
    try click(NSPoint(x: bar.title.frame.midX, y: bar.title.frame.midY))
    #expect(bar.isExpanded)
    try click(NSPoint(x: bar.title.frame.midX, y: bar.title.frame.midY))
    #expect(!bar.isExpanded)
}
