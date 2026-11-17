import AnyDockCore
import Combine
import Foundation
import PockyFoundation
@testable import AnyDock

@MainActor
final class FakeReceiver: ReceiverSettings {
    let statusSubject = CurrentValueSubject<InboxStatus, Never>(.starting)
    var configuration: ConnectionConfiguration
    var appliedReceivers = [ConnectionConfiguration.Receiver]()
    var savedSenders = [ConnectionConfiguration.Sender]()
    var applyError: (any Error)?

    var status: AnyPublisher<InboxStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    init(port: UInt16 = 8765, shortcutName: String? = nil) {
        configuration = ConnectionConfiguration(
            receiver: .init(
                port: port,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "AnyDockTests-\(UUID().uuidString)"
                ),
                token: String(repeating: "k", count: 32)
            ),
            sender: .init(shortcutName: shortcutName)
        )
    }

    func apply(receiver: ConnectionConfiguration.Receiver) async throws {
        if let applyError {
            throw applyError
        }
        appliedReceivers.append(receiver)
        configuration.receiver = receiver
    }

    func apply(sender: ConnectionConfiguration.Sender) throws {
        savedSenders.append(sender)
        configuration.sender = sender
    }
}

@MainActor
final class FakePreferences: SettingsPreferences {
    var appearance = PKYAppearance.Mode.system
    var language = AppLanguage.system
    var copiesNewItems = false
    var keepsClipboardHistory = true
    var wakeHotKey: KeyCombination?
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var requiresApproval = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}

@MainActor
final class FakeHotKeys: WakeHotKeyRegistering {
    var unavailable = Set<UInt32>()
    private(set) var registered: KeyCombination?

    var isRegistered: Bool {
        registered != nil
    }

    func register(_ hotKey: KeyCombination?) -> Bool {
        guard let hotKey else {
            registered = nil
            return true
        }
        guard !unavailable.contains(hotKey.keyCode) else {
            registered = nil
            return false
        }
        registered = hotKey
        return true
    }
}

@MainActor
final class FakeRestarter: ApplicationRestarting {
    var canRestart = true
    var restarts = 0

    func restart() throws {
        restarts += 1
    }
}

@MainActor
final class FakeHost: HostInformation {
    var computerName: String?

    init(computerName: String? = nil) {
        self.computerName = computerName
    }

    func receiveAddress(port: UInt16) -> String {
        "http://test.local:\(port)/upload"
    }
}

@MainActor
final class FakePasteboard: SettingsPasteboard {
    var copies = [(text: String, concealed: Bool)]()

    func copy(_ text: String, concealed: Bool) {
        copies.append((text, concealed))
    }
}

@MainActor
final class FakeSharing: ShortcutSharing {
    var shareError: (any Error)?
    var prepareError: (any Error)?
    var cleanedUp = [URL]()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
        "AnyDockTests-\(UUID().uuidString).shortcut"
    )

    func prepare(address _: String, key _: String, name _: String) async throws -> URL {
        if let prepareError {
            throw prepareError
        }
        return file
    }

    func share(_: URL) async throws {
        if let shareError {
            throw shareError
        }
    }

    func cleanUp(_ file: URL) throws {
        cleanedUp.append(file)
    }

    func exportGenericShortcut(to _: URL) throws {}
}
