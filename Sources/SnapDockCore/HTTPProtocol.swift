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
}

public struct HTTPRequestDecoder: Sendable {
  public static let maximumBodySize = 32 * 1024 * 1024
  private static let maximumHeaderSize = 16 * 1024
  private let token: String
  private var buffer = Data()
  private var contentLength: Int?
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
    return buffer.count == contentLength ? UploadRequest(body: buffer) : nil
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
    guard headers["transfer-encoding"] == nil else { throw HTTPFailure(400, "Bad Request") }
    guard let value = headers["content-length"], !value.isEmpty,
      value.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(value), count > 0
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
