import Foundation

struct ReceivedContent {
    let kind: ReceivedKind
    let data: Data
    let nameSuffix: String
    let thumbnail: Data?
    let isPlainText: Bool

    var isQuarantined: Bool {
        kind != .image
    }

    static func make(from request: UploadRequest) throws -> ReceivedContent {
        let content = switch resolvedKind(of: request) {
        case .image: try image(request.body)
        case .text: text(request.body)
        case .link: try link(request.body)
        case .file: try file(request)
        }
        guard content.data.count <= HTTPRequestDecoder.maximumBodySize else {
            throw UploadError.payloadTooLarge
        }
        return content
    }

    private static func resolvedKind(of request: UploadRequest) -> ReceivedKind {
        if request.kind == .file, ImagePreview.isImage(request.body) {
            return .image
        }
        return request.kind
    }

    private static func image(_ body: Data) throws -> ReceivedContent {
        let preview = try ImagePreview(body)
        return ReceivedContent(
            kind: .image,
            data: body,
            nameSuffix: "." + preview.originalExtension,
            thumbnail: preview.png,
            isPlainText: false
        )
    }

    private static func text(_ body: Data) -> ReceivedContent {
        ReceivedContent(
            kind: .text,
            data: body,
            nameSuffix: ".txt",
            thumbnail: nil,
            isPlainText: false
        )
    }

    private static func link(_ body: Data) throws -> ReceivedContent {
        let address = String(decoding: body, as: UTF8.self)
        let webloc = try PropertyListSerialization.data(
            fromPropertyList: ["URL": address],
            format: .xml,
            options: 0
        )
        return ReceivedContent(
            kind: .link,
            data: webloc,
            nameSuffix: ".webloc",
            thumbnail: nil,
            isPlainText: false
        )
    }

    private static func file(_ request: UploadRequest) throws -> ReceivedContent {
        guard let filename = request.filename else {
            throw UploadError.filenameRequired
        }
        guard request.contentType?.hasPrefix("image/") != true else {
            throw UploadError.unsupportedImage
        }
        let name = FileTypeDetector.filename(filename, matching: request.body)
        return ReceivedContent(
            kind: .file,
            data: request.body,
            nameSuffix: "-" + name,
            thumbnail: nil,
            isPlainText: FileTypeDetector.isPlainText(request.body, filename: name)
        )
    }
}
