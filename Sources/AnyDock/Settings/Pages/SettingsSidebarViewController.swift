import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarCell")

    private let viewModel: SettingsViewModel
    private let table = NSTableView()
    private let statusDot = StatusDot(size: PKYLayout.Size.dot())
    private let statusText = SettingsLabel.make(font: .supporting, color: .pkyContent(.secondary))
    private var subscriptions = Set<AnyCancellable>()

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let content = NSView()
        let header = makeHeader()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        let version = SettingsLabel.make(
            viewModel.about.version ?? "",
            font: .caption,
            color: .pkyContent(.tertiary)
        )
        version.isHidden = viewModel.about.version == nil
        for view in [header, scroll, version] {
            content.addSubview(view)
        }
        configureTable()
        header.snp.makeConstraints { make in
            make.top.equalTo(content.safeAreaLayoutGuide).offset(PKYLayout.Gap.content())
            make.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.page())
        }
        scroll.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(PKYLayout.Gap.group())
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(version.snp.top).offset(-PKYLayout.Gap.content())
        }
        version.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.page())
            make.bottom.equalTo(content.safeAreaLayoutGuide).inset(PKYLayout.Inset.page())
        }
        view = content
        bind()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        SettingsSection.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection.allCases[row]
        let cell = tableView.makeView(
            withIdentifier: Self.cellIdentifier,
            owner: self
        ) as? NSTableCellView
            ?? makeCell()
        cell.textField?.stringValue = section.title
        cell.imageView?.image = NSImage(
            systemSymbolName: section.symbolName,
            accessibilityDescription: nil
        )
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard let section = SettingsSection(rawValue: table.selectedRow) else {
            return
        }
        viewModel.select(section)
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: BrandIcon.artwork ?? BrandIcon.menuBar())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.snp.makeConstraints { $0.size.equalTo(SettingsMetrics.sidebarAppIconSide) }
        let status = NSStackView(views: [statusDot, statusText])
        status.orientation = .horizontal
        status.spacing = PKYLayout.Gap.content(.compact)
        statusText.lineBreakMode = .byTruncatingTail
        statusText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let names = NSStackView(views: [
            SettingsLabel.make(L10n.text("AnyDock"), font: PKYTypographyRole.heading),
            status,
        ])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = PKYLayout.Gap.content(.compact)
        let header = NSStackView(views: [icon, names])
        header.orientation = .horizontal
        header.spacing = PKYLayout.Gap.content()
        return header
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: Self.cellIdentifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.style = .sourceList
        table.backgroundColor = .clear
        table.rowSizeStyle = .large
        table.dataSource = self
        table.delegate = self
        table.reloadData()
        table.setAccessibilityLabel(L10n.text("Settings sections"))
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.cellIdentifier
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        cell.imageView = image
        cell.textField = text
        cell.addSubview(image)
        cell.addSubview(text)
        image.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(PKYLayout.Gap.content())
            make.centerY.equalToSuperview()
            make.width.equalTo(PKYIcon.Size.item.pointSize)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(image.snp.trailing).offset(PKYLayout.Gap.content())
            make.trailing.lessThanOrEqualToSuperview().inset(PKYLayout.Gap.content())
            make.centerY.equalToSuperview()
        }
        return cell
    }

    private func bind() {
        viewModel.section
            .sink { [weak self] section in
                guard let self, table.selectedRow != section.rawValue else {
                    return
                }
                table.selectRowIndexes(
                    IndexSet(integer: section.rawValue),
                    byExtendingSelection: false
                )
            }
            .store(in: &subscriptions)
        viewModel.listenerStatus
            .sink { [weak self] status in
                self?.statusDot.tone = status.tone
                self?.statusText.stringValue = status.summary
                self?.statusText.toolTip = status.tone == .failed ? status.detail : nil
            }
            .store(in: &subscriptions)
    }
}
