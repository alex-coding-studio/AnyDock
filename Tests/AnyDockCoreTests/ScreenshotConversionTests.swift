import CoreGraphics
import Foundation
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import AnyDockCore

@Test("开启截图转 PNG 时将带 EXIF 标记的 HEIC 截图转正并存为 PNG，保留截图标记")
func convertsExifMarkedHEICScreenshotToUprightPNG() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let heic = try makeHEICImage(width: 4, height: 2, orientation: 6, userComment: "Screenshot")
    let store = InboxStore()
    let item = try await store.save(
        UploadRequest(body: heic, kind: .image),
        in: directory,
        convertScreenshotsToPNG: true
    )
    #expect(item.kind == .image)
    #expect(item.url.pathExtension == "png")
    let savedData = try Data(contentsOf: item.url)
    let source = try #require(CGImageSourceCreateWithData(savedData as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 4)
    let orientation = properties[kCGImagePropertyOrientation] as? Int
    #expect(orientation == nil || orientation == 1)
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifUserComment] as? String == "Screenshot")
    #expect(item.aspectRatio == 2.0)
}

@Test("关闭截图转 PNG 时保留 HEIC 截图原始字节与扩展名")
func preservesHEICScreenshotWhenConversionDisabled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let heic = try makeHEICImage(width: 4, height: 2, orientation: 6, userComment: "Screenshot")
    let store = InboxStore()
    let item = try await store.save(
        UploadRequest(body: heic, kind: .image),
        in: directory,
        convertScreenshotsToPNG: false
    )
    #expect(item.url.pathExtension == "heic")
    #expect(try Data(contentsOf: item.url) == heic)
}

@Test("开启截图转 PNG 时普通 HEIC 照片保持原格式与原始字节")
func preservesRegularHEICPhotoWhenConversionEnabled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let photo = try makeHEICImage(width: 4, height: 2, orientation: 1, userComment: nil)
    let store = InboxStore()
    let item = try await store.save(
        UploadRequest(body: photo, kind: .image),
        in: directory,
        convertScreenshotsToPNG: true
    )
    #expect(item.url.pathExtension == "heic")
    #expect(try Data(contentsOf: item.url) == photo)
}

@Test("开启截图转 PNG 时已是 PNG 的截图不重编码，保留原始字节")
func preservesPNGScreenshotWithoutReencoding() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try makePNGScreenshot()
    let store = InboxStore()
    let item = try await store.save(
        UploadRequest(body: png, kind: .image),
        in: directory,
        convertScreenshotsToPNG: true
    )
    #expect(item.url.pathExtension == "png")
    #expect(try Data(contentsOf: item.url) == png)
}

@Test("开启截图转 PNG 时支持识别 XMP exif:UserComment 截图标记")
func convertsXMPMarkedHEICScreenshotToPNG() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let heic = try makeXMPHEICScreenshot(width: 4, height: 2)
    let store = InboxStore()
    let item = try await store.save(
        UploadRequest(body: heic, kind: .image),
        in: directory,
        convertScreenshotsToPNG: true
    )
    #expect(item.url.pathExtension == "png")
    let savedData = try Data(contentsOf: item.url)
    let source = try #require(CGImageSourceCreateWithData(savedData as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
}

@Test("HTTPServer 动态读取截图转 PNG 开关，切换后无需重启即可生效")
func httpServerReadsConvertScreenshotsFlagDynamically() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = InboxStore()
    let server = HTTPServer(store: store)
    let port = UInt16.random(in: 20000 ... 45000)
    let configuration = ConnectionConfiguration.Receiver(
        port: port,
        directory: directory,
        token: "test-key"
    )
    let flag = OSAllocatedUnfairLock(initialState: false)
    let heic = try makeHEICImage(width: 4, height: 2, orientation: 1, userComment: "Screenshot")
    do {
        try await server.start(
            configuration: configuration,
            convertScreenshotsToPNG: { flag.withLock { $0 } },
            onReceive: { _ in },
            onFailure: { _ in }
        )
        var request = try URLRequest(url: #require(URL(string: "http://127.0.0.1:\(port)/upload")))
        request.httpMethod = "POST"
        request.setValue("test-key", forHTTPHeaderField: "X-AnyDock-Key")
        request.httpBody = heic
        let (_, firstResponse) = try await URLSession.shared.data(for: request)
        #expect((firstResponse as? HTTPURLResponse)?.statusCode == 201)

        flag.withLock { $0 = true }
        let (_, secondResponse) = try await URLSession.shared.data(for: request)
        #expect((secondResponse as? HTTPURLResponse)?.statusCode == 201)

        let listed = try await store.list(in: directory)
        let extensions = Set(listed.map(\.url.pathExtension))
        #expect(extensions == ["heic", "png"])
        await server.stop()
    } catch {
        await server.stop()
        throw error
    }
}

private func makeCGImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func makeHEICImage(
    width: Int,
    height: Int,
    orientation: Int,
    userComment: String?
) throws -> Data {
    let image = try makeCGImage(width: width, height: height)
    let bytes = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(bytes, UTType.heic.identifier as CFString, 1, nil)
    )
    var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
    if let userComment {
        properties[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifUserComment: userComment,
        ]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}

private func makePNGScreenshot() throws -> Data {
    let image = try makeCGImage(width: 4, height: 2)
    let bytes = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
    )
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifUserComment: "Screenshot",
        ],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}

private func makeXMPHEICScreenshot(width: Int, height: Int) throws -> Data {
    let image = try makeCGImage(width: width, height: height)
    let bytes = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(bytes, UTType.heic.identifier as CFString, 1, nil)
    )
    let metadata = CGImageMetadataCreateMutable()
    let registered = CGImageMetadataRegisterNamespaceForPrefix(
        metadata,
        kCGImageMetadataNamespaceExif,
        kCGImageMetadataPrefixExif,
        nil
    )
    #expect(registered)
    let tag = try #require(
        CGImageMetadataTagCreate(
            kCGImageMetadataNamespaceExif,
            kCGImageMetadataPrefixExif,
            kCGImagePropertyExifUserComment,
            .alternateText,
            "Screenshot" as CFString
        )
    )
    let set = CGImageMetadataSetTagWithPath(metadata, nil, "exif:UserComment" as CFString, tag)
    #expect(set)
    CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}
