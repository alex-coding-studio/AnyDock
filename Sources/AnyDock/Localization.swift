import Foundation

enum L10n {
    @TaskLocal static var bundle = Bundle.module

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
