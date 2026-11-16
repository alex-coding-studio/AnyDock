import AnyDockCore
import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class TrayHeaderView: NSView {
    private static let buttonHeight =
        PKYLayout.Size.button(.compact) - PKYLayout.Gap.content(.compact) * 2

    private(set) lazy var filterBar = TrayScopeBar(
        surface: TrayGlass.surface(NSView(), cornerRadius: PKYLayout.Size.button(.compact) / 2)
    )

    private(set) lazy var controlGroup: NSView = {
        let buttons = NSStackView(views: [folderButton, settingsButton])
        buttons.spacing = 0
        buttons.edgeInsets = NSEdgeInsets(
            top: PKYLayout.Gap.content(.compact),
            left: PKYLayout.Gap.content(.compact),
            bottom: PKYLayout.Gap.content(.compact),
            right: PKYLayout.Gap.content(.compact)
        )
        return TrayGlass.surface(buttons, cornerRadius: PKYLayout.Size.button(.compact) / 2)
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
        addSubview(filterBar)
        addSubview(controlGroup)
        filterBar.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
            make.trailing.lessThanOrEqualTo(controlGroup.snp.leading)
                .offset(-PKYLayout.Gap.group(.compact))
        }
        controlGroup.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview()
            make.height.equalTo(PKYLayout.Size.button(.compact))
        }
        snp.makeConstraints { $0.height.equalTo(PKYLayout.Size.button(.compact)) }
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
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
                    title: "\(filter.title) \(count)",
                    accessibilityLabel: L10n.text(
                        "filter_accessibility",
                        filter.title,
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
                pointSize: PKYIcon.Size.control.pointSize,
                weight: .regular
            ))
        button.target = self
        button.action = action
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.snp.makeConstraints { make in
            make.width.equalTo(PKYLayout.Size.button(.compact))
            make.height.equalTo(Self.buttonHeight)
        }
        return button
    }

    @objc private func folderClicked() {
        folderSubject.send()
    }

    @objc private func settingsClicked() {
        settingsSubject.send()
    }
}
