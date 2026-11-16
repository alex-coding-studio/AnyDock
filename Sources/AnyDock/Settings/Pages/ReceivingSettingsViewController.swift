import AnyDockCore
import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class ReceivingSettingsViewController: NSViewController, NSTextFieldDelegate {
    private let viewModel: ReceivingSettingsViewModel
    private let banner = ListenerBanner()
    private let folderIcon = NSImageView()
    private let folderName = SettingsLabel.make()
    private let folderPath = SettingsLabel.make(font: .supporting, color: .pkyContent(.secondary))
    private let port = NSTextField()
    private let error = SettingsLabel.message()
    private let revert = NSButton()
    private let apply = NSButton()
    private var page: SettingsPageView?
    private var subscriptions = Set<AnyCancellable>()

    init(viewModel: ReceivingSettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = SettingsSection.receiving.title
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let page = SettingsPageView(
            title: SettingsSection.receiving.title,
            subtitle: L10n.text("settings.receiving.subtitle"),
            sections: [banner, folderSection(), networkSection()],
            footer: bottomBar()
        )
        self.page = page
        view = page
        viewModel.state
            .sink { [weak self] in self?.render($0) }
            .store(in: &subscriptions)
    }

    func controlTextDidChange(_: Notification) {
        viewModel.setPortText(port.stringValue)
    }

    private func folderSection() -> NSView {
        folderIcon.imageScaling = .scaleProportionallyUpOrDown
        folderIcon.snp.makeConstraints { $0.size.equalTo(SettingsMetrics.folderIconSide) }
        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderName.lineBreakMode = .byTruncatingMiddle
        folderName.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let names = NSStackView(views: [folderName, folderPath])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = PKYLayout.Gap.content(.compact)
        names.setHuggingPriority(.defaultLow, for: .horizontal)
        let folder = NSStackView(views: [
            folderIcon,
            names,
            SettingsLabel.button(
                L10n.text("Show in Finder"),
                target: self,
                action: #selector(showInFinder)
            ),
            SettingsLabel.button(
                L10n.text("Change…"),
                target: self,
                action: #selector(chooseFolder)
            ),
        ])
        folder.orientation = .horizontal
        folder.spacing = PKYLayout.Gap.content()
        let chips = NSStackView(views: [
            SettingsLabel.make(
                L10n.text("Sorted by type"),
                font: .supporting,
                color: .pkyContent(.secondary)
            ),
        ] + ReceivedKind.allCases.map { CapsuleView(kind: $0) })
        chips.orientation = .horizontal
        chips.spacing = PKYLayout.Gap.content(.compact)
        return SettingsCard.titled(
            L10n.text("Save Location"),
            card: SettingsCard(rows: [SettingsRow(content: folder), SettingsRow(content: chips)]),
            footer: SettingsLabel.footnote(L10n.text("settings.folder.note"))
        )
    }

    private func networkSection() -> NSView {
        port.placeholderString = String(ConnectionConfiguration.Receiver.defaultPort)
        port.alignment = .right
        port.font = PKYTypographyRole.body.monospacedDigits.nsFont(in: PKYThemeFallback.system)
        port.delegate = self
        port.setAccessibilityLabel(L10n.text("Listening port"))
        port.snp.makeConstraints { $0.width.equalTo(SettingsMetrics.portFieldWidth) }
        let hint = L10n.text(
            "meta_separator",
            L10n.text("settings.port.range"),
            L10n.text("settings.port.note")
        )
        return SettingsCard.titled(
            L10n.text("Network"),
            card: SettingsCard(rows: [
                SettingsRow(title: L10n.text("Listening port"), detail: hint, accessories: [port]),
            ]),
            footer: error
        )
    }

    private func bottomBar() -> NSView {
        revert.title = L10n.text("Revert")
        revert.bezelStyle = .push
        revert.target = self
        revert.action = #selector(revertChanges)
        apply.title = L10n.text("Apply")
        apply.bezelStyle = .push
        apply.keyEquivalent = "\r"
        apply.target = self
        apply.action = #selector(applyChanges)
        let content = NSStackView(views: [
            SettingsLabel.symbol("circle.fill", size: .accessory, color: .pkyStatus(.warning)),
            SettingsLabel.make(
                L10n.text("Unapplied changes"),
                font: .supporting,
                color: .pkyContent(.secondary)
            ),
            NSView(),
            revert,
            apply,
        ])
        content.orientation = .horizontal
        content.spacing = PKYLayout.Gap.content()
        let separator = NSBox()
        separator.boxType = .separator
        let bar = NSView()
        bar.addSubview(separator)
        bar.addSubview(content)
        separator.snp.makeConstraints { $0.top.leading.trailing.equalToSuperview() }
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.top.bottom.equalToSuperview().inset(PKYLayout.Inset.page())
        }
        return bar
    }

    private func render(_ state: ReceivingSettingsState) {
        banner.status = state.status
        folderIcon.image = NSWorkspace.shared.icon(forFile: state.folder.path)
        folderName.stringValue = state.folderName
        folderPath.stringValue = state.folderPath
        folderPath.toolTip = state.folder.path
        if port.stringValue != state.portText {
            port.stringValue = state.portText
        }
        SettingsLabel.show(
            state.errorMessage.map { SettingsMessage(text: $0, isError: true) },
            in: error
        )
        apply.isEnabled = state.canApply
        revert.isEnabled = !state.isApplying
        page?.setFooterHidden(!state.hasChanges)
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([viewModel.currentState.folder])
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.currentState.folder
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectFolder(url)
        }
    }

    @objc private func revertChanges() {
        viewModel.revert()
    }

    @objc private func applyChanges() {
        viewModel.apply()
    }
}
