import Foundation
import Testing
@testable import AnyDock

@Test("剪贴板历史最多保留 4 条，新的挤掉最旧的")
func clipboardHistoryKeepsNewestFour() {
    var history = ClipboardHistory()
    for index in 1 ... 6 {
        history.record("text \(index)")
    }
    #expect(history.clips.map(\.text) == ["text 6", "text 5", "text 4", "text 3"])
}

@Test("与最新一条相同的文本不新增，与更早的相同仍会新增")
func clipboardHistorySkipsRepeatOfNewest() {
    var history = ClipboardHistory()
    let recorded = ["a", "a", "b", "a"].map { history.record($0) }
    #expect(recorded == [true, false, true, true])
    #expect(history.clips.map(\.text) == ["a", "b", "a"])
}
