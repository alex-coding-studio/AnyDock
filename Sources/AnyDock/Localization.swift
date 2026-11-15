import Foundation

enum L10n {
  static func text(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .module, comment: "")
    return String(format: format, locale: Locale.current, arguments: arguments)
  }
}
