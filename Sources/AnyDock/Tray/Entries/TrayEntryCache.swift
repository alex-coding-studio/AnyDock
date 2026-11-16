import AnyDockCore
import Foundation

@MainActor
final class TrayEntryCache {
    private var entries = [URL: TrayEntry]()

    func entry(for item: ReceivedItem) -> TrayEntry {
        if let cached = entries[item.url] {
            return cached
        }
        let entry = TrayEntry(item: item)
        entries[item.url] = entry
        return entry
    }

    func invalidate(_ url: URL) {
        entries[url] = nil
    }

    func keep(only present: Set<URL>) -> [URL] {
        let removed = entries.keys.filter { !present.contains($0) }
        for url in removed {
            entries[url] = nil
        }
        return removed
    }
}
