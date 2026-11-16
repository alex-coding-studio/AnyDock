import Foundation

public struct ReceivedItem: Sendable {
    public let url: URL
    public let kind: ReceivedKind
    public let thumbnail: Data?
    public let receivedAt: Date
    public let isPlainText: Bool
    public var aspectRatio: Double?
}
