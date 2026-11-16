import AnyDockCore
import Combine
import Foundation
import PockyFoundation

@MainActor
protocol ReceiverSettings: AnyObject {
    var configuration: ConnectionConfiguration { get }
    var status: AnyPublisher<InboxStatus, Never> { get }
    func apply(receiver: ConnectionConfiguration.Receiver) async throws
    func apply(sender: ConnectionConfiguration.Sender) throws
}

@MainActor
protocol SettingsPreferences: AnyObject {
    var appearance: PKYAppearance.Mode { get set }
    var language: AppLanguage { get set }
    var copiesNewItems: Bool { get set }
    var keepsClipboardHistory: Bool { get set }
    var wakeHotKey: KeyCombination? { get set }
}

@MainActor
protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
protocol WakeHotKeyRegistering: AnyObject {
    var isRegistered: Bool { get }
    func register(_ hotKey: KeyCombination?) -> Bool
}

@MainActor
protocol ApplicationRestarting: AnyObject {
    var canRestart: Bool { get }
    func restart() throws
}

@MainActor
protocol HostInformation: AnyObject {
    var computerName: String? { get }
    func receiveAddress(port: UInt16) -> String
}

@MainActor
protocol SettingsPasteboard: AnyObject {
    func copy(_ text: String, concealed: Bool)
}

enum ShortcutSharingError: Error, Equatable {
    case airDropUnsupported
    case airDropUnavailable
    case templateMissing
    case resourceMissing
}

@MainActor
protocol ShortcutSharing: AnyObject {
    func prepare(address: String, key: String, name: String) async throws -> URL
    func share(_ file: URL) async throws
    func cleanUp(_ file: URL) throws
    func exportGenericShortcut(to destination: URL) throws
}

extension Inbox: ReceiverSettings {}

extension GlobalHotKeyCenter: WakeHotKeyRegistering {}
