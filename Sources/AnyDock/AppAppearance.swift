import AppKit

@MainActor
enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    static var current: AppAppearance {
        Preferences.appearance
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
