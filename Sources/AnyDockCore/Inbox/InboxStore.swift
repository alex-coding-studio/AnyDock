import Foundation

public actor InboxStore {
    private var aspectRatios = [URL: (modified: Date, ratio: Double)]()

    public init() {}

    public func save(_ request: UploadRequest, in directory: URL) throws -> ReceivedItem {
        let content = try ReceivedContent.make(from: request)
        let writer = try ItemWriter(in: directory, kind: content.kind)
        let filename = Self.uniqueStem() + content.nameSuffix
        try writer.write(content.data, named: filename, quarantined: content.isQuarantined)
        let url = writer.directory.appendingPathComponent(filename)
        return ReceivedItem(
            url: url,
            kind: content.kind,
            thumbnail: content.thumbnail,
            receivedAt: Date(),
            isPlainText: content.isPlainText,
            aspectRatio: content.kind == .image ? ImagePreview.headerAspectRatio(at: url) : nil
        )
    }

    public func list(in directory: URL) throws -> [ReceivedItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let folders: [(URL, ReceivedKind)] =
            [(directory, .image)]
                + ReceivedKind.allCases.map {
                    (directory.appendingPathComponent($0.directoryName, isDirectory: true), $0)
                }
        var candidates = [Candidate]()
        for (folder, category) in folders {
            candidates += try Self.candidates(in: folder, kind: category)
        }
        let present = Set(candidates.map(\.url))
        aspectRatios = aspectRatios.filter { present.contains($0.key) }
        return candidates.sorted { $0.date > $1.date }.compactMap(item)
    }

    private func item(_ candidate: Candidate) -> ReceivedItem? {
        let url = candidate.url
        var ratio: Double?
        var plainText = false
        switch candidate.kind {
        case .image:
            guard let found = aspectRatio(of: candidate) else {
                return nil
            }
            ratio = found
        case .text:
            break
        case .link:
            guard Self.isWebLocation(url) else {
                return nil
            }
        case .file:
            plainText = FileTypeDetector.isPlainTextFile(url)
        }
        return ReceivedItem(
            url: url,
            kind: candidate.kind,
            thumbnail: nil,
            receivedAt: candidate.date,
            isPlainText: plainText,
            aspectRatio: ratio
        )
    }

    private func aspectRatio(of candidate: Candidate) -> Double? {
        if let cached = aspectRatios[candidate.url], cached.modified == candidate.modified {
            return cached.ratio
        }
        guard let ratio = ImagePreview.headerAspectRatio(at: candidate.url) else {
            return nil
        }
        aspectRatios[candidate.url] = (candidate.modified, ratio)
        return ratio
    }
}

extension InboxStore {
    private struct Candidate {
        let url: URL
        let date: Date
        let modified: Date
        let kind: ReceivedKind
    }

    private static let filenamePrefix = "AnyDock-"
    private static let folderKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
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
            guard url.lastPathComponent.hasPrefix(filenamePrefix),
                  let values = try? url.resourceValues(forKeys: fileKeys),
                  values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
                  size <= HTTPRequestDecoder.maximumBodySize
            else {
                return nil
            }
            return Candidate(
                url: url,
                date: values.creationDate ?? .distantPast,
                modified: values.contentModificationDate ?? .distantPast,
                kind: kind
            )
        }
    }

    private static func uniqueStem() -> String {
        "\(filenamePrefix)\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
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
}
