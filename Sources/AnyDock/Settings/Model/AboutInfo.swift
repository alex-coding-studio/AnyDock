import Foundation

struct AboutInfo: Equatable {
    static let repositoryURL = URL(string: "https://github.com/alex-coding-studio/AnyDock")
    static let authorURL = URL(string: "https://github.com/Cunqi")

    let version: String?

    init(version: String?) {
        self.version = version
    }

    init(bundle: Bundle) {
        guard
            let version = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            version = nil
            return
        }
        self.version = L10n.text("Version %@ (%@)", version, build)
    }
}
