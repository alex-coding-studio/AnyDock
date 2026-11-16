// swiftformat:disable redundantRawValues

import Foundation

@MainActor
enum Preferences {
    enum Key: String {
        case appearance = "appearance"
        case copyNewItems = "copyNewItems"
        case keepClipboardHistory = "keepClipboardHistory"
        case wakeHotKey = "wakeHotKey"
        case personalizedShortcutName = "personalizedShortcutName"
    }

    static var copiesNewItems: Bool {
        get { defaults.bool(forKey: Key.copyNewItems.rawValue) }
        set { defaults.set(newValue, forKey: Key.copyNewItems.rawValue) }
    }

    static var keepsClipboardHistory: Bool {
        get { defaults.object(forKey: Key.keepClipboardHistory.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepClipboardHistory.rawValue) }
    }

    static var appearance: AppAppearance {
        get {
            AppAppearance(rawValue: defaults.string(forKey: Key.appearance.rawValue) ?? "")
                ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance.rawValue) }
    }

    static var wakeHotKey: HotKey? {
        get { HotKey(preference: defaults.object(forKey: Key.wakeHotKey.rawValue)) }
        set { defaults.set(newValue?.preference, forKey: Key.wakeHotKey.rawValue) }
    }

    static var shortcutName: String? {
        get { defaults.string(forKey: Key.personalizedShortcutName.rawValue) }
        set { defaults.set(newValue, forKey: Key.personalizedShortcutName.rawValue) }
    }

    private static var defaults: UserDefaults {
        .standard
    }
}
