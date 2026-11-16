import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor InboxStore {
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

    public func list(in directory: URL, kind: ReceivedKind? = nil) throws -> [ReceivedItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let folders: [(URL, ReceivedKind)] =
            [(directory, .image)]
                + ReceivedKind.allCases.map {
                    (directory.appendingPathComponent($0.directoryName, isDirectory: true), $0)
                }
        var candidates = [Candidate]()
        for (folder, category) in folders where kind == nil || kind == category {
            candidates += try Self.candidates(in: folder, kind: category)
        }
        let newest = candidates.sorted { $0.date > $1.date }.prefix(Self.maximumListedItems)
        return newest.compactMap(Self.item)
    }
}

extension InboxStore {
    private struct Candidate {
        let url: URL
        let date: Date
        let kind: ReceivedKind
    }

    private static let maximumListedItems = 120
    private static let folderKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .creationDateKey,
    ]

    private static func candidates(in folder: URL, kind: ReceivedKind) throws -> [Candidate] {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return []
        }
        let folderValues = try folder.resourceValues(forKeys: folderKeys)
        guard folderValues.isDirectory == true, folderValues.isSymbolicLink != true else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(fileKeys),
            options: .skipsHiddenFiles
        )
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("AnyDock-"),
                  let values = try? url.resourceValues(forKeys: fileKeys),
                  values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
                  size <= HTTPRequestDecoder.maximumBodySize
            else {
                return nil
            }
            return Candidate(url: url, date: values.creationDate ?? .distantPast, kind: kind)
        }
    }

    private static func item(_ candidate: Candidate) -> ReceivedItem? {
        let url = candidate.url
        var thumbnail: Data?
        var plainText = false
        switch candidate.kind {
        case .image:
            guard let data = try? Data(contentsOf: url), let inspected = try? inspect(data) else {
                return nil
            }
            thumbnail = inspected.0
        case .text:
            guard (try? String(contentsOf: url, encoding: .utf8)) != nil else {
                return nil
            }
        case .link:
            guard isWebLocation(url) else {
                return nil
            }
        case .file:
            plainText = isPlainTextFile(url)
        }
        return ReceivedItem(
            url: url,
            kind: candidate.kind,
            thumbnail: thumbnail,
            receivedAt: candidate.date,
            isPlainText: plainText
        )
    }

    private static func isWebLocation(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let property = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let address = (property as? [String: String])?["URL"]
        else {
            return false
        }
        return UploadRequest.webURL(address) != nil
    }

    private static func isPlainTextFile(_ url: URL) -> Bool {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true,
              let data = try? Data(contentsOf: url)
        else {
            return false
        }
        return isPlainText(data, filename: url.lastPathComponent)
    }
}
