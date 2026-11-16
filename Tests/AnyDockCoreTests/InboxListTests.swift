import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AnyDockCore

@Test("图片宽高比只读文件头，EXIF 方向 5–8 时宽高互换", arguments: [(1, 0.5), (6, 2.0)])
func listReadsOrientedAspectRatioFromHeader(orientation: Int, expected: Double) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let images = directory.appendingPathComponent("Images")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = images.appendingPathComponent("AnyDock-1-photo.jpg")
    try makeJPEG(width: 40, height: 20, orientation: orientation).write(to: url)
    let item = try #require(try await InboxStore().list(in: directory).first)
    #expect(item.aspectRatio == expected)
}

@Test("托盘列出全部收到的项目、从新到旧，且不解码图片内容")
func listReturnsEveryItemNewestFirstWithoutDecoding() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let images = directory.appendingPathComponent("Images")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let headerOnly = try makeImage().prefix(33)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    for index in 0 ..< 150 {
        let url = images.appendingPathComponent("AnyDock-\(index).png")
        try headerOnly.write(to: url)
        try FileManager.default.setAttributes(
            [.creationDate: start.addingTimeInterval(Double(index))],
            ofItemAtPath: url.path
        )
    }
    let listed = try await InboxStore().list(in: directory)
    #expect(listed.count == 150)
    #expect(listed.first?.url.lastPathComponent == "AnyDock-149.png")
    #expect(listed.last?.url.lastPathComponent == "AnyDock-0.png")
    #expect(listed.allSatisfy { $0.aspectRatio == 1 })
}

private func makeJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    )
    let bytes = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)
    )
    try CGImageDestinationAddImage(
        destination,
        #require(context.makeImage()),
        [kCGImagePropertyOrientation: orientation] as CFDictionary
    )
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}
