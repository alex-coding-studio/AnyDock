import AnyDockCore
import AppKit
import Combine
import OSLog

enum InboxStatus: Equatable {
    case starting
    case listening(port: UInt16)
    case failed(String)
}

@MainActor
final class Inbox: TrayInbox {
    private(set) var configuration: ConnectionConfiguration

    private let store: ConnectionConfigurationStore
    private let inboxStore = InboxStore()
    private let statusSubject = CurrentValueSubject<InboxStatus, Never>(.starting)
    private let receivedSubject = PassthroughSubject<ReceivedItem, Never>()
    private let itemsSubject = PassthroughSubject<[ReceivedItem], Never>()
    private let logger = Logger(subsystem: "com.cuxiao.mac.anydock", category: "Receiver")

    private lazy var server = HTTPServer(store: inboxStore)

    var status: AnyPublisher<InboxStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var received: AnyPublisher<ReceivedItem, Never> {
        receivedSubject.eraseToAnyPublisher()
    }

    var items: AnyPublisher<[ReceivedItem], Never> {
        itemsSubject.eraseToAnyPublisher()
    }

    init(configuration: ConnectionConfiguration, store: ConnectionConfigurationStore) {
        self.configuration = configuration
        self.store = store
    }

    func start() async {
        await startReceiver(configuration.receiver)
        await reload()
    }

    func reload() async {
        let directory = configuration.receiver.directory
        do {
            let listed = try await inboxStore.list(in: directory)
            guard directory == configuration.receiver.directory else {
                return
            }
            itemsSubject.send(listed)
        } catch {
            fail(L10n.text("Unable to read the receive folder: %@", error.localizedDescription))
        }
    }

    func list() async throws -> [ReceivedItem] {
        let directory = configuration.receiver.directory
        let listed = try await inboxStore.list(in: directory)
        guard directory == configuration.receiver.directory else {
            throw CocoaError(.userCancelled)
        }
        return listed
    }

    func recycle(_ requested: [URL]) async throws {
        let allowed = try await Set(list().map(\.url))
        let urls = requested.filter { allowed.contains($0) }
        guard !urls.isEmpty else {
            return
        }
        let error: (any Error)? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { _, error in
                continuation.resume(returning: error)
            }
        }
        await reload()
        if let error {
            throw error
        }
    }

    func apply(sender: ConnectionConfiguration.Sender) throws {
        var next = configuration
        next.sender = sender
        try store.save(next)
        configuration = next
    }

    func apply(receiver: ConnectionConfiguration.Receiver) async throws {
        let changed = receiver != configuration.receiver
        if changed {
            try FileManager.default.createDirectory(
                at: receiver.directory,
                withIntermediateDirectories: true
            )
            guard FileManager.default.isWritableFile(atPath: receiver.directory.path) else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        var next = configuration
        next.receiver = receiver
        try store.save(next)
        configuration = next
        guard changed else {
            return
        }
        await reload()
        await startReceiver(receiver)
    }

    func openFolder() {
        let directory = configuration.receiver.directory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(directory)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func startReceiver(_ receiver: ConnectionConfiguration.Receiver) async {
        do {
            try await server.start(
                configuration: receiver,
                onReceive: { [weak self] item in
                    await self?.receive(item, directory: receiver.directory)
                },
                onFailure: { [weak self] message in
                    await self?.fail(message)
                }
            )
            statusSubject.send(.listening(port: receiver.port))
        } catch {
            fail(L10n.text(
                "Unable to listen on port %d: %@",
                Int(receiver.port),
                error.localizedDescription
            ))
        }
    }

    private func receive(_ item: ReceivedItem, directory: URL) {
        guard directory == configuration.receiver.directory else {
            return
        }
        receivedSubject.send(item)
    }

    private func fail(_ message: String) {
        logger.error("Listener failed: \(message, privacy: .public)")
        statusSubject.send(.failed(message))
    }
}
