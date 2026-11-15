import Foundation

public struct HTTPFailure: Error, Sendable {
  public let status: Int
  public let reason: String

  public init(_ status: Int, _ reason: String) {
    self.status = status
    self.reason = reason
  }
}

public struct UploadRequest: Sendable {
  public let body: Data
  public let kind: ReceivedKind
  public let filename: String?
  public let contentType: String?

  public init(
    body: Data, kind: ReceivedKind, filename: String? = nil, contentType: String? = nil
  ) throws {
    self.filename = try filename.map(Self.sanitizedFilename)
    self.kind = self.filename != nil && kind != .image ? .file : kind
    self.body = body
    self.contentType = contentType
    guard body.count <= HTTPRequestDecoder.maximumBodySize else {
      throw HTTPFailure(413, "Payload Too Large")
    }
    guard !body.isEmpty || self.kind == .file else { throw HTTPFailure(400, "Empty Content") }
    switch self.kind {
    case .image: break
    case .file:
      guard self.filename != nil else { throw HTTPFailure(400, "Filename Required") }
    case .text:
      guard String(data: body, encoding: .utf8) != nil else {
        throw HTTPFailure(415, "Invalid UTF-8")
      }
      if let contentType {
        let parts = contentType.split(separator: ";").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.first == "text/plain" else { throw HTTPFailure(415, "Unsupported Text Type") }
        for parameter in parts.dropFirst() where parameter.hasPrefix("charset=") {
          let charset = parameter.dropFirst(8).trimmingCharacters(
            in: CharacterSet(charactersIn: "\""))
          guard ["utf-8", "utf8"].contains(charset) else {
            throw HTTPFailure(415, "Invalid UTF-8 Declaration")
          }
        }
      }
    case .link:
      guard let value = String(data: body, encoding: .utf8), Self.webURL(value) != nil else {
        throw HTTPFailure(415, "Invalid Web URL")
      }
    }
  }

  static func webURL(_ value: String) -> URL? {
    guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      value.rangeOfCharacter(from: .controlCharacters) == nil,
      let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty
    else { return nil }
    return url
  }

  private static func sanitizedFilename(_ value: String) throws -> String {
    guard !value.contains("/"), !value.contains("\\"),
      value.rangeOfCharacter(from: .controlCharacters) == nil
    else { throw HTTPFailure(400, "Invalid Filename") }
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .replacingOccurrences(of: ":", with: "-")
    guard !name.isEmpty, name.utf8.count <= 180 else {
      throw HTTPFailure(400, "Invalid Filename")
    }
    return name
  }
}

public struct HTTPRequestDecoder: Sendable {
  public static let maximumBodySize = 50_000_000
  private static let maximumHeaderSize = 16 * 1024
  private let token: String
  private var buffer = Data()
  private var contentLength: Int?
  private var kind = ReceivedKind.image
  private var filename: String?
  private var contentType: String?
  public private(set) var expectsContinue = false

  public init(token: String) { self.token = token }

  public mutating func append(_ data: Data) throws -> UploadRequest? {
    guard buffer.count + data.count <= Self.maximumBodySize + Self.maximumHeaderSize else {
      throw HTTPFailure(413, "Payload Too Large")
    }
    buffer.append(data)
    if contentLength == nil {
      guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
        if buffer.count > Self.maximumHeaderSize { throw HTTPFailure(431, "Headers Too Large") }
        return nil
      }
      guard separator.lowerBound <= Self.maximumHeaderSize,
        let header = String(data: buffer[..<separator.lowerBound], encoding: .ascii)
      else { throw HTTPFailure(400, "Bad Request") }
      try parseHeader(header)
      buffer = Data(buffer[separator.upperBound...])
    }
    guard let contentLength else { return nil }
    guard buffer.count <= contentLength else { throw HTTPFailure(400, "Bad Request") }
    guard buffer.count == contentLength else { return nil }
    return try UploadRequest(body: buffer, kind: kind, filename: filename, contentType: contentType)
  }

  private mutating func parseHeader(_ header: String) throws {
    let lines = header.components(separatedBy: "\r\n")
    let request = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
    guard request.count == 3, request[0] == "POST", request[1] == "/upload",
      request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0"
    else { throw HTTPFailure(400, "Bad Request") }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { throw HTTPFailure(400, "Bad Request") }
      let name = String(line[..<colon]).lowercased()
      let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty,
        name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
        !value.utf8.contains(where: { $0 < 32 && $0 != 9 }), headers[name] == nil
      else { throw HTTPFailure(400, "Bad Request") }
      headers[name] = value
    }
    guard Self.matches(headers["x-snapdock-key"] ?? "", token), !token.isEmpty else {
      throw HTTPFailure(401, "Unauthorized")
    }
    contentType = headers["content-type"]?.lowercased()
    if let encoded = headers["x-anydock-filename"], !encoded.isEmpty {
      guard let decoded = encoded.removingPercentEncoding else {
        throw HTTPFailure(400, "Invalid Filename")
      }
      filename = decoded
    }
    if let declared = headers["x-anydock-type"] {
      guard let parsed = ReceivedKind(rawValue: declared) else {
        throw HTTPFailure(415, "Unsupported Content Type")
      }
      kind = parsed
    } else if filename != nil {
      kind = .file
    } else if contentType?.hasPrefix("text/plain") == true {
      kind = .text
    } else if contentType?.hasPrefix("text/uri-list") == true {
      kind = .link
    }
    guard headers["transfer-encoding"] == nil else { throw HTTPFailure(400, "Bad Request") }
    guard let value = headers["content-length"], !value.isEmpty,
      value.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(value), count >= 0
    else { throw HTTPFailure(411, "Length Required") }
    guard count <= Self.maximumBodySize else { throw HTTPFailure(413, "Payload Too Large") }
    if let expectation = headers["expect"] {
      guard expectation.lowercased() == "100-continue" else {
        throw HTTPFailure(417, "Expectation Failed")
      }
      expectsContinue = true
    }
    contentLength = count
  }

  private static func matches(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8)
    let b = Array(rhs.utf8)
    guard a.count == b.count else { return false }
    return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }
}
