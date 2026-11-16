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
