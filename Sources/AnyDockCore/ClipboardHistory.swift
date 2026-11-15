import Foundation

public struct ClipboardClip: Sendable, Equatable {
  public let text: String
  public let copiedAt: Date
}

public struct ClipboardHistory: Sendable {
  public static let limit = 4
  public private(set) var clips: [ClipboardClip] = []

  public init() {}

  @discardableResult
  public mutating func record(_ text: String, at date: Date = Date()) -> Bool {
    guard !text.isEmpty, clips.first?.text != text else { return false }
    clips = Array(([ClipboardClip(text: text, copiedAt: date)] + clips).prefix(Self.limit))
    return true
  }

  public mutating func clear() { clips = [] }
}
