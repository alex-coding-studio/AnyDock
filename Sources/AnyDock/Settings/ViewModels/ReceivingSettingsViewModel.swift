import AnyDockCore
import Combine
import Foundation

struct ReceivingSettingsState: Equatable {
    var status: ListenerStatus
    var folder: URL
    var portText: String
    var hasChanges: Bool
    var isApplying: Bool
    var errorMessage: String?

    var canApply: Bool {
        hasChanges && !isApplying
    }

    var folderName: String {
        FileManager.default.displayName(atPath: folder.path)
    }

    var folderPath: String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }
}

@MainActor
final class ReceivingSettingsViewModel {
    static let portRange: ClosedRange<UInt16> = 1024 ... UInt16.max

    private let receiver: any ReceiverSettings
    private let stateSubject: CurrentValueSubject<ReceivingSettingsState, Never>
    private var subscriptions = Set<AnyCancellable>()

    var state: AnyPublisher<ReceivingSettingsState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var currentState: ReceivingSettingsState {
        stateSubject.value
    }

    init(receiver: any ReceiverSettings) {
        self.receiver = receiver
        let applied = receiver.configuration.receiver
        stateSubject = CurrentValueSubject(ReceivingSettingsState(
            status: ListenerStatus(.starting),
            folder: applied.directory,
            portText: String(applied.port),
            hasChanges: false,
            isApplying: false
        ))
        receiver.status
            .map(ListenerStatus.init)
            .sink { [weak self] status in self?.update { $0.status = status } }
            .store(in: &subscriptions)
    }

    private static func port(from text: String) -> UInt16? {
        UInt16(text.trimmingCharacters(in: .whitespaces))
    }

    func selectFolder(_ folder: URL) {
        update { $0.folder = folder }
    }

    func setPortText(_ text: String) {
        update { $0.portText = text }
    }

    func revert() {
        guard !stateSubject.value.isApplying else {
            return
        }
        let applied = receiver.configuration.receiver
        update {
            $0.folder = applied.directory
            $0.portText = String(applied.port)
            $0.errorMessage = nil
        }
    }

    func apply() {
        let current = stateSubject.value
        guard current.canApply else {
            return
        }
        guard let port = Self.port(from: current.portText), Self.portRange.contains(port) else {
            update { $0.errorMessage = L10n.text(
                "Enter a whole-number port between 1024 and 65535."
            ) }
            return
        }
        var next = receiver.configuration.receiver
        next.port = port
        next.directory = current.folder
        update {
            $0.isApplying = true
            $0.errorMessage = nil
        }
        Task {
            do {
                try await receiver.apply(receiver: next)
                update { $0.isApplying = false }
            } catch {
                update {
                    $0.isApplying = false
                    $0.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func update(_ change: (inout ReceivingSettingsState) -> Void) {
        var next = stateSubject.value
        change(&next)
        let applied = receiver.configuration.receiver
        next.hasChanges = next.folder != applied.directory || Self.port(
            from: next.portText
        ) != applied.port
        if next != stateSubject.value {
            stateSubject.send(next)
        }
    }
}
