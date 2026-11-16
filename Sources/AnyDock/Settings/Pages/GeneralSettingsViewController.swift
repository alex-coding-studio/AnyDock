import AnyDockCore
import AppKit
import Combine
import PockyFoundation

@MainActor
final class GeneralSettingsViewController: NSViewController {
    private let viewModel: GeneralSettingsViewModel
    private let appearancePicker = AppearancePicker()
    private let language = NSSegmentedControl()
    private let restartMessage = SettingsLabel.message()
    private let login = NSSwitch()
    private let loginMessage = SettingsLabel.message()
    private let autoCopy = NSSwitch()
    private let clipboardHistory = NSSwitch()
    private let hotKeyRecorder = HotKeyRecorder()
    private let clearHotKey = NSButton()
    private let hotKeyMessage = SettingsLabel.message()
    private var appearanceCard: SettingsCard?
    private var restartRow: SettingsRow?
    private var subscriptions = Set<AnyCancellable>()

    init(viewModel: GeneralSettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = SettingsSection.general.title
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        configureControls()
        view = SettingsPageView(
            title: SettingsSection.general.title,
            subtitle: L10n.text("settings.general.subtitle"),
            sections: [appearanceSection(), traySection(), startupSection()]
        )
        bind()
    }

    private static func title(of language: AppLanguage) -> String {
        switch language {
        case .system: L10n.text("Follow System")
        case .english: L10n.text("English")
        case .simplifiedChinese: L10n.text("简体中文")
        }
    }

    private func configureControls() {
        language.segmentCount = AppLanguage.allCases.count
        for (index, option) in AppLanguage.allCases.enumerated() {
            language.setLabel(Self.title(of: option), forSegment: index)
        }
        language.trackingMode = .selectOne
        language.target = self
        language.action = #selector(changeLanguage)
        language.setAccessibilityLabel(L10n.text("Language"))
        for (control, title, action) in [
            (login, "Launch at login", #selector(toggleLogin)),
            (autoCopy, "Copy new items automatically", #selector(toggleAutoCopy)),
            (clipboardHistory, "Keep last 4 clipboard texts", #selector(toggleClipboardHistory)),
        ] {
            control.target = self
            control.action = action
            control.setAccessibilityLabel(L10n.text(title))
        }
        clearHotKey.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: L10n.text("hotkey.clear.accessibility")
        )
        clearHotKey.isBordered = false
        clearHotKey.contentTintColor = .pkyContent(.tertiary)
        clearHotKey.toolTip = L10n.text("hotkey.clear")
        clearHotKey.setAccessibilityLabel(L10n.text("hotkey.clear.accessibility"))
        clearHotKey.target = self
        clearHotKey.action = #selector(clearSavedHotKey)
    }

    private func appearanceSection() -> NSView {
        let notice = NSStackView(views: [
            SettingsLabel.symbol(
                "arrow.clockwise.circle",
                size: .control,
                color: .pkyAccent(.primary)
            ),
            SettingsLabel.make(
                L10n.text("Restart AnyDock to apply the language change."),
                wraps: true
            ),
            SettingsLabel.button(
                L10n.text("Restart Now"),
                target: self,
                action: #selector(restart)
            ),
        ])
        notice.orientation = .horizontal
        notice.spacing = PKYLayout.Gap.content()
        let restartRow = SettingsRow(content: notice)
        let card = SettingsCard(rows: [
            SettingsRow(content: appearancePicker),
            SettingsRow(title: L10n.text("Language"), accessories: [language]),
            restartRow,
        ])
        card.setRow(restartRow, hidden: true)
        appearanceCard = card
        self.restartRow = restartRow
        return SettingsCard.titled(L10n.text("Appearance"), card: card, footer: restartMessage)
    }

    private func traySection() -> NSView {
        SettingsCard.titled(L10n.text("Tray"), card: SettingsCard(rows: [
            SettingsRow(title: L10n.text("Copy new items automatically"), accessories: [autoCopy]),
            SettingsRow(
                title: L10n.text("Keep last 4 clipboard texts"),
                detail: L10n.text("settings.clipboardHistory.note"),
                accessories: [clipboardHistory]
            ),
        ]))
    }

    private func startupSection() -> NSView {
        let messages = NSStackView(views: [loginMessage, hotKeyMessage])
        messages.orientation = .vertical
        messages.alignment = .leading
        messages.spacing = PKYLayout.Gap.content(.compact)
        return SettingsCard.titled(
            L10n.text("Startup & Keyboard"),
            card: SettingsCard(rows: [
                SettingsRow(title: L10n.text("Launch at login"), accessories: [login]),
                SettingsRow(
                    title: L10n.text("Wake shortcut"),
                    accessories: [hotKeyRecorder, clearHotKey]
                ),
            ]),
            footer: messages
        )
    }

    private func bind() {
        viewModel.state
            .sink { [weak self] in self?.render($0) }
            .store(in: &subscriptions)
        appearancePicker.selections
            .sink { [weak self] in self?.viewModel.selectAppearance($0) }
            .store(in: &subscriptions)
        hotKeyRecorder.recordingChanges
            .sink { [weak self] recording in
                if recording {
                    self?.viewModel.beginHotKeyRecording()
                } else {
                    self?.viewModel.endHotKeyRecording()
                }
            }
            .store(in: &subscriptions)
        hotKeyRecorder.records
            .sink { [weak self] in self?.viewModel.record($0) }
            .store(in: &subscriptions)
        hotKeyRecorder.rejections
            .sink { [weak self] in self?.viewModel.rejectHotKey() }
            .store(in: &subscriptions)
    }

    private func render(_ state: GeneralSettingsState) {
        appearancePicker.selectedMode = state.appearance
        language.selectedSegment = AppLanguage.allCases.firstIndex(of: state.language) ?? 0
        if let restartRow {
            appearanceCard?.setRow(restartRow, hidden: !state.showsRestartNotice)
        }
        SettingsLabel.show(
            state.restartMessage.map { SettingsMessage(text: $0, isError: true) },
            in: restartMessage
        )
        login.state = state.launchesAtLogin ? .on : .off
        SettingsLabel.show(
            state.loginMessage.map { SettingsMessage(text: $0, isError: true) },
            in: loginMessage
        )
        autoCopy.state = state.copiesNewItems ? .on : .off
        clipboardHistory.state = state.keepsClipboardHistory ? .on : .off
        hotKeyRecorder.hotKey = state.hotKey
        clearHotKey.isEnabled = state.hotKey != nil
        SettingsLabel.show(
            state.hotKeyMessage.map { SettingsMessage(text: $0, isError: true) },
            in: hotKeyMessage
        )
    }

    @objc private func changeLanguage() {
        let index = language.selectedSegment
        guard AppLanguage.allCases.indices.contains(index) else {
            return
        }
        viewModel.selectLanguage(AppLanguage.allCases[index])
    }

    @objc private func restart() {
        viewModel.restart()
    }

    @objc private func toggleLogin() {
        viewModel.setLaunchesAtLogin(login.state == .on)
    }

    @objc private func toggleAutoCopy() {
        viewModel.setCopiesNewItems(autoCopy.state == .on)
    }

    @objc private func toggleClipboardHistory() {
        viewModel.setKeepsClipboardHistory(clipboardHistory.state == .on)
    }

    @objc private func clearSavedHotKey() {
        hotKeyRecorder.endRecording()
        viewModel.clearHotKey()
    }
}
