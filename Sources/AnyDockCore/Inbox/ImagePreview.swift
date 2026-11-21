import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImagePreview {
    private static let maximumPixelCount = 80_000_000
    private static let maximumThumbnailSize = 640
    private static let screenshotMarker = "Screenshot"
    private static let normalOrientation = 1
    private static let transformedOrientations = 2 ... 8
    private static let exifUserCommentPath = "exif:UserComment"

    private static var uncached: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    let png: Data
    let originalExtension: String
    let storedData: Data
    let storedExtension: String

    init(_ data: Data, convertScreenshotToPNG: Bool = false) throws {
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
        if convertScreenshotToPNG,
           type != .png,
           CGImageSourceGetCount(source) == 1,
           Self.isScreenshot(source),
           let converted = Self.convertToPNG(source: source),
           converted.count <= HTTPRequestDecoder.maximumBodySize {
            storedData = converted
            storedExtension = UTType.png.preferredFilenameExtension ?? "png"
        } else {
            storedData = data
            storedExtension = originalExtension
        }
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

    private static func isScreenshot(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        if let comment = exif?[kCGImagePropertyExifUserComment] as? String,
           isScreenshotComment(comment) {
            return true
        }
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return false
        }
        if let value = CGImageMetadataCopyStringValueWithPath(
            metadata,
            nil,
            exifUserCommentPath as CFString
        ) as String?, isScreenshotComment(value) {
            return true
        }
        if let tag = CGImageMetadataCopyTagWithPath(
            metadata,
            nil,
            exifUserCommentPath as CFString
        ), let values = CGImageMetadataTagCopyValue(tag) as? [Any] {
            for index in values.indices {
                let path = "\(exifUserCommentPath)[\(index + 1)]" as CFString
                if let entry = CGImageMetadataCopyStringValueWithPath(
                    metadata,
                    nil,
                    path
                ) as String?, isScreenshotComment(entry) {
                    return true
                }
            }
        }
        return false
    }

    private static func isScreenshotComment(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
        )
        return trimmed.caseInsensitiveCompare(screenshotMarker) == .orderedSame
    }

    private static func convertToPNG(source: CGImageSource) -> Data? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? normalOrientation
        let fullImage: CGImage? = if transformedOrientations.contains(orientation),
                                     width > 0, height > 0 {
            CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        } else {
            CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let fullImage else {
            return nil
        }
        let pngProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: normalOrientation,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: screenshotMarker,
            ],
        ]
        return try? encodePNG(fullImage, properties: pngProperties)
    }

    private static func encodePNG(
        _ image: CGImage,
        properties: [CFString: Any]? = nil
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw UploadError.imageProcessingFailed
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else {
            throw UploadError.imageProcessingFailed
        }
        return output as Data
    }
}
