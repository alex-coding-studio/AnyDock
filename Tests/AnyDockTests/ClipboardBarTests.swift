import AppKit
import Combine
import SnapKit
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
    let tray = TrayViewController(
        viewModel: TrayViewModel(inbox: TestInbox()),
        clipboard: monitor
    )
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
    #expect(tray.footer.clipboardSurface.isHidden == false)
    tray.footer.clipboardBar.clearButton.performClick(nil)
    #expect(tray.footer.clipboardBar.clips.isEmpty)
    #expect(tray.footer.clipboardSurface.isHidden == true)
}

@MainActor
@Test("每次关闭托盘后剪贴板条回到收起状态，Esc 先收起")
func barCollapsesForEachOpening() {
    let (tray, enabled, pasteboard) = makeTray(with: ["a"])
    defer {
        enabled.send(false)
        pasteboard.releaseGlobally()
    }
    #expect(!tray.footer.clipboardBar.isExpanded)
    tray.footer.clipboardBar.setExpanded(true, animated: false)
    #expect(tray.footer.collapseClipboard())
    #expect(!tray.footer.clipboardBar.isExpanded)
    tray.footer.clipboardBar.setExpanded(true, animated: false)
    tray.trayDidClose()
    #expect(!tray.footer.clipboardBar.isExpanded)
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
    bar.snp.makeConstraints { $0.width.equalTo(400) }
    bar.update([ClipboardClip(text: "clip", copiedAt: Date())])
    window.contentView?.layoutSubtreeIfNeeded()
    let collapsedHeight = bar.frame.height
    #expect(collapsedHeight > 0)
    bar.setExpanded(true, animated: false)
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(bar.frame.height > collapsedHeight)
    for child in bar.subviews where !child.isHidden {
        #expect(bar.bounds.contains(child.frame))
    }
    bar.setExpanded(false, animated: false)
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(bar.frame.height == collapsedHeight)
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

@MainActor
@Test("浅色窗口中剪贴板条目仍沿用深色外观解析背景与文字")
func cellResolvesDarkAppearanceInsideLightWindow() throws {
    let cell = ClipboardCell()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
        styleMask: [],
        backing: .buffered,
        defer: true
    )
    window.appearance = NSAppearance(named: .aqua)
    window.contentView?.addSubview(cell)
    cell.snp.makeConstraints { $0.edges.equalToSuperview() }
    window.contentView?.layoutSubtreeIfNeeded()
    cell.updateLayer()

    #expect(cell.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    #expect(cell.text.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    #expect(cell.time.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

    var expectedDark = CGColor.black
    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        expectedDark = NSColor.pkyBackground(.standard(.secondary)).cgColor
    }
    var lightBackground = CGColor.white
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        lightBackground = NSColor.pkyBackground(.standard(.secondary)).cgColor
    }
    let actual = try #require(cell.layer?.backgroundColor)
    #expect(actual == expectedDark)
    #expect(actual != lightBackground)
}
