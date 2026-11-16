import Quartz

final class TrayQuickLookSource: NSObject, QLPreviewPanelDataSource {
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func numberOfPreviewItems(in _: QLPreviewPanel?) -> Int {
        urls.count
    }

    func previewPanel(_: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
        urls[index] as NSURL
    }
}
