import AnyDockCore
import AppKit

extension ReceivedKind {
    var displayName: String {
        switch self {
        case .image: L10n.text("Image")
        case .text: L10n.text("Text")
        case .link: L10n.text("Link")
        case .file: L10n.text("File")
        }
    }

    var filterTitle: String {
        switch self {
        case .image: L10n.text("Images")
        case .text: L10n.text("Text")
        case .link: L10n.text("Links")
        case .file: L10n.text("Files")
        }
    }

    var badgeText: String? {
        switch self {
        case .text: "TEXT"
        case .link: "URL"
        case .image, .file: nil
        }
    }

    var badgeStyle: BadgeView.Style {
        switch self {
        case .image: .media
        case .text: .solid(.systemGray)
        case .link: .solid(.systemBlue)
        case .file: .neutral
        }
    }

    @MainActor
    var cardItemClass: TrayCardItem.Type {
        switch self {
        case .image: ImageCardItem.self
        case .text: TextCardItem.self
        case .link: LinkCardItem.self
        case .file: FileCardItem.self
        }
    }

    @MainActor
    var cardIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(String(describing: cardItemClass))
    }
}

extension TrayFilter {
    var title: String {
        switch self {
        case .all: L10n.text("All")
        case let .kind(kind): kind.filterTitle
        }
    }
}
