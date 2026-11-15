import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SnapDockCore

@Test("分段到达的图片请求保持原始字节")
func fragmentedUploadPreservesBody() throws {
  var decoder = HTTPRequestDecoder(token: "test-key")
  let header = Data(
    "POST /upload HTTP/1.1\r\nContent-Length: 4\r\nX-SnapDock-Key: test-key\r\n\r\n".utf8)
  #expect(try decoder.append(header.prefix(20)) == nil)
  #expect(try decoder.append(header.dropFirst(20) + Data([0, 255])) == nil)
  #expect(try decoder.append(Data([13, 10]))?.body == Data([0, 255, 13, 10]))
}

@Test("缺少密钥、歧义长度和过大请求不能进入图片存储")
func rejectsUnsafeRequests() throws {
  let cases: [(String, Int)] = [
    ("Content-Length: 1\r\n", 401),
    ("X-SnapDock-Key: wrong\r\nContent-Length: 1\r\n", 401),
    ("X-SnapDock-Key: test-key\r\nContent-Length: 1\r\nContent-Length: 2\r\n", 400),
    ("X-SnapDock-Key: test-key\r\nContent-Length: 999999999\r\n", 413),
    ("X-SnapDock-Key: test-key\r\nTransfer-Encoding: chunked\r\n", 400),
  ]
  for (headers, status) in cases {
    var decoder = HTTPRequestDecoder(token: "test-key")
    do {
      _ = try decoder.append(Data("POST /upload HTTP/1.1\r\n\(headers)\r\n".utf8))
      Issue.record("Unsafe request was accepted")
    } catch let error as HTTPFailure {
      #expect(error.status == status)
    }
  }
}

@Test("同一张图收到两次另存原图，非图片不落盘")
func storesOriginalsWithoutOverwriting() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let image = try makeImage()
  let store = ImageStore()
  let first = try await store.save(image, in: directory)
  let second = try await store.save(image, in: directory)
  #expect(first.url != second.url)
  #expect(try Data(contentsOf: first.url) == image)
  #expect(try Data(contentsOf: second.url) == image)
  await #expect(throws: HTTPFailure.self) {
    try await store.save(Data("not an image".utf8), in: directory)
  }
  #expect(try await store.list(in: directory).count == 2)
}

@Test("真实 HTTP 上传仅在鉴权和原图落盘后返回成功，端口冲突不会换端口")
func receivesAuthenticatedHTTPAndRejectsPortConflict() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ImageStore()
  let server = HTTPServer(store: store)
  let conflicting = HTTPServer(store: store)
  let port = UInt16.random(in: 20000...45000)
  let configuration = ReceiverConfiguration(port: port, directory: directory, token: "test-key")
  do {
    try await server.start(configuration: configuration, onReceive: { _ in }, onFailure: { _ in })
    await #expect(throws: (any Error).self) {
      try await conflicting.start(
        configuration: configuration, onReceive: { _ in }, onFailure: { _ in })
    }
    var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/upload")))
    request.httpMethod = "POST"
    request.httpBody = try makeImage()
    let (_, deniedResponse) = try await URLSession.shared.data(for: request)
    #expect((deniedResponse as? HTTPURLResponse)?.statusCode == 401)
    #expect(try await store.list(in: directory).isEmpty)
    request.setValue("test-key", forHTTPHeaderField: "X-SnapDock-Key")
    let (responseBody, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 201)
    let json = try #require(JSONSerialization.jsonObject(with: responseBody) as? [String: Any])
    #expect(json["status"] as? String == "saved")
    let image = try #require(try await store.list(in: directory).first)
    #expect(try Data(contentsOf: image.url) == request.httpBody)
    await server.stop()
    await conflicting.stop()
  } catch {
    await server.stop()
    await conflicting.stop()
    throw error
  }
}

func makeImage() throws -> Data {
  let context = try #require(
    CGContext(
      data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
  let bytes = NSMutableData()
  let destination = try #require(
    CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
  #expect(CGImageDestinationFinalize(destination))
  return bytes as Data
}
