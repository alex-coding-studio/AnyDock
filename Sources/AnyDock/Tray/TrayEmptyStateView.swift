import AppKit
import Combine

@MainActor
final class TrayEmptyStateView: NSStackView {
    static let centerOffset = -Space.s24
    static let sideInset = Space.s32

    private static let iconSide: CGFloat = 40
    private static let itemSpacing: CGFloat = 10

    private let viewModel: TrayViewModel
    private var subscriptions = Set<AnyCancellable>()

    private lazy var icon: NSImageView = {
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "tray", accessibilityDescription: nil) ?? NSImage()
        )
        icon.contentTintColor = .secondaryLabelColor
        return icon
    }()

    private lazy var title: NSTextField = {
        let title = NSTextField(labelWithString: L10n.text("Nothing received yet"))
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return title
    }()

    private lazy var detail: NSTextField = {
        let detail = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Share content on your iPhone and choose your Mac’s shortcut."
            )
        )
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        return detail
    }()

    init(viewModel: TrayViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setViews([icon, title, detail], in: .center)
        orientation = .vertical
        alignment = .centerX
        spacing = Self.itemSpacing
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: Self.iconSide),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSide),
        ])
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    private func subscribeEvents() {
        viewModel.list
            .sink { [weak self] _ in self?.isHidden = self?.viewModel.isEmpty == false }
            .store(in: &subscriptions)
    }
}
