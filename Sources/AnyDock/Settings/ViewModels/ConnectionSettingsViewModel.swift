import Combine
import Foundation

struct SettingsMessage: Equatable {
    let text: String
    let isError: Bool
}

struct ConnectionSettingsState: Equatable {
    var shortcutName: String
    var nameMessage: SettingsMessage?
    var canSend: Bool
    var isSending: Bool
    var message: SettingsMessage?
    var receiveAddress: String
}

@MainActor
final class ConnectionSettingsViewModel {
    private let receiver: any ReceiverSettings
    private let host: any HostInformation
    private let sharing: any ShortcutSharing
    private let pasteboard: any SettingsPasteboard
    private let stateSubject: CurrentValueSubject<ConnectionSettingsState, Never>
    private var sharedFile: URL?
    private var subscriptions = Set<AnyCancellable>()

    var state: AnyPublisher<ConnectionSettingsState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var isSending: AnyPublisher<Bool, Never> {
        stateSubject.map(\.isSending).removeDuplicates().eraseToAnyPublisher()
    }

    var currentState: ConnectionSettingsState {
        stateSubject.value
    }

    init(
        receiver: any ReceiverSettings,
        host: any HostInformation,
        sharing: any ShortcutSharing,
        pasteboard: any SettingsPasteboard
    ) {
        self.receiver = receiver
        self.host = host
        self.sharing = sharing
        self.pasteboard = pasteboard
        stateSubject = CurrentValueSubject(ConnectionSettingsState(
            shortcutName: Self.initialName(receiver: receiver, host: host),
            canSend: false,
            isSending: false,
            receiveAddress: host.receiveAddress(port: receiver.configuration.receiver.port)
        ))
        validateName()
        receiver.status
            .sink { [weak self] _ in self?.refreshAddress() }
            .store(in: &subscriptions)
    }

    private static func initialName(
        receiver: any ReceiverSettings,
        host: any HostInformation
    ) -> String {
        if let saved = receiver.configuration.sender.shortcutName {
            return saved
        }
        if let name = host.computerName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !name.isEmpty {
            return L10n.text("Send to %@", name)
        }
        return L10n.text("Send to Mac")
    }

    private static func preparationMessage(for error: any Error) -> String {
        switch error as? ShortcutSharingError {
        case .airDropUnsupported: L10n.text("shortcut.airdrop.unsupported")
        case .templateMissing: L10n.text("shortcut.template.missing")
        default: L10n.text("Unable to send the shortcut: %@", error.localizedDescription)
        }
    }

    func setShortcutName(_ name: String) {
        update { $0.shortcutName = name }
        validateName()
    }

    func copyReceiveAddress() {
        pasteboard.copy(stateSubject.value.receiveAddress, concealed: false)
    }

    func copyConnectionKey() {
        pasteboard.copy(receiver.configuration.receiver.token, concealed: true)
    }

    func exportGenericShortcut(to destination: URL) {
        do {
            try sharing.exportGenericShortcut(to: destination)
        } catch ShortcutSharingError.resourceMissing {
            show(L10n.text("shortcut.resource.missing"))
        } catch {
            show(L10n.text("Export failed: %@", error.localizedDescription))
        }
    }

    func send() {
        guard stateSubject.value.canSend else {
            return
        }
        if sharedFile != nil, !cleanUpSharedFile() {
            return
        }
        guard let name = try? ShortcutInstaller.normalizedName(
            stateSubject.value.shortcutName
        ) else {
            validateName()
            return
        }
        let address = stateSubject.value.receiveAddress
        let key = receiver.configuration.receiver.token
        update {
            $0.shortcutName = name
            $0.isSending = true
        }
        validateName()
        show(L10n.text("Creating and signing the shortcut…"), isError: false)
        Task { await deliver(address: address, key: key, name: name) }
    }

    private func deliver(address: String, key: String, name: String) async {
        defer { finishSending() }
        do {
            sharedFile = try await sharing.prepare(address: address, key: key, name: name)
        } catch {
            show(Self.preparationMessage(for: error))
            return
        }
        guard let file = sharedFile else {
            return
        }
        show(L10n.text("shortcut.airdrop.choosePhone"), isError: false)
        do {
            try await sharing.share(file)
        } catch {
            if cleanUpSharedFile() {
                show(error as? ShortcutSharingError == .airDropUnavailable
                    ? L10n.text("shortcut.airdrop.unavailable")
                    : L10n.text("shortcut.airdrop.failed", error.localizedDescription))
            }
            return
        }
        let saved = saveShortcutName(name)
        if cleanUpSharedFile(), saved {
            show(L10n.text("shortcut.airdrop.sent"), isError: false)
        }
    }

    private func finishSending() {
        update { $0.isSending = false }
        validateName()
    }

    private func saveShortcutName(_ name: String) -> Bool {
        do {
            var sender = receiver.configuration.sender
            sender.shortcutName = name
            try receiver.apply(sender: sender)
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    private func cleanUpSharedFile() -> Bool {
        guard let file = sharedFile else {
            return true
        }
        do {
            try sharing.cleanUp(file)
            sharedFile = nil
            return true
        } catch {
            show(L10n.text("shortcut.cleanup.failed", error.localizedDescription))
            return false
        }
    }

    private func validateName() {
        let current = stateSubject.value
        do {
            let name = try ShortcutInstaller.normalizedName(current.shortcutName)
            update {
                $0.nameMessage = name == current.shortcutName
                    ? nil : SettingsMessage(
                        text: L10n.text("shortcut.name.normalized", name),
                        isError: false
                    )
                $0.canSend = !current.isSending && !receiver.configuration.receiver.token.isEmpty
            }
        } catch {
            update {
                $0.nameMessage = SettingsMessage(text: error.localizedDescription, isError: true)
                $0.canSend = false
            }
        }
    }

    private func refreshAddress() {
        let address = host.receiveAddress(port: receiver.configuration.receiver.port)
        update { $0.receiveAddress = address }
    }

    private func show(_ text: String, isError: Bool = true) {
        update { $0.message = SettingsMessage(text: text, isError: isError) }
    }

    private func update(_ change: (inout ConnectionSettingsState) -> Void) {
        var next = stateSubject.value
        change(&next)
        if next != stateSubject.value {
            stateSubject.send(next)
        }
    }
}
