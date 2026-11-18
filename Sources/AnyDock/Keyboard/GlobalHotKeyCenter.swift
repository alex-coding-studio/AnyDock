import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class GlobalHotKeyCenter {
    private let pressSubject = PassthroughSubject<Void, Never>()
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var requestedHotKey: KeyCombination?
    private var inputSourceChanges: AnyCancellable?

    var presses: AnyPublisher<Void, Never> {
        pressSubject.eraseToAnyPublisher()
    }

    var isRegistered: Bool {
        registration != nil
    }

    init() {
        let inputSourceChanged = Notification.Name(
            kTISNotifySelectedKeyboardInputSourceChanged as String
        )
        inputSourceChanges = DistributedNotificationCenter.default()
            .publisher(for: inputSourceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let hotKey = requestedHotKey, hotKey.modifiers == .command else {
                    return
                }
                _ = register(hotKey)
            }
    }

    func register(_ hotKey: KeyCombination?) -> Bool {
        requestedHotKey = hotKey
        if let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        guard let hotKey else {
            return true
        }
        guard !hotKey.isReservedForQuit, installHandler() else {
            return false
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            EventHotKeyID(signature: 0x414E_444B, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            return false
        }
        registration = reference
        return true
    }

    private func installHandler() -> Bool {
        guard handler == nil else {
            return true
        }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { center.pressSubject.send() }
                return noErr
            },
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        return status == noErr
    }
}
