import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ReceivedImage: Sendable, Identifiable {
  public var id: URL { url }
  public let url: URL
  public let thumbnail: Data
  public let receivedAt: Date
}

public actor ImageStore {
  public init() {}

  public func save(_ data: Data, in directory: URL) throws -> ReceivedImage {
    let (thumbnail, fileExtension) = try Self.inspect(data)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let filename =
      "SnapDock-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).\(fileExtension)"
    let url = directory.appendingPathComponent(filename)
    try data.write(to: url, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return ReceivedImage(url: url, thumbnail: thumbnail, receivedAt: Date())
  }

  public func list(in directory: URL) throws -> [ReceivedImage] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey,
    ]
    let candidates = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
    )
    .filter { $0.lastPathComponent.hasPrefix("SnapDock-") }
    .compactMap { url -> (URL, Date)? in
      guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
        values.isSymbolicLink != true, let size = values.fileSize,
        size <= HTTPRequestDecoder.maximumBodySize
      else { return nil }
      return (url, values.creationDate ?? .distantPast)
    }.sorted { $0.1 > $1.1 }.prefix(120)
    return candidates.compactMap { url, date in
      guard let data = try? Data(contentsOf: url), let (thumbnail, _) = try? Self.inspect(data)
      else { return nil }
      return ReceivedImage(url: url, thumbnail: thumbnail, receivedAt: date)
    }
  }

  private static func inspect(_ data: Data) throws -> (Data, String) {
    guard !data.isEmpty, data.count <= HTTPRequestDecoder.maximumBodySize,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String),
      type.conforms(to: .image),
      let fileExtension = type.preferredFilenameExtension,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 80_000_000 / height,
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 640,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { throw HTTPFailure(415, "Unsupported Image") }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)
    else {
      throw HTTPFailure(500, "Image Processing Failed")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw HTTPFailure(500, "Image Processing Failed")
    }
    return (output as Data, fileExtension)
  }
}
