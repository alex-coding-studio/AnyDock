import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class TrayEmptyStateView: NSStackView {
    static let opticalCenterOffset: CGFloat = -24

    private static let iconSide: CGFloat = 40

    private let viewModel: TrayViewModel
    private var subscriptions = Set<AnyCancellable>()

    private lazy var icon: NSImageView = {
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "tray", accessibilityDescription: nil) ?? NSImage()
        )
        icon.contentTintColor = .pkyContent(.secondary)
        return icon
    }()

    private lazy var title: NSTextField = {
        let title = NSTextField(labelWithString: L10n.text("Nothing received yet"))
        title.font = PKYTypographyRole.heading.nsFont(in: PKYThemeFallback.system)
        return title
    }()

    private lazy var detail: NSTextField = {
        let detail = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Share content on your iPhone and choose your Mac’s shortcut."
            )
        )
        detail.font = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
        detail.textColor = .pkyContent(.secondary)
        detail.alignment = .center
        return detail
    }()

    init(viewModel: TrayViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        configure()
        setViews([icon, title, detail], in: .center)
        icon.snp.makeConstraints { $0.size.equalTo(Self.iconSide) }
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    private func configure() {
        orientation = .vertical
        alignment = .centerX
        spacing = PKYLayout.Gap.content(.standard)
    }

    private func subscribeEvents() {
        viewModel.list
            .sink { [weak self] _ in self?.isHidden = self?.viewModel.isEmpty == false }
            .store(in: &subscriptions)
    }
}
