import AppKit

@MainActor
enum AppAppearance: String, CaseIterable {
  case system
  case light
  case dark

  static var current: AppAppearance {
    AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
  }

  func apply() {
    switch self {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }
}
