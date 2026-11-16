import AnyDockCore
import AppKit
import Combine
import QuickLookThumbnailing

@MainActor
final class TrayPreviewCache {
    private static let countLimit = 200
    private static let costLimit = 200 * 1024 * 1024
    private static let bytesPerPixel = 4

    private let loadedSubject = PassthroughSubject<URL, Never>()
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = TrayPreviewCache.countLimit
        cache.totalCostLimit = TrayPreviewCache.costLimit
        return cache
    }()

    private var versions = [URL: Int]()
    private var keysByURL = [URL: Set<NSString>]()
    private var pending = [URL: UUID]()
    private var failed = Set<NSString>()

    var loaded: AnyPublisher<URL, Never> {
        loadedSubject.eraseToAnyPublisher()
    }

    static func cost(of size: CGSize) -> Int {
        Int(max(size.width, 0) * max(size.height, 0)) * bytesPerPixel
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: key(for: url))
    }

    func store(_ data: Data, for url: URL) {
        guard let image = NSImage(data: data) else {
            return
        }
        insert(image, cost: Self.cost(of: image.size), key: key(for: url), url: url)
    }

    func load(_ entry: TrayEntry) {
        let url = entry.url
        let key = key(for: url)
        guard pending[url] == nil, !failed.contains(key), cache.object(forKey: key) == nil else {
            return
        }
        let generation = UUID()
        let version = versions[url, default: 0]
        pending[url] = generation
        let finish: @MainActor @Sendable (CGImage?) -> Void = { [weak self] image in
            self?.finish(url, key: key, image: image, generation: generation, version: version)
        }
        guard entry.kind == .file else {
            Task.detached(priority: .userInitiated) {
                let image = ImagePreview.thumbnail(at: url)
                await finish(image)
            }
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(
                width: TrayMetrics.fileThumbnailSide,
                height: TrayMetrics.fileThumbnailSide
            ),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        if url.pathExtension.isEmpty, let type = entry.contentType {
            request.contentType = type
        }
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.cgImage
            Task { @MainActor in finish(image) }
        }
    }

    func forget(_ urls: some Sequence<URL>) {
        for url in urls {
            versions[url, default: 0] += 1
            pending[url] = nil
            for key in keysByURL.removeValue(forKey: url) ?? [] {
                cache.removeObject(forKey: key)
                failed.remove(key)
            }
        }
    }

    private func finish(
        _ url: URL,
        key: NSString,
        image: CGImage?,
        generation: UUID,
        version: Int
    ) {
        if pending[url] == generation {
            pending[url] = nil
        }
        guard version == versions[url, default: 0] else {
            return
        }
        guard let image else {
            failed.insert(key)
            keysByURL[url, default: []].insert(key)
            return
        }
        let size = CGSize(width: image.width, height: image.height)
        insert(NSImage(cgImage: image, size: .zero), cost: Self.cost(of: size), key: key, url: url)
        loadedSubject.send(url)
    }

    private func insert(_ image: NSImage, cost: Int, key: NSString, url: URL) {
        cache.setObject(image, forKey: key, cost: cost)
        keysByURL[url, default: []].insert(key)
    }

    private func key(for url: URL) -> NSString {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        return "\(url.path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }
}
