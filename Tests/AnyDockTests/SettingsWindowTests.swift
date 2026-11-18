import AppKit
import Carbon.HIToolbox
import Testing
@testable import AnyDock

@MainActor
@Test("长按 Esc 只取消录制，松开后再按 Esc 才关闭设置")
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
    func escapeEvent(isARepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: isARepeat,
            keyCode: UInt16(kVK_Escape)
        ))
    }

    try window.sendEvent(escapeEvent())
    #expect(!recorder.isRecording)
    #expect(!closeRequest.wasRequested)

    #expect(window.firstResponder === recorder)
    try window.sendEvent(escapeEvent(isARepeat: true))
    #expect(!closeRequest.wasRequested)

    try window.sendEvent(escapeEvent())
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
