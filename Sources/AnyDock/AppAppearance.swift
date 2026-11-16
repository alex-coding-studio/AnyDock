import AppKit

@MainActor
enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    static var current: AppAppearance {
        Preferences.appearance
    }

    static func follow(_ popover: NSPopover) -> NSKeyValueObservation {
        NSApp.observe(\.effectiveAppearance, options: [.initial]) { [weak popover] _, _ in
            MainActor.assumeIsolated { popover?.appearance = NSApp.effectiveAppearance }
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
