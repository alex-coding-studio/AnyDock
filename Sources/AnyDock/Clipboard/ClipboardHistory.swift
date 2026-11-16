import Foundation

struct ClipboardClip: Sendable, Equatable {
    let text: String
    let copiedAt: Date
}

struct ClipboardHistory: Sendable {
    static let limit = 4

    private(set) var clips = [ClipboardClip]()

    @discardableResult
    mutating func record(_ text: String, at date: Date = Date()) -> Bool {
        guard !text.isEmpty, clips.first?.text != text else {
            return false
        }
        clips = Array(([ClipboardClip(text: text, copiedAt: date)] + clips).prefix(Self.limit))
        return true
    }

    mutating func clear() {
        clips = []
    }
}
