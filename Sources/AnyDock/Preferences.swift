// swiftformat:disable redundantRawValues

import Combine
import Foundation
import PockyFoundation

@MainActor
enum Preferences {
    enum Key: String {
        case appearance = "appearance"
        case convertScreenshotsToPNG = "convertScreenshotsToPNG"
        case copyNewItems = "copyNewItems"
        case hasRequestedNotificationPermission = "hasRequestedNotificationPermission"
        case keepClipboardHistory = "keepClipboardHistory"
        case receiveNotifications = "receiveNotifications"
        case openTrayOnArrival = "openTrayOnArrival"
        case wakeHotKey = "wakeHotKey"
    }

    static let appearance = PKYAppearance(key: Key.appearance.rawValue)

    static var copiesNewItems: Bool {
        get { defaults.bool(forKey: Key.copyNewItems.rawValue) }
        set { defaults.set(newValue, forKey: Key.copyNewItems.rawValue) }
    }

    static var keepsClipboardHistory: Bool {
        get { defaults.object(forKey: Key.keepClipboardHistory.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepClipboardHistory.rawValue) }
    }

    static var receiveNotifications: Bool {
        get { defaults.bool(forKey: Key.receiveNotifications.rawValue) }
        set { defaults.set(newValue, forKey: Key.receiveNotifications.rawValue) }
    }

    static var hasReceiveNotificationsPreference: Bool {
        defaults.object(forKey: Key.receiveNotifications.rawValue) != nil
    }

    static var hasRequestedNotificationPermission: Bool {
        get { defaults.bool(forKey: Key.hasRequestedNotificationPermission.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasRequestedNotificationPermission.rawValue) }
    }

    static var opensTrayOnArrival: Bool {
        get { defaults.object(forKey: Key.openTrayOnArrival.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.openTrayOnArrival.rawValue) }
    }

    static var wakeHotKey: KeyCombination? {
        get { KeyCombination(preference: defaults.object(forKey: Key.wakeHotKey.rawValue)) }
        set { defaults.set(newValue?.preference, forKey: Key.wakeHotKey.rawValue) }
    }

    nonisolated static var convertsScreenshotsToPNG: Bool {
        get { UserDefaults.standard.bool(forKey: Key.convertScreenshotsToPNG.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: Key.convertScreenshotsToPNG.rawValue) }
    }

    nonisolated static var keepsClipboardHistoryChanges: AnyPublisher<Bool, Never> {
        let read = { UserDefaults.standard.object(
            forKey: Key.keepClipboardHistory.rawValue
        ) as? Bool ?? true }
        return NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .receive(on: DispatchQueue.main)
            .map { _ in read() }
            .prepend(read())
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static var defaults: UserDefaults {
        .standard
    }
}
