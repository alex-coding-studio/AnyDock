import Foundation

public struct UploadRequest: Sendable {
    private static let maximumFilenameBytes = 180
    private static let charsetPrefix = "charset="
    private static let quotes = CharacterSet(charactersIn: "\"")
    private static let utf8Charsets: Set = ["utf-8", "utf8"]
    private static let webSchemes: Set = ["http", "https"]

    public let body: Data
    public let kind: ReceivedKind
    public let filename: String?
    public let contentType: String?

    public init(
        body: Data,
        kind: ReceivedKind,
        filename: String? = nil,
        contentType: String? = nil
    ) throws {
        self.filename = try filename.map(Self.sanitizedFilename)
        self.kind = self.filename != nil && kind != .image ? .file : kind
        self.body = body
        self.contentType = contentType
        guard body.count <= HTTPRequestDecoder.maximumBodySize else {
            throw UploadError.payloadTooLarge
        }
        guard !body.isEmpty || self.kind == .file else {
            throw UploadError.emptyContent
        }
        switch self.kind {
        case .image: break
        case .file: try Self.validateFile(filename: self.filename)
        case .text: try Self.validateText(body, contentType: contentType)
        case .link: try Self.validateLink(body)
        }
    }

    static func webURL(_ value: String) -> URL? {
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              webSchemes.contains(scheme), let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }

    private static func validateFile(filename: String?) throws {
        guard filename != nil else {
            throw UploadError.filenameRequired
        }
    }

    private static func validateText(_ body: Data, contentType: String?) throws {
        guard String(data: body, encoding: .utf8) != nil else {
            throw UploadError.invalidUTF8
        }
        guard let contentType else {
            return
        }
        let parts = contentType.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.first == "text/plain" else {
            throw UploadError.unsupportedTextType
        }
        for parameter in parts.dropFirst() where parameter.hasPrefix(charsetPrefix) {
            let charset = parameter.dropFirst(charsetPrefix.count).trimmingCharacters(in: quotes)
            guard utf8Charsets.contains(charset) else {
                throw UploadError.invalidUTF8Declaration
            }
        }
    }

    private static func validateLink(_ body: Data) throws {
        guard let value = String(data: body, encoding: .utf8), webURL(value) != nil else {
            throw UploadError.invalidWebURL
        }
    }

    private static func sanitizedFilename(_ value: String) throws -> String {
        guard !value.contains("/"), !value.contains("\\"),
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw UploadError.invalidFilename
        }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, name.utf8.count <= maximumFilenameBytes else {
            throw UploadError.invalidFilename
        }
        return name
    }
}
