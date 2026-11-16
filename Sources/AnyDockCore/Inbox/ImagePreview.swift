import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImagePreview {
    private static let maximumPixelCount = 80_000_000
    private static let maximumThumbnailSize = 640

    private static var uncached: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    let png: Data
    let originalExtension: String

    init(_ data: Data) throws {
        guard !data.isEmpty, data.count <= HTTPRequestDecoder.maximumBodySize,
              let source = Self.source(data),
              let type = Self.type(of: source), type.conforms(to: .image),
              let originalExtension = type.preferredFilenameExtension,
              Self.hasAcceptableSize(source),
              let image = Self.thumbnail(from: source)
        else {
            throw UploadError.unsupportedImage
        }
        png = try Self.encodePNG(image)
        self.originalExtension = originalExtension
    }

    public static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, uncached),
              hasAcceptableSize(source)
        else {
            return nil
        }
        return thumbnail(from: source)
    }

    static func headerAspectRatio(at url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, uncached),
              type(of: source)?.conforms(to: .image) == true
        else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            return 1
        }
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        return (5 ... 8).contains(orientation)
            ? Double(width) / Double(height) : Double(height) / Double(width)
    }

    static func isImage(_ data: Data) -> Bool {
        source(data).flatMap(type)?.conforms(to: .image) == true
    }

    private static func source(_ data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, uncached)
    }

    private static func type(of source: CGImageSource) -> UTType? {
        CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    }

    private static func hasAcceptableSize(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int
        else {
            return false
        }
        return width > 0 && height > 0 && width <= maximumPixelCount / height
    }

    private static func thumbnail(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumThumbnailSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw UploadError.imageProcessingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UploadError.imageProcessingFailed
        }
        return output as Data
    }
}
