enum SettingsSection: Int, CaseIterable {
    case general
    case connection
    case receiving
    case about

    var title: String {
        switch self {
        case .general: L10n.text("General")
        case .connection: L10n.text("Connection")
        case .receiving: L10n.text("Receiving")
        case .about: L10n.text("About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .connection: "iphone"
        case .receiving: "tray.and.arrow.down"
        case .about: "info.circle"
        }
    }
}
