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

public struct ReceivedItem: Sendable, Identifiable {
    public let url: URL
    public let kind: ReceivedKind
    public let thumbnail: Data?
    public let receivedAt: Date
    public let isPlainText: Bool

    public var id: URL {
        url
    }

    public var image: ReceivedImage? {
        guard kind == .image, let thumbnail else {
            return nil
        }
        return ReceivedImage(url: url, thumbnail: thumbnail, receivedAt: receivedAt)
    }
}
