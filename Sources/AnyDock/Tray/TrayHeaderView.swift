import AnyDockCore
import AppKit
import Combine

@MainActor
final class TrayHeaderView: NSView {
    private static let iconPointSize: CGFloat = 14
    private static let buttonWidth: CGFloat = 36
    private static let buttonHeight = TrayMetrics.scopeBarHeight - TrayMetrics.scopeBarInset * 2

    private(set) lazy var filterBar = TrayScopeBar(
        surface: TrayGlass.surface(NSView(), cornerRadius: TrayMetrics.scopeBarHeight / 2)
    )

    private(set) lazy var controlGroup: NSView = {
        let buttons = NSStackView(views: [folderButton, settingsButton])
        buttons.spacing = 0
        buttons.edgeInsets = NSEdgeInsets(
            top: TrayMetrics.scopeBarInset,
            left: TrayMetrics.scopeBarInset,
            bottom: TrayMetrics.scopeBarInset,
            right: TrayMetrics.scopeBarInset
        )
        let group = TrayGlass.surface(buttons, cornerRadius: TrayMetrics.scopeBarHeight / 2)
        group.translatesAutoresizingMaskIntoConstraints = false
        return group
    }()

    private let viewModel: TrayViewModel
    private let folderSubject = PassthroughSubject<Void, Never>()
    private let settingsSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var folderButton = iconButton(
        symbol: "folder",
        title: L10n.text("Open Folder"),
        action: #selector(folderClicked)
    )

    private lazy var settingsButton = iconButton(
        symbol: "gearshape",
        title: L10n.text("Settings"),
        action: #selector(settingsClicked)
    )

    var filterSelections: AnyPublisher<TrayFilter, Never> {
        filterBar.selections
    }

    var selectAllRequests: AnyPublisher<TrayFilter, Never> {
        filterBar.selectAllRequests
    }

    var folderRequests: AnyPublisher<Void, Never> {
        folderSubject.eraseToAnyPublisher()
    }

    var settingsRequests: AnyPublisher<Void, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    init(viewModel: TrayViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(filterBar)
        addSubview(controlGroup)
        NSLayoutConstraint.activate([
            filterBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            filterBar.trailingAnchor.constraint(
                lessThanOrEqualTo: controlGroup.leadingAnchor,
                constant: -Space.s8
            ),
            filterBar.topAnchor.constraint(equalTo: topAnchor),
            controlGroup.heightAnchor.constraint(equalToConstant: TrayMetrics.scopeBarHeight),
            controlGroup.topAnchor.constraint(equalTo: topAnchor),
            controlGroup.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: TrayMetrics.scopeBarHeight),
        ])
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private static func title(of filter: TrayFilter) -> String {
        switch filter {
        case .all: L10n.text("All")
        case .kind(.image): L10n.text("Images")
        case .kind(.text): L10n.text("Text")
        case .kind(.link): L10n.text("Links")
        case .kind(.file): L10n.text("Files")
        }
    }

    private func subscribeEvents() {
        viewModel.list
            .sink { [weak self] _ in self?.updateFilterBar() }
            .store(in: &subscriptions)
    }

    private func updateFilterBar() {
        let contents = viewModel.contents
        filterBar.isHidden = contents.items.isEmpty
        filterBar.update(
            contents.availableFilters.map { filter in
                let count = viewModel.count(of: filter)
                return TrayScopeBar.Segment(
                    title: "\(Self.title(of: filter)) \(count)",
                    accessibilityLabel: L10n.text(
                        "filter_accessibility",
                        Self.title(of: filter),
                        count
                    ),
                    filter: filter
                )
            },
            selected: contents.filter
        )
    }

    private func iconButton(symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: Self.iconPointSize,
                weight: .regular
            ))
        button.target = self
        button.action = action
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonWidth),
            button.heightAnchor.constraint(equalToConstant: Self.buttonHeight),
        ])
        return button
    }

    @objc private func folderClicked() {
        folderSubject.send()
    }

    @objc private func settingsClicked() {
        settingsSubject.send()
    }
}
