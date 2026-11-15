import Darwin
import Foundation
import Testing

@testable import AnyDockCore

@Test("文本、链接和文件保留发送语义，拒绝无效输入及未认证请求")
func decodesContentAndRejectsUnsafeInputs() throws {
  let text = try decodeContent(kind: "text", body: Data("你好".utf8))
  #expect(text.kind == .text)
  #expect(text.body == Data("你好".utf8))
  let link = try decodeContent(kind: "link", body: Data("https://example.com/path?q=1".utf8))
  #expect(link.kind == .link)
  let file = try decodeContent(kind: "file", name: ".notes:2026.json", body: Data("{}".utf8))
  #expect(file.kind == .file)
  #expect(file.filename == "notes-2026.json")
  let textFile = try decodeContent(kind: "text", name: "notes.txt", body: Data("hello".utf8))
  #expect(textFile.kind == .file)
  let invalid: [(String, String?, Data, String?, Int)] = [
    ("text", nil, Data([255]), "test-key", 415),
    ("link", nil, Data("file:///etc/passwd".utf8), "test-key", 415),
    ("link", nil, Data("https://example.com\nhttps://other.com".utf8), "test-key", 415),
    ("file", "../private.txt", Data([1]), "test-key", 400),
    ("file", "..\\private.txt", Data([1]), "test-key", 400),
    ("file", "...", Data([1]), "test-key", 400),
    ("file", "bad\0.txt", Data([1]), "test-key", 400),
    ("file", nil, Data([1]), "test-key", 400),
    ("file", "notes.txt", Data([1]), nil, 401),
  ]
  for (kind, name, body, key, status) in invalid {
    do {
      _ = try decodeContent(kind: kind, name: name, body: body, key: key)
      Issue.record("Unsafe content was accepted")
    } catch let error as HTTPFailure {
      #expect(error.status == status)
    }
  }
  var decoder = HTTPRequestDecoder(token: "test-key")
  let header =
    "POST /upload HTTP/1.1\r\nX-SnapDock-Key: test-key\r\nContent-Length: 50000001\r\n\r\n"
  #expect(throws: HTTPFailure.self) { try decoder.append(Data(header.utf8)) }
  var partial = HTTPRequestDecoder(token: "test-key")
  let incomplete =
    "POST /upload HTTP/1.1\r\nX-SnapDock-Key: test-key\r\nContent-Length: 10\r\n"
    + "X-AnyDock-Type: text\r\n\r\nabc"
  #expect(try partial.append(Data(incomplete.utf8)) == nil)
}

@Test("分类型保存与隔离属性保持原字节，文件语义优先于文本格式")
func storesTypedContentWithQuarantine() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ImageStore()
  let text = try await store.save(
    try decodeContent(kind: "text", body: Data("hello".utf8)), in: directory)
  let link = try await store.save(
    try decodeContent(kind: "link", body: Data("https://example.com".utf8)), in: directory)
  let file = try await store.save(
    try decodeContent(kind: "file", name: "notes.json", body: Data("{}".utf8)), in: directory)
  let video = try await store.save(
    try decodeContent(kind: "file", name: "clip.mp4", body: Data([0, 1, 255])), in: directory)
  let image = try await store.save(try makeImage(), in: directory)
  #expect(text.url.deletingLastPathComponent().lastPathComponent == "Text")
  #expect(text.url.pathExtension == "txt")
  #expect(link.url.deletingLastPathComponent().lastPathComponent == "Links")
  #expect(link.url.pathExtension == "webloc")
  #expect(file.url.deletingLastPathComponent().lastPathComponent == "Files")
  #expect(file.url.lastPathComponent.hasSuffix("-notes.json"))
  #expect(file.kind == .file && file.isPlainText)
  #expect(video.kind == .file && !video.isPlainText)
  #expect(video.url.deletingLastPathComponent().lastPathComponent == "Files")
  #expect(try Data(contentsOf: video.url) == Data([0, 1, 255]))
  #expect(image.url.deletingLastPathComponent().lastPathComponent == "Images")
  for item in [text, link, file, video] {
    #expect(item.url.lastPathComponent.hasPrefix("AnyDock-"))
    #expect(getxattr(item.url.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    let properties = try item.url.resourceValues(forKeys: [.quarantinePropertiesKey])
    #expect(properties.quarantineProperties != nil)
  }
  #expect(try Data(contentsOf: text.url) == Data("hello".utf8))
  let property = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: link.url), format: nil)
  #expect((property as? [String: String])?["URL"] == "https://example.com")
  let second = try await store.save(
    try decodeContent(kind: "file", name: "notes.json", body: Data("different".utf8)),
    in: directory)
  #expect(second.url != file.url)
  #expect(try Data(contentsOf: file.url) == Data("{}".utf8))
  #expect(try await store.list(in: directory).count == 6)
  #expect(try await store.listImages(in: directory).count == 1)
}

