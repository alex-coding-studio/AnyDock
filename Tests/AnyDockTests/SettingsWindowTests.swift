import AppKit
import Carbon.HIToolbox
import Testing
@testable import AnyDock

@MainActor
@Test("录制快捷键时 Esc 只取消录制，窗口收到 Esc 时使用原生关闭操作")
func escapeCancelsRecordingBeforeClosingSettings() throws {
    let window = SettingsWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    let closeRequest = CloseRequest()
    window.delegate = closeRequest
    let recorder = HotKeyRecorder()
    window.contentView = recorder
    recorder.performClick(nil)
    #expect(window.firstResponder === recorder)
    #expect(recorder.isRecording)
    let escape = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "\u{1B}",
        charactersIgnoringModifiers: "\u{1B}",
        isARepeat: false,
        keyCode: UInt16(kVK_Escape)
    ))

    window.sendEvent(escape)
    #expect(!recorder.isRecording)
    #expect(!closeRequest.wasRequested)

    window.makeFirstResponder(window)
    window.sendEvent(escape)
    #expect(closeRequest.wasRequested)
}

@MainActor
private final class CloseRequest: NSObject, NSWindowDelegate {
    private(set) var wasRequested = false

    func windowShouldClose(_: NSWindow) -> Bool {
        wasRequested = true
        return true
    }
}
