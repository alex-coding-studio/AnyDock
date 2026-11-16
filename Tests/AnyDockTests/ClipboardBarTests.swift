import AppKit
import Combine
import PockyFoundation
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
@Test("剪贴板条目在浅色模式为带描边和阴影的纯白卡片与深色文字，深色模式保持主干深色卡片无描边阴影")
func cellSeparatesOnLightGlassAndPreservesDarkMode() throws {
    let cell = ClipboardCell()
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
    container.addSubview(cell)
    cell.snp.makeConstraints { $0.edges.equalToSuperview() }
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
        styleMask: [],
        backing: .buffered,
        defer: true
    )
    window.contentView?.addSubview(container)
    container.snp.makeConstraints { $0.edges.equalToSuperview() }

    window.appearance = NSAppearance(named: .aqua)
    window.contentView?.layoutSubtreeIfNeeded()
    let lightCG = try #require(cell.layer?.backgroundColor)
    let lightBackground = try #require(NSColor(cgColor: lightCG)?.usingColorSpace(.sRGB))
    #expect(lightBackground.redComponent > 0.99)
    #expect(lightBackground.greenComponent > 0.99)
    #expect(lightBackground.blueComponent > 0.99)
    #expect(lightBackground.alphaComponent > 0.99)
    #expect(cell.layer?.borderWidth == PKYShape.Stroke.standard)
    #expect((cell.layer?.shadowOpacity ?? 0) > 0)
    let lightText = try #require(cell.text.textColor?.usingColorSpace(.sRGB))
    #expect(lightText.redComponent < 0.2)

    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView?.layoutSubtreeIfNeeded()
    var expectedDark = CGColor.black
    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        expectedDark = NSColor.pkyBackground(.standard(.secondary)).cgColor
    }
    let darkCG = try #require(cell.layer?.backgroundColor)
    let darkBackground = try #require(NSColor(cgColor: darkCG)?.usingColorSpace(.sRGB))
    let expectedDarkColor = try #require(NSColor(cgColor: expectedDark)?.usingColorSpace(.sRGB))
    #expect(abs(darkBackground.redComponent - expectedDarkColor.redComponent) < 0.001)
    #expect(cell.layer?.borderWidth == 0)
    #expect((cell.layer?.shadowOpacity ?? 0) == 0)

    window.appearance = NSAppearance(named: .aqua)
    container.appearance = NSAppearance(named: .vibrantDark)
    window.contentView?.layoutSubtreeIfNeeded()
    let overriddenCG = try #require(cell.layer?.backgroundColor)
    let overriddenBackground = try #require(NSColor(cgColor: overriddenCG)?.usingColorSpace(.sRGB))
    #expect(overriddenBackground.redComponent > 0.99)
    let overriddenText = try #require(cell.text.textColor?.usingColorSpace(.sRGB))
    #expect(overriddenText.redComponent < 0.2)
}

@MainActor
@Test("剪贴板玻璃容器保持原生 contentView 嵌套结构")
func clipboardSurfaceUsesNativeGlassContentView() {
    let (tray, enabled, pasteboard) = makeTray(with: ["a"])
    defer {
        enabled.send(false)
        pasteboard.releaseGlobally()
    }
    if #available(macOS 26, *) {
        let glass = tray.footer.clipboardSurface as? NSGlassEffectView
        #expect(glass?.contentView === tray.footer.clipboardBar)
        #expect(glass?.tintColor == nil)
    }
}
