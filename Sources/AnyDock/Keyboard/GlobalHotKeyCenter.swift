import Carbon.HIToolbox
import Combine

@MainActor
final class GlobalHotKeyCenter {
    private let pressSubject = PassthroughSubject<Void, Never>()
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var presses: AnyPublisher<Void, Never> {
        pressSubject.eraseToAnyPublisher()
    }

    var isRegistered: Bool {
        registration != nil
    }

    func register(_ hotKey: KeyCombination?) -> Bool {
        if let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        guard let hotKey else {
            return true
        }
        guard installHandler() else {
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
