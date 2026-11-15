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

  static func follow(_ popover: NSPopover) -> NSKeyValueObservation {
    NSApp.observe(\.effectiveAppearance, options: [.initial]) { [weak popover] _, _ in
      MainActor.assumeIsolated { popover?.appearance = NSApp.effectiveAppearance }
    }
  }
}
