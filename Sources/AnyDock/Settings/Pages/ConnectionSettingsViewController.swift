import AppKit
import Combine
import PockyFoundation
import SnapKit

@MainActor
final class ConnectionSettingsViewController: NSViewController, NSTextFieldDelegate {
    private let viewModel: ConnectionSettingsViewModel
    private let shortcutName = SettingsControls.textField()
    private let nameMessage = SettingsLabel.message()
    private let status = SettingsLabel.message()
    private lazy var send = SettingsControls.button(
        L10n.text("Send to iPhone…"),
        symbol: "paperplane.fill",
        role: .primary,
        target: self,
        action: #selector(sendToPhone)
    )
    private let address = SettingsLabel.make()
    private var subscriptions = Set<AnyCancellable>()

    init(viewModel: ConnectionSettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = SettingsSection.connection.title
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        view = SettingsPageView(
            title: SettingsSection.connection.title,
            subtitle: L10n.text("settings.connection.subtitle"),
            sections: [oneStepSection(), manualSection()]
        )
        viewModel.state
            .sink { [weak self] in self?.render($0) }
            .store(in: &subscriptions)
    }

    func controlTextDidChange(_: Notification) {
        viewModel.setShortcutName(shortcutName.stringValue)
    }

    private func oneStepSection() -> NSView {
        let illustration = NSImageView(image: NSImage(
            systemSymbolName: "iphone.radiowaves.left.and.right",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(
            pointSize: SettingsMetrics.heroIllustrationPointSize,
            weight: .light
        )) ?? NSImage())
        illustration.contentTintColor = .pkyAccent(.primary)
        illustration.setContentHuggingPriority(.required, for: .horizontal)
        shortcutName.delegate = self
        shortcutName.setAccessibilityLabel(L10n.text("Shortcut name"))
        shortcutName.placeholderString = L10n.text("Shortcut name")
        shortcutName.snp.makeConstraints { $0.width.equalTo(SettingsMetrics.shortcutNameWidth) }
        send.keyEquivalent = "\r"
        let form = NSStackView(views: [shortcutName, send])
        form.orientation = .horizontal
        form.alignment = .centerY
        form.spacing = PKYLayout.Gap.content()
        let description = SettingsLabel.make(
            L10n.text("settings.oneStep.description"),
            color: .pkyContent(.secondary),
            wraps: true
        )
        let note = SettingsLabel.noted("lock.fill", L10n.text("settings.shortcut.note"))
        let details = NSStackView(views: [
            SettingsLabel.make(
                L10n.text("One-step Setup"),
                font: PKYSectionHeaderRole.group.title.semibold
            ),
            description,
            form,
            nameMessage,
            note,
        ])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = PKYLayout.Gap.content()
        details.setCustomSpacing(PKYLayout.Gap.group(), after: description)
        for view in [description, nameMessage, note] {
            view.snp.makeConstraints { $0.width.equalTo(details) }
        }
        let hero = NSStackView(views: [illustration, details])
        hero.orientation = .horizontal
        hero.alignment = .top
        hero.spacing = PKYLayout.Gap.group()
        hero.edgeInsets = NSEdgeInsets(
            top: PKYLayout.Inset.container(),
            left: PKYLayout.Inset.container(),
            bottom: PKYLayout.Inset.container(),
            right: PKYLayout.Inset.container()
        )
        let card = SettingsCard(rows: [hero], style: .prominent)
        return SettingsCard.titled(nil, card: card, footer: status)
    }

    private func manualSection() -> NSView {
        let monospaced = NSFont.monospacedSystemFont(
            ofSize: PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system).pointSize,
            weight: .regular
        )
        address.font = monospaced
        address.isSelectable = true
        address.lineBreakMode = .byTruncatingMiddle
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let key = SettingsLabel.make("•••• •••• •••• ••••", color: .pkyContent(.secondary))
        key.font = monospaced
        let copyAddress = SettingsControls.button(
            L10n.text("Copy"),
            target: self,
            action: #selector(copyAddress)
        )
        copyAddress.setAccessibilityLabel(L10n.text("Copy receive address"))
        let copyKey = SettingsControls.button(
            L10n.text("Copy"),
            target: self,
            action: #selector(copyKey)
        )
        copyKey.setAccessibilityLabel(L10n.text("Copy connection key"))
        let card = SettingsCard(rows: [
            SettingsRow(title: L10n.text("Receive address"), accessories: [address, copyAddress]),
            SettingsRow(title: L10n.text("Connection key"), accessories: [key, copyKey]),
            SettingsRow(title: L10n.text("Generic shortcut"), accessories: [
                SettingsLabel.make(L10n.text("Send to Mac"), color: .pkyContent(.secondary)),
                SettingsControls.button(
                    L10n.text("Export…"),
                    target: self,
                    action: #selector(exportShortcut)
                ),
            ]),
        ])
        return SettingsCard.titled(
            L10n.text("Manual Setup"),
            card: card,
            footer: SettingsLabel.noted("network", L10n.text("settings.manual.note"))
        )
    }

    private func render(_ state: ConnectionSettingsState) {
        if shortcutName.stringValue != state.shortcutName {
            shortcutName.stringValue = state.shortcutName
        }
        shortcutName.isEnabled = !state.isSending
        send.isEnabled = state.canSend
        SettingsLabel.show(state.nameMessage, in: nameMessage)
        SettingsLabel.show(state.message, in: status)
        address.stringValue = state.receiveAddress
        address.toolTip = state.receiveAddress
    }

    @objc private func sendToPhone() {
        viewModel.send()
    }

    @objc private func copyAddress() {
        viewModel.copyReceiveAddress()
    }

    @objc private func copyKey() {
        viewModel.copyConnectionKey()
    }

    @objc private func exportShortcut() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L10n.text("Send to Mac") + ".shortcut"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        viewModel.exportGenericShortcut(to: destination)
    }
}
