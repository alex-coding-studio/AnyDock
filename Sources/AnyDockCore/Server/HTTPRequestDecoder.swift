import Foundation

public struct HTTPRequestDecoder: Sendable {
    public static let maximumBodySize = 50_000_000

    private static let maximumHeaderSize = 16 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let lineSeparator = "\r\n"
    private static let supportedVersions: Set = ["HTTP/1.1", "HTTP/1.0"]
    private static let horizontalTab: UInt8 = 9
    private static let firstPrintableByte: UInt8 = 32
    private static let hyphen = UInt8(ascii: "-")
    private static let lowercaseLetters = UInt8(ascii: "a") ... UInt8(ascii: "z")
    private static let digits = UInt8(ascii: "0") ... UInt8(ascii: "9")

    public private(set) var expectsContinue = false

    private let token: String
    private var buffer = Data()
    private var contentLength: Int?
    private var kind = ReceivedKind.image
    private var filename: String?
    private var contentType: String?

    public init(token: String) {
        self.token = token
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else {
            return false
        }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func validateRequestLine(_ line: String) throws {
        let request = line.split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[0] == "POST", request[1] == "/upload",
              supportedVersions.contains(String(request[2]))
        else {
            throw UploadError.badRequest
        }
    }

    private static func headerFields(_ lines: ArraySlice<String>) throws -> [String: String] {
        var headers = [String: String]()
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                throw UploadError.badRequest
            }
            let name = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard isValidFieldName(name), isValidFieldValue(value), headers[name] == nil else {
                throw UploadError.badRequest
            }
            headers[name] = value
        }
        return headers
    }

    private static func isValidFieldName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy(isFieldNameByte)
    }

    private static func isFieldNameByte(_ byte: UInt8) -> Bool {
        lowercaseLetters.contains(byte) || digits.contains(byte) || byte == hyphen
    }

    private static func isValidFieldValue(_ value: String) -> Bool {
        !value.utf8.contains { $0 < firstPrintableByte && $0 != horizontalTab }
    }

    private static func declaredLength(_ headers: [String: String]) throws -> Int {
        guard headers["transfer-encoding"] == nil else {
            throw UploadError.badRequest
        }
        guard let value = headers["content-length"], !value.isEmpty,
              value.utf8.allSatisfy(digits.contains), let count = Int(value), count >= 0
        else {
            throw UploadError.lengthRequired
        }
        guard count <= maximumBodySize else {
            throw UploadError.payloadTooLarge
        }
        return count
    }

    private static func continueExpected(_ headers: [String: String]) throws -> Bool {
        guard let expectation = headers["expect"] else {
            return false
        }
        guard expectation.lowercased() == "100-continue" else {
            throw UploadError.expectationFailed
        }
        return true
    }

    public mutating func append(_ data: Data) throws -> UploadRequest? {
        guard buffer.count + data.count <= Self.maximumBodySize + Self.maximumHeaderSize else {
            throw UploadError.payloadTooLarge
        }
        buffer.append(data)
        if contentLength == nil {
            guard let separator = buffer.range(of: Self.headerTerminator) else {
                if buffer.count > Self.maximumHeaderSize {
                    throw UploadError.headersTooLarge
                }
                return nil
            }
            guard separator.lowerBound <= Self.maximumHeaderSize,
                  let header = String(data: buffer[..<separator.lowerBound], encoding: .ascii)
            else {
                throw UploadError.badRequest
            }
            try parseHeader(header)
            buffer = Data(buffer[separator.upperBound...])
        }
        guard let contentLength else {
            return nil
        }
        guard buffer.count <= contentLength else {
            throw UploadError.badRequest
        }
        guard buffer.count == contentLength else {
            return nil
        }
        return try UploadRequest(
            body: buffer,
            kind: kind,
            filename: filename,
            contentType: contentType
        )
    }

    private mutating func parseHeader(_ header: String) throws {
        let lines = header.components(separatedBy: Self.lineSeparator)
        try Self.validateRequestLine(lines.first ?? "")
        let headers = try Self.headerFields(lines.dropFirst())
        try authorize(headers)
        contentType = headers["content-type"]?.lowercased()
        try readFilename(headers)
        try inferKind(headers)
        let count = try Self.declaredLength(headers)
        if try Self.continueExpected(headers) {
            expectsContinue = true
        }
        contentLength = count
    }

    private func authorize(_ headers: [String: String]) throws {
        guard Self.matches(headers["x-anydock-key"] ?? "", token), !token.isEmpty else {
            throw UploadError.unauthorized
        }
    }

    private mutating func readFilename(_ headers: [String: String]) throws {
        guard let encoded = headers["x-anydock-filename"], !encoded.isEmpty else {
            return
        }
        guard let decoded = encoded.removingPercentEncoding else {
            throw UploadError.invalidFilename
        }
        filename = decoded
    }

    private mutating func inferKind(_ headers: [String: String]) throws {
        if let declared = headers["x-anydock-type"] {
            guard let parsed = ReceivedKind(rawValue: declared) else {
                throw UploadError.unsupportedContentType
            }
            kind = parsed
        } else if filename != nil {
            kind = .file
        } else if contentType?.hasPrefix("text/plain") == true {
            kind = .text
        } else if contentType?.hasPrefix("text/uri-list") == true {
            kind = .link
        }
    }
}
