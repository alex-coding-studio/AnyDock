import Foundation

public enum ReceivedKind: String, CaseIterable, Sendable {
    case image
    case text
    case link
    case file

    public var directoryName: String {
        switch self {
        case .image: "Images"
        case .text: "Text"
        case .link: "Links"
        case .file: "Files"
        }
    }
}

public struct ReceivedItem: Sendable {
    public let url: URL
    public let kind: ReceivedKind
    public let thumbnail: Data?
    public let receivedAt: Date
    public let isPlainText: Bool
}
