import AppKit

@MainActor
final class AirDropShortcutSharing: NSObject, ShortcutSharing, NSSharingServiceDelegate {
    private var service: NSSharingService?
    private var continuation: CheckedContinuation<Void, any Error>?

    func prepare(address: String, key: String, name: String) async throws -> URL {
        guard NSSharingService(named: .sendViaAirDrop) != nil else {
            throw ShortcutSharingError.airDropUnsupported
        }
        guard
            let template = Bundle.main.url(
                forResource: "Template",
                withExtension: "shortcut",
                subdirectory: "Shortcuts"
            )
        else {
            throw ShortcutSharingError.templateMissing
        }
        return try await Task.detached {
            try ShortcutInstaller.prepare(
                templateURL: template,
                address: address,
                key: key,
                name: name
            )
        }.value
    }

    func share(_ file: URL) async throws {
        guard continuation == nil, let service = NSSharingService(named: .sendViaAirDrop) else {
            throw ShortcutSharingError.airDropUnsupported
        }
        guard service.canPerform(withItems: [file]) else {
            throw ShortcutSharingError.airDropUnavailable
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.service = service
            service.delegate = self
            service.perform(withItems: [file])
        }
    }

    func cleanUp(_ file: URL) throws {
        try ShortcutInstaller.cleanUp(file)
    }

    func exportGenericShortcut(to destination: URL) throws {
        guard
            let source = Bundle.main.url(
                forResource: "发送到 Mac",
                withExtension: "shortcut",
                subdirectory: "Shortcuts"
            )
        else {
            throw ShortcutSharingError.resourceMissing
        }
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) {
        finish(with: nil)
    }

    func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error: any Error) {
        finish(with: error)
    }

    func sharingService(
        _: NSSharingService,
        sourceWindowForShareItems _: [Any],
        sharingContentScope _: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        NSApp.keyWindow
    }

    private func finish(with error: (any Error)?) {
        let continuation = continuation
        self.continuation = nil
        service = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