@Test("图片按实际内容识别，伪装扩展名不能绕过声明校验")
func classifiesImagesByContentAndDeclaration() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ImageStore()
  let image = try await store.save(
    try decodeContent(kind: "file", name: "document.pdf", body: makeImage()), in: directory)
  #expect(image.kind == .image)
  #expect(image.url.deletingLastPathComponent().lastPathComponent == "Images")
  let fake = try await store.save(
    try decodeContent(kind: "file", name: "fake.png", body: Data("not an image".utf8)),
    in: directory)
  #expect(fake.kind == .file)
  #expect(getxattr(fake.url.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
  let invalid = try UploadRequest(
    body: Data("not an image".utf8), kind: .file, filename: "fake.png", contentType: "image/png")
  await #expect(throws: HTTPFailure.self) {
    try await store.save(invalid, in: directory)
  }
  #expect(try await store.list(in: directory).count == 2)
}

@Test("旧根目录图片保持原位，符号链接和普通文件不扩大列表或接收范围")
func listsLegacyImagesAndRejectsDirectoryEscape() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: outside)
  }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  let image = try makeImage()
  let legacy = root.appendingPathComponent("SnapDock-legacy.png")
  let renamed = root.appendingPathComponent("AnyDock-flat.png")
  try image.write(to: legacy)
  try image.write(to: renamed)
  try image.write(to: root.appendingPathComponent("holiday.png"))
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("Files"), withDestinationURL: outside)
  let store = ImageStore()
  await #expect(throws: (any Error).self) {
    try await store.save(
      try decodeContent(kind: "file", name: "notes.txt", body: Data("hi".utf8)), in: root)
  }
  #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
  let listed = try await store.list(in: root)
  let paths = Set(listed.map { $0.url.resolvingSymlinksInPath().path })
  #expect(paths == Set([legacy, renamed].map { $0.resolvingSymlinksInPath().path }))
  #expect(FileManager.default.fileExists(atPath: legacy.path))
}

@Test("分类目录验证后被替换为符号链接时，不能向外部目录写入")
func rejectsDirectoryReplacementAfterValidation() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: outside)
  }
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  let writer = try ItemWriter(in: root, kind: .file)
  let retired = root.appendingPathComponent("OriginalFiles", isDirectory: true)
  try FileManager.default.moveItem(at: writer.directory, to: retired)
  try FileManager.default.createSymbolicLink(at: writer.directory, withDestinationURL: outside)
  #expect(throws: (any Error).self) {
    try writer.write(Data("fixture".utf8), named: "AnyDock-replacement.txt", quarantined: true)
  }
  #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
  #expect(try FileManager.default.contentsOfDirectory(atPath: retired.path).isEmpty)
}

func decodeContent(
  kind: String, name: String? = nil, body: Data, key: String? = "test-key"
) throws -> UploadRequest {
  var headers =
    "POST /upload HTTP/1.1\r\nContent-Length: \(body.count)\r\nX-AnyDock-Type: \(kind)\r\n"
  if let key { headers += "X-SnapDock-Key: \(key)\r\n" }
  if let name {
    let encoded = try #require(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
    headers += "X-AnyDock-Filename: \(encoded)\r\n"
  }
  var decoder = HTTPRequestDecoder(token: "test-key")
  let request = try decoder.append(Data((headers + "\r\n").utf8) + body)
  return try #require(request)
}

func sendRawRequest(port: UInt16, data: Data) throws -> String {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw POSIXError(.EIO) }
  defer { close(descriptor) }
  var timeout = timeval(tv_sec: 5, tv_usec: 0)
  var noSignal: Int32 = 1
  setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
  setsockopt(
    descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = port.bigEndian
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
  let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
  var remaining = data
  while !remaining.isEmpty {
    let sent = remaining.withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, 0) }
    guard sent > 0 else { throw POSIXError(.EIO) }
    remaining.removeFirst(sent)
  }
  shutdown(descriptor, SHUT_WR)
  var response = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let count = recv(descriptor, &buffer, buffer.count, 0)
    guard count >= 0 else { throw POSIXError(.EIO) }
    if count == 0 { break }
    response.append(contentsOf: buffer.prefix(count))
  }
  return String(decoding: response, as: UTF8.self)
}
