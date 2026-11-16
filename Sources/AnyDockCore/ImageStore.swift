import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ReceivedImage: Sendable, Identifiable {
    public let url: URL
    public let thumbnail: Data
    public let receivedAt: Date

    public var id: URL {
        url
    }
}

public actor ImageStore {
    public init() {}

    private static func nameMatchingContent(_ filename: String, data: Data) -> String {
        let signatures: [(offset: Int, bytes: [UInt8], type: UTType)] = [
            (0, Array("%PDF-".utf8), .pdf),
            (0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], .png),
            (0, [0xFF, 0xD8, 0xFF], .jpeg),
            (0, Array("GIF8".utf8), .gif),
            (4, Array("ftypheic".utf8), .heic),
            (4, Array("ftypheix".utf8), .heic),
            (0, [0x50, 0x4B, 0x03, 0x04], .zip),
        ]
        guard
            let type = signatures.first(
                where: { data.dropFirst($0.offset).starts(with: $0.bytes) }
            )?
            .type,
            let fileExtension = type.preferredFilenameExtension
        else {
            return filename
        }
        let current = (filename as NSString).pathExtension
        if !current.isEmpty, let declared = UTType(filenameExtension: current), declared.isDeclared {
            let detectable = signatures.contains { declared.conforms(to: $0.type) }
            if declared.conforms(to: type) || !(detectable || declared.conforms(to: .text)) {
                return filename
            }
        }
        return filename + "." + fileExtension
    }

    private static func isPlainText(_ data: Data, filename: String) -> Bool {
        let extensionName = (filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: extensionName), type.conforms(to: .text),
              !data.contains(0), String(data: data, encoding: .utf8) != nil
        else {
            return false
        }
        return true
    }

    private static func inspect(_ data: Data) throws -> (Data, String) {
        guard !data.isEmpty, data.count <= HTTPRequestDecoder.maximumBodySize,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String),
              type.conforms(to: .image),
              let fileExtension = type.preferredFilenameExtension,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [
                  CFString: Any
              ],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 80_000_000 / height,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 640,
                      kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary
              )
        else {
            throw UploadError.unsupportedImage
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw UploadError.imageProcessingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UploadError.imageProcessingFailed
        }
        return (output as Data, fileExtension)
    }

    public func save(_ data: Data, in directory: URL) throws -> ReceivedImage {
        let item = try save(UploadRequest(body: data, kind: .image), in: directory)
        guard let image = item.image else {
            throw UploadError.unsupportedImage
        }
        return image
    }

    public func save(_ request: UploadRequest, in directory: URL) throws -> ReceivedItem {
        var kind = request.kind
        var thumbnail: Data?
        var suffix: String
        var data = request.body
        let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        )
        let imageType = source.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
        if kind == .image || (kind == .file && imageType?.conforms(to: .image) == true) {
            let inspected = try Self.inspect(data)
            kind = .image
            thumbnail = inspected.0
            suffix = "." + inspected.1
        } else {
            switch kind {
            case .image: throw UploadError.unsupportedImage
            case .text: suffix = ".txt"
            case .link:
                let address = String(decoding: data, as: UTF8.self)
                data = try PropertyListSerialization.data(
                    fromPropertyList: ["URL": address],
                    format: .xml,
                    options: 0
                )
                suffix = ".webloc"
            case .file:
                guard let filename = request.filename else {
                    throw UploadError.filenameRequired
                }
                guard request.contentType?.hasPrefix("image/") != true else {
                    throw UploadError.unsupportedImage
                }
                suffix = "-" + Self.nameMatchingContent(filename, data: data)
            }
        }
        guard data.count <= HTTPRequestDecoder.maximumBodySize else {
            throw UploadError.payloadTooLarge
        }
        let writer = try ItemWriter(in: directory, kind: kind)
        let stem = "AnyDock-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let url = writer.directory.appendingPathComponent(stem + suffix)
        try writer.write(data, named: url.lastPathComponent, quarantined: kind != .image)
        return ReceivedItem(
            url: url,
            kind: kind,
            thumbnail: thumbnail,
            receivedAt: Date(),
            isPlainText: kind == .file && Self.isPlainText(data, filename: url.lastPathComponent)
        )
    }

    public func listImages(in directory: URL) throws -> [ReceivedImage] {
        try list(in: directory, kind: .image).compactMap(\.image)
    }

    public func list(in directory: URL, kind: ReceivedKind? = nil) throws -> [ReceivedItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        var candidates = [(URL, Date, ReceivedKind)]()
        let folders: [(URL, ReceivedKind)] =
            [(directory, .image)]
                + ReceivedKind.allCases.map {
                    (directory.appendingPathComponent($0.directoryName, isDirectory: true), $0)
                }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .creationDateKey,
        ]
        for (folder, category) in folders where kind == nil || kind == category {
            guard FileManager.default.fileExists(atPath: folder.path) else {
                continue
            }
            let folderValues = try folder.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard folderValues.isDirectory == true, folderValues.isSymbolicLink != true else {
                continue
            }
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            )
            for url in urls {
                guard url.lastPathComponent.hasPrefix("AnyDock-") else {
                    continue
                }
                guard let values = try? url.resourceValues(
                    forKeys: keys
                ), values.isRegularFile == true,
                values.isSymbolicLink != true, let size = values.fileSize,
                size <= HTTPRequestDecoder.maximumBodySize
                else {
                    continue
                }
                candidates.append((url, values.creationDate ?? .distantPast, category))
            }
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(120).compactMap { url, date, category in
            var thumbnail: Data?
            var plainText = false
            switch category {
            case .image:
                guard let data = try? Data(contentsOf: url), let inspected = try? Self.inspect(data)
                else {
                    return nil
                }
                thumbnail = inspected.0
            case .text:
                guard (try? String(contentsOf: url, encoding: .utf8)) != nil else {
                    return nil
                }
            case .link:
                guard let data = try? Data(contentsOf: url),
                      let property = try? PropertyListSerialization.propertyList(
                          from: data,
                          format: nil
                      ),
                      let address = (property as? [String: String])?["URL"],
                      UploadRequest.webURL(address) != nil
                else {
                    return nil
                }
            case .file:
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true,
                   let data = try? Data(contentsOf: url) {
                    plainText = Self.isPlainText(data, filename: url.lastPathComponent)
                }
            }
            return ReceivedItem(
                url: url,
                kind: category,
                thumbnail: thumbnail,
                receivedAt: date,
                isPlainText: plainText
            )
        }
    }
}
