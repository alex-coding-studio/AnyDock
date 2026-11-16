import AnyDockCore
import AppKit
import Combine
import PockyFoundation
import ServiceManagement
import SnapKit

@MainActor
final class SettingsController: NSWindowController, NSTextFieldDelegate, NSSharingServiceDelegate {
    private enum Metrics {
        static let windowSide: CGFloat = 600
        static let aboutIconSide: CGFloat = 96
        static let shortcutNameWidth: CGFloat = 260
        static let portWidth: CGFloat = 76
        static let statusIconSide: CGFloat = 9
        static let statusRowMinimumHeight: CGFloat = 38
        static let formRowMinimumHeight: CGFloat = 40
        static let aboutOpticalCenterOffset: CGFloat = -24
    }

    let statusIcon = NSImageView(
        image: NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: L10n.text("Starting")
        )
            ?? NSImage()
    )
    let hotKeyRecorder = HotKeyRecorder()
    let hotKeyStatus = NSTextField(wrappingLabelWithString: "")

    private let inbox: Inbox
    private let hotKeys: GlobalHotKeyCenter
    private var subscriptions = Set<AnyCancellable>()
    private var selectedDirectory: URL
    private let appearance = NSPopUpButton(frame: .zero, pullsDown: false)
    private let language = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchLanguage = AppLanguage.current(domain: "com.cuxiao.mac.anydock")
    private let languageNotice = NSTextField(
        wrappingLabelWithString: L10n.text("Restart AnyDock to apply the language change.")
    )
    private let restart = NSButton(title: L10n.text("Restart Now"), target: nil, action: nil)
    private lazy var restartRow = row([NSView(), restart])
    private var isApplying = false
    private var isSending = false
    private let shortcutName = NSTextField()
    private let shortcutNameStatus = NSTextField(wrappingLabelWithString: "")
    private var sharedFile: URL?
    private var sharingService: NSSharingService?
    private let folder = NSTextField(labelWithString: "")
    private let port = NSTextField()
    private let address = NSTextField(wrappingLabelWithString: "")
    private let receiverStatus = NSTextField(
        wrappingLabelWithString: L10n.text("Starting the receiver…")
    )
    private let receivingError = NSTextField(wrappingLabelWithString: "")
    private let generalStatus = NSTextField(wrappingLabelWithString: "")
    private let connectionStatus = NSTextField(wrappingLabelWithString: "")
    private let pending = NSTextField(labelWithString: "")
    private let login = NSSwitch()
    private let autoCopy = NSSwitch()
    private let clipboardHistory = NSSwitch()
    private let clearHotKey = NSButton(title: L10n.text("hotkey.clear"), target: nil, action: nil)
    private let save = NSButton(title: L10n.text("Apply"), target: nil, action: nil)
    private let send = NSButton(title: L10n.text("Send to iPhone…"), target: nil, action: nil)

    init(inbox: Inbox, hotKeys: GlobalHotKeyCenter) {
        self.inbox = inbox
        self.hotKeys = hotKeys
        selectedDirectory = inbox.configuration.receiver.directory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.windowSide, height: Metrics.windowSide),
            styleMask: [
                .titled,
                .closable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("AnyDock Settings")
        window.toolbarStyle = .preference
        window.center()
        super.init(window: window)
        statusIcon.contentTintColor = .tertiaryLabelColor
        if let savedName = inbox.configuration.sender.shortcutName {
            shortcutName.stringValue = savedName
        } else if let computerName = LocalHost.computerName()?
            .trimmingCharacters(in: .whitespacesAndNewlines), !computerName.isEmpty {
            shortcutName.stringValue = L10n.text("Send to %@", computerName)
        } else {
            shortcutName.stringValue = L10n.text("Send to Mac")
        }
        configureMessage(hotKeyStatus)
        hotKeyRecorder.hotKey = Preferences.wakeHotKey
        clearHotKey.target = self
        clearHotKey.action = #selector(clearSavedHotKey)
        clearHotKey.bezelStyle = .rounded
        clearHotKey.controlSize = .small
        clearHotKey.setAccessibilityLabel(L10n.text("hotkey.clear.accessibility"))
        clearHotKey.isEnabled = Preferences.wakeHotKey != nil
        if let saved = Preferences.wakeHotKey, !hotKeys.isRegistered {
            showHotKeyMessage(L10n.text("hotkey.unavailable", saved.displayString))
        }
        subscribeEvents()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        prepareInterface()
        super.showWindow(sender)
    }

    static func versionText(bundle: Bundle) -> String? {
        guard
            let version = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }
        return L10n.text("Version %@ (%@)", version, build)
    }

    func registerSavedHotKey() {
        guard let saved = Preferences.wakeHotKey else {
            _ = hotKeys.register(nil)
            return
        }
        if !hotKeys.register(saved) {
            showHotKeyMessage(L10n.text("hotkey.unavailable", saved.displayString))
        }
    }

    func recordHotKey(_ candidate: KeyCombination) {
        guard hotKeys.register(candidate) else {
            registerSavedHotKey()
            showHotKeyMessage(L10n.text("hotkey.unavailable", candidate.displayString))
            return
        }
        Preferences.wakeHotKey = candidate
        hotKeyRecorder.hotKey = candidate
        clearHotKey.isEnabled = true
        hotKeyStatus.isHidden = true
    }

    func prepareInterface() {
        guard window?.contentViewController == nil else {
            return
        }
        buildInterface()
        window?.center()
    }

    func setStatus(_ text: String, isError: Bool) {
        receiverStatus.stringValue = text
        receiverStatus.textColor = isError ? .pkyStatus(.destructive) : .labelColor
        statusIcon.contentTintColor = isError ? .pkyStatus(.destructive) : .pkyStatus(.success)
        statusIcon.image = NSImage(
            systemSymbolName: isError ? "exclamationmark.circle.fill" : "circle.fill",
            accessibilityDescription: isError ? L10n.text("Receiver Failed") : L10n.text(
                "Listening"
            )
        )
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === shortcutName {
            updateShortcutName()
        } else {
            updatePending()
        }
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) {
        sharingService = nil
        saveShortcutName(shortcutName.stringValue)
        setSending(false)
        if cleanUpSharedFile() {
            showConnectionMessage(L10n.text("shortcut.airdrop.sent"), isError: false)
        }
    }

    func sharingService(
        _: NSSharingService,
        didFailToShareItems _: [Any],
        error: Error
    ) {
        sharingService = nil
        setSending(false)
        if cleanUpSharedFile() {
            showConnectionMessage(L10n.text("shortcut.airdrop.failed", error.localizedDescription))
        }
    }

    func sharingService(
        _: NSSharingService,
        sourceWindowForShareItems _: [Any],
        sharingContentScope _: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        window
    }

    private func subscribeEvents() {
        inbox.status
            .sink { [weak self] in self?.show($0) }
            .store(in: &subscriptions)
        hotKeyRecorder.recordingChanges
            .sink { [weak self] in self?.recordingChanged($0) }
            .store(in: &subscriptions)
        hotKeyRecorder.records
            .sink { [weak self] in self?.recordHotKey($0) }
            .store(in: &subscriptions)
        hotKeyRecorder.rejections
            .sink { [weak self] in self?.showHotKeyMessage(L10n.text("hotkey.modifierRequired")) }
            .store(in: &subscriptions)
    }

    private func recordingChanged(_ recording: Bool) {
        hotKeyStatus.isHidden = true
        if recording {
            _ = hotKeys.register(nil)
        } else {
            registerSavedHotKey()
        }
    }

    private func show(_ status: InboxStatus) {
        switch status {
        case .starting:
            break
        case let .listening(port):
            setStatus(L10n.text("Listening · %d", Int(port)), isError: false)
        case let .failed(message):
            setStatus(message, isError: true)
        }
    }

    private func showHotKeyMessage(_ text: String) {
        hotKeyStatus.stringValue = text
        hotKeyStatus.isHidden = false
    }

    @objc private func clearSavedHotKey() {
        hotKeyRecorder.endRecording()
        Preferences.wakeHotKey = nil
        _ = hotKeys.register(nil)
        hotKeyRecorder.hotKey = nil
        clearHotKey.isEnabled = false
        hotKeyStatus.isHidden = true
    }

    private func buildInterface() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        tabs.addTabViewItem(generalTab())
        tabs.addTabViewItem(connectionTab())
        tabs.addTabViewItem(receivingTab())
        tabs.addTabViewItem(aboutTab())
        tabs.selectedTabViewItemIndex = 0
        window?.contentViewController = tabs
    }

    private func generalTab() -> NSTabViewItem {
        appearance.addItems(withTitles: [
            L10n.text("Follow System"),
            L10n.text("Light"),
            L10n.text("Dark"),
        ])
        appearance.selectItem(
            at: PKYAppearance.Mode.allCases.firstIndex(of: Preferences.appearance.storedMode()) ?? 0
        )
        appearance.target = self
        appearance.action = #selector(changeAppearance)
        appearance.setAccessibilityLabel(L10n.text("Appearance"))
        language.addItems(withTitles: [
            L10n.text("Follow System"),
            L10n.text("English"),
            L10n.text("简体中文"),
        ])
        language.selectItem(at: AppLanguage.allCases.firstIndex(of: launchLanguage) ?? 0)
        language.target = self
        language.action = #selector(changeLanguage)
        language.setAccessibilityLabel(L10n.text("Language"))
        languageNotice.font = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
        languageNotice.textColor = .secondaryLabelColor
        languageNotice.isHidden = true
        languageNotice.setContentCompressionResistancePriority(.required, for: .vertical)
        restart.target = self
        restart.action = #selector(restartApplication)
        restart.bezelStyle = .rounded
        restartRow.isHidden = true
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        login.action = #selector(toggleLogin)
        login.setAccessibilityLabel(L10n.text("Launch at login"))
        autoCopy.state = Preferences.copiesNewItems ? .on : .off
        autoCopy.target = self
        autoCopy.action = #selector(toggleAutoCopy)
        autoCopy.setAccessibilityLabel(L10n.text("Copy new items automatically"))
        clipboardHistory.state = Preferences.keepsClipboardHistory ? .on : .off
        clipboardHistory.target = self
        clipboardHistory.action = #selector(toggleClipboardHistory)
        clipboardHistory.setAccessibilityLabel(L10n.text("Keep last 4 clipboard texts"))
        configureMessage(generalStatus)
        return tab(
            L10n.text("General"),
            symbol: "gearshape",
            views: [
                section(
                    L10n.text("Startup"),
                    rows: [formRow(L10n.text("Launch at login"), value: login)]
                ),
                generalStatus,
                section(
                    L10n.text("Personalization"),
                    rows: [
                        formRow(L10n.text("Appearance"), value: appearance),
                        formRow(L10n.text("Language"), value: language),
                    ]
                ),
                languageNotice,
                restartRow,
                section(
                    L10n.text("Tray"),
                    rows: [
                        formRow(L10n.text("Copy new items automatically"), value: autoCopy),
                        formRow(L10n.text("Keep last 4 clipboard texts"), value: clipboardHistory),
                    ],
                    note: L10n.text("settings.clipboardHistory.note")
                ),
                section(
                    L10n.text("Keyboard"),
                    rows: [formRow(
                        L10n.text("Wake shortcut"),
                        value: row([hotKeyRecorder, clearHotKey])
                    )]
                ),
                hotKeyStatus,
            ]
        )
    }

    private func aboutTab() -> NSTabViewItem {
        let icon = NSImageView(image: BrandIcon.artwork ?? BrandIcon.menuBar())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.snp.makeConstraints { $0.size.equalTo(Metrics.aboutIconSide) }
        let name = NSTextField(labelWithString: L10n.text("AnyDock"))
        name.font = PKYTypographyRole.pageTitle.semibold.nsFont(in: PKYThemeFallback.system)
        let version = footnote(Self.versionText(bundle: .main) ?? "")
        version.isHidden = version.stringValue.isEmpty
        version.isSelectable = true
        let tagline = NSTextField(labelWithString: L10n.text("about.tagline"))
        let links = row([
            button(L10n.text("GitHub Project"), #selector(openRepository)),
            button(L10n.text("Author @Cunqi"), #selector(openAuthor)),
        ])
        let copyright = footnote(L10n.text("about.copyright"))
        let quit = NSButton(
            title: L10n.text("Quit AnyDock"),
            target: NSApp,
            action: #selector(NSApplication.terminate(_:))
        )
        quit.bezelStyle = .rounded
        let identity = NSStackView(views: [icon, name, version, tagline, links, copyright])
        identity.orientation = .vertical
        identity.alignment = .centerX
        identity.spacing = PKYLayout.Gap.content(.standard)
        identity.setCustomSpacing(PKYLayout.Gap.content(.wide), after: icon)
        identity.setCustomSpacing(PKYLayout.Gap.group(.standard), after: tagline)
        identity.setCustomSpacing(PKYLayout.Gap.group(.standard), after: links)
        let content = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: Metrics.windowSide,
            height: Metrics.windowSide
        ))
        for view in [identity, quit] {
            content.addSubview(view)
        }
        identity.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(Metrics.aboutOpticalCenterOffset)
            make.leading.greaterThanOrEqualToSuperview().offset(PKYLayout.Inset.page(.wide))
        }
        quit.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.top.greaterThanOrEqualTo(identity.snp.bottom).offset(PKYLayout.Gap.group(.wide))
        }
        return tabItem(L10n.text("About"), symbol: "info.circle", content: content)
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/alex-coding-studio/AnyDock")!)
    }

    @objc private func openAuthor() {
        NSWorkspace.shared.open(URL(string: "https://github.com/Cunqi")!)
    }

    private func connectionTab() -> NSTabViewItem {
        address.isSelectable = true
        address.maximumNumberOfLines = 2
        address.lineBreakMode = .byCharWrapping
        let detailFontSize = PKYTypographyRole.supporting.nsFont(
            in: PKYThemeFallback.system
        ).pointSize
        address.font = .monospacedSystemFont(ofSize: detailFontSize, weight: .regular)
        refreshAddress()
        let key = NSTextField(labelWithString: "•••• •••• •••• ••••")
        key.font = .monospacedSystemFont(ofSize: detailFontSize, weight: .regular)
        key.textColor = .secondaryLabelColor
        send.target = self
        send.action = #selector(sendToPhone)
        send.bezelStyle = .rounded
        send.bezelColor = .pkyAccent(.primary)
        configureMessage(connectionStatus)
        configureMessage(shortcutNameStatus)
        shortcutName.delegate = self
        shortcutName.setAccessibilityLabel(L10n.text("Shortcut name"))
        shortcutName.snp.makeConstraints { $0.width.equalTo(Metrics.shortcutNameWidth) }
        updateShortcutName()
        let copyAddress = button(L10n.text("Copy"), #selector(copyConnectionAddress))
        copyAddress.setAccessibilityLabel(L10n.text("Copy receive address"))
        let copyKey = button(L10n.text("Copy"), #selector(copyToken))
        copyKey.setAccessibilityLabel(L10n.text("Copy connection key"))
        return tab(
            L10n.text("Connection"),
            symbol: "iphone",
            views: [
                section(
                    L10n.text("One-step Setup"),
                    rows: [
                        formRow(L10n.text("Shortcut name"), value: shortcutName),
                        formRow(L10n.text("Send to Mac"), value: send),
                    ],
                    note: L10n.text("settings.shortcut.note")
                ),
                shortcutNameStatus,
                connectionStatus,
                section(
                    L10n.text("Manual Setup"),
                    rows: [
                        formRow(L10n.text("Receive address"), value: address, action: copyAddress),
                        formRow(L10n.text("Connection key"), value: key, action: copyKey),
                        formRow(
                            L10n.text(
                                "Generic shortcut"
                            ),
                            value: NSTextField(labelWithString: L10n.text("Send to Mac")),
                            action: button(L10n.text("Export…"), #selector(exportShortcut))
                        ),
                    ],
                    note: L10n.text("settings.manual.note")
                ),
            ]
        )
    }

    private func receivingTab() -> NSTabViewItem {
        refreshFolder()
        folder.lineBreakMode = .byTruncatingMiddle
        port.stringValue = String(inbox.configuration.receiver.port)
        port.placeholderString = String(ConnectionConfiguration.Receiver.defaultPort)
        port.alignment = .right
        port.font = PKYTypographyRole.body.monospacedDigits.nsFont(in: PKYThemeFallback.system)
        port.snp.makeConstraints { $0.width.equalTo(Metrics.portWidth) }
        port.delegate = self
        port.setAccessibilityLabel(L10n.text("Listening port"))
        statusIcon.snp.makeConstraints { $0.size.equalTo(Metrics.statusIconSide) }
        let statusRow = row([statusIcon, receiverStatus, NSView()])
        statusRow.snp.makeConstraints {
            $0.height.greaterThanOrEqualTo(Metrics.statusRowMinimumHeight)
        }
        configureMessage(receivingError)
        pending.font = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
        pending.textColor = .secondaryLabelColor
        save.target = self
        save.action = #selector(saveSettings)
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        updatePending()
        return tab(
            L10n.text("Receiving"),
            symbol: "tray.and.arrow.down",
            views: [
                group(rows: [statusRow]),
                section(
                    L10n.text("Save Location"),
                    rows: [
                        formRow(
                            L10n.text("Folder"),
                            value: folder,
                            action: button(L10n.text("Change…"), #selector(chooseFolder))
                        ),
                    ],
                    note: L10n.text("settings.folder.note")
                ),
                section(
                    L10n.text("Network"),
                    rows: [formRow(L10n.text("Listening port"), value: port)],
                    note: L10n.text("settings.port.note")
                ),
                receivingError,
            ],
            bottomBar: row([NSView(), pending, save])
        )
    }

    private func tab(_ title: String, symbol: String, views: [NSView], bottomBar: NSView? = nil)
        -> NSTabViewItem {
        let content = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: Metrics.windowSide,
            height: Metrics.windowSide
        ))
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PKYLayout.Gap.section(.compact)
        content.addSubview(stack)
        for element in stack.arrangedSubviews {
            element.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        let bottomTarget: ConstraintItem
        let bottomGap: CGFloat
        if let bottomBar {
            content.addSubview(bottomBar)
            let separator = NSBox()
            separator.boxType = .separator
            content.addSubview(separator)
            bottomBar.snp.makeConstraints { make in
                make.leading.trailing.equalTo(stack)
                make.bottom.equalToSuperview().inset(PKYLayout.Inset.page(.standard))
            }
            separator.snp.makeConstraints { make in
                make.directionalHorizontalEdges.equalToSuperview()
                make.bottom.equalTo(bottomBar.snp.top).offset(-PKYLayout.Gap.group(.compact))
            }
            bottomTarget = separator.snp.top
            bottomGap = PKYLayout.Gap.group(.compact)
        } else {
            bottomTarget = content.snp.bottom
            bottomGap = PKYLayout.Inset.page(.wide)
        }
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.bottom.lessThanOrEqualTo(bottomTarget).offset(-bottomGap)
        }
        return tabItem(title, symbol: symbol, content: content)
    }

    private func tabItem(_ title: String, symbol: String, content: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.title = title
        controller.preferredContentSize = NSSize(
            width: Metrics.windowSide,
            height: Metrics.windowSide
        )
        controller.view = content
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = PKYLayout.Gap.content(.standard)
        stack.alignment = .centerY
        return stack
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func formRow(_ title: String, value: NSView, action: NSView? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        value.setContentHuggingPriority(
            action == nil ? .required : .defaultLow,
            for: .horizontal
        )
        value.setContentCompressionResistancePriority(
            action == nil ? .required : .defaultLow,
            for: .horizontal
        )
        let stack = row(
            [label] + (action == nil ? [NSView(), value] : [value]) + (action.map { [$0] } ?? [])
        )
        stack.snp.makeConstraints { $0.height.greaterThanOrEqualTo(Metrics.formRowMinimumHeight) }
        return stack
    }

    private func footnote(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func configureMessage(_ label: NSTextField) {
        label.font = PKYTypographyRole.supporting.nsFont(in: PKYThemeFallback.system)
        label.textColor = .pkyStatus(.destructive)
        label.isHidden = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func section(_ title: String, rows: [NSView], note: String? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = PKYTypographyRole.supporting.semibold.nsFont(in: PKYThemeFallback.system)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(
            views: [label, group(rows: rows)] + (note.map { [footnote($0)] } ?? [])
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PKYLayout.Gap.content(.standard)
        for view in stack.arrangedSubviews.dropFirst() {
            view.snp.makeConstraints { $0.width.equalTo(stack) }
        }
        return stack
    }

    private func group(rows: [NSView]) -> NSView {
        let contents = NSStackView()
        contents.orientation = .vertical
        contents.spacing = 0
        for (index, item) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                contents.addArrangedSubview(separator)
                separator.snp.makeConstraints { $0.width.equalTo(contents) }
            }
            contents.addArrangedSubview(item)
            item.snp.makeConstraints { $0.width.equalTo(contents) }
        }
        let group = SettingsGroup()
        group.addSubview(contents)
        contents.snp.makeConstraints { make in
            make.directionalHorizontalEdges.equalToSuperview()
                .inset(PKYLayout.Inset.row.horizontal(.standard))
            make.verticalEdges.equalToSuperview().inset(PKYLayout.Inset.row.vertical(.compact))
        }
        return group
    }

    private func refreshAddress() {
        address.stringValue = LocalHost.receiveAddress(port: inbox.configuration.receiver.port)
    }

    private func refreshFolder() {
        folder.stringValue = (selectedDirectory.path as NSString).abbreviatingWithTildeInPath
        folder.toolTip = selectedDirectory.path
    }

    private func updatePending() {
        let enteredPort = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces))
        let changed = selectedDirectory != inbox.configuration.receiver.directory || enteredPort != inbox.configuration.receiver.port
        pending.stringValue = changed ? L10n.text("Unapplied changes") : ""
        save.isEnabled = changed && !isApplying
    }

    private func updateShortcutName() {
        do {
            let name = try ShortcutInstaller.normalizedName(shortcutName.stringValue)
            shortcutNameStatus.stringValue = L10n.text("shortcut.name.normalized", name)
            shortcutNameStatus.textColor = .secondaryLabelColor
            shortcutNameStatus.isHidden = name == shortcutName.stringValue
            send.isEnabled = !isSending && !inbox.configuration.receiver.token.isEmpty
        } catch {
            shortcutNameStatus.stringValue = error.localizedDescription
            shortcutNameStatus.textColor = .pkyStatus(.destructive)
            shortcutNameStatus.isHidden = false
            send.isEnabled = false
        }
    }

    private func setSending(_ value: Bool) {
        isSending = value
        shortcutName.isEnabled = !value
        updateShortcutName()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedDirectory
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
            refreshFolder()
            updatePending()
        }
    }

    @objc private func saveSettings() {
        guard !isApplying, save.isEnabled else {
            return
        }
        guard let value = UInt16(
            port.stringValue.trimmingCharacters(in: .whitespaces)
        ), value >= 1024
        else {
            receivingError.stringValue = L10n.text(
                "Enter a whole-number port between 1024 and 65535."
            )
            receivingError.isHidden = false
            return
        }
        var next = inbox.configuration.receiver
        next.port = value
        next.directory = selectedDirectory
        isApplying = true
        receivingError.isHidden = true
        updatePending()
        Task {
            defer {
                isApplying = false
                updatePending()
            }
            do {
                try await inbox.apply(receiver: next)
                refreshAddress()
            } catch {
                receivingError.stringValue = error.localizedDescription
                receivingError.isHidden = false
            }
        }
    }

    @objc private func changeAppearance() {
        let index = appearance.indexOfSelectedItem
        guard PKYAppearance.Mode.allCases.indices.contains(index) else {
            return
        }
        let selected = PKYAppearance.Mode.allCases[index]
        Preferences.appearance.save(selected)
        NSApp.appearance = selected.nsAppearance
    }

    @objc private func changeLanguage() {
        let index = language.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else {
            return
        }
        let selected = AppLanguage.allCases[index]
        selected.save()
        languageNotice.isHidden = selected == launchLanguage
        restartRow.isHidden = selected == launchLanguage
    }

    @objc private func restartApplication() {
        guard !isSending else {
            generalStatus.stringValue = L10n.text("Finish sharing before restarting AnyDock.")
            generalStatus.isHidden = false
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            generalStatus.stringValue = L10n.text(
                "settings.restart.unbundled"
            )
            generalStatus.isHidden = false
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; done
            /usr/bin/open -n "$2" --args --settings
            """,
            "AnyDockRestart",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            guard UserDefaults.standard.synchronize() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try process.run()
            NSApp.terminate(nil)
        } catch {
            generalStatus.stringValue = L10n.text(
                "Unable to restart AnyDock: %@",
                error.localizedDescription
            )
            generalStatus.isHidden = false
        }
    }

    @objc private func toggleLogin() {
        generalStatus.isHidden = true
        do {
            if login.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if SMAppService.mainApp.status == .requiresApproval {
                generalStatus.stringValue = L10n.text(
                    "Allow AnyDock in System Settings → Login Items."
                )
                generalStatus.isHidden = false
            }
        } catch {
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            generalStatus.stringValue = L10n.text(
                "Unable to change the login item: %@",
                error.localizedDescription
            )
            generalStatus.isHidden = false
        }
    }

    @objc private func toggleAutoCopy() {
        Preferences.copiesNewItems = autoCopy.state == .on
    }

    @objc private func toggleClipboardHistory() {
        Preferences.keepsClipboardHistory = clipboardHistory.state == .on
    }

    @objc private func copyConnectionAddress() {
        copy(address.stringValue)
    }

    @objc private func copyToken() {
        copy(inbox.configuration.receiver.token, concealed: true)
    }

    private func copy(_ value: String, concealed: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        if concealed {
            NSPasteboard.general.setString("", forType: ClipboardMonitor.concealedType)
        }
    }

    private func showConnectionMessage(_ text: String, isError: Bool = true) {
        connectionStatus.stringValue = text
        connectionStatus.textColor = isError ? .pkyStatus(.destructive) : .secondaryLabelColor
        connectionStatus.isHidden = false
    }

    @objc private func sendToPhone() {
        guard send.isEnabled else {
            return
        }
        if sharedFile != nil, !cleanUpSharedFile() {
            return
        }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            showConnectionMessage(L10n.text("shortcut.airdrop.unsupported"))
            return
        }
        guard
            let template = Bundle.main.url(
                forResource: "Template",
                withExtension: "shortcut",
                subdirectory: "Shortcuts"
            )
        else {
            showConnectionMessage(L10n.text("shortcut.template.missing"))
            return
        }
        guard let name = try? ShortcutInstaller.normalizedName(shortcutName.stringValue) else {
            updateShortcutName()
            return
        }
        shortcutName.stringValue = name
        let receiveAddress = address.stringValue
        let key = inbox.configuration.receiver.token
        setSending(true)
        showConnectionMessage(L10n.text("Creating and signing the shortcut…"), isError: false)
        Task {
            do {
                let file = try await Task.detached {
                    try ShortcutInstaller.prepare(
                        templateURL: template,
                        address: receiveAddress,
                        key: key,
                        name: name
                    )
                }.value
                sharedFile = file
                guard service.canPerform(withItems: [file]) else {
                    if cleanUpSharedFile() {
                        showConnectionMessage(L10n.text("shortcut.airdrop.unavailable"))
                    }
                    setSending(false)
                    return
                }
                sharingService = service
                service.delegate = self
                showConnectionMessage(L10n.text("shortcut.airdrop.choosePhone"), isError: false)
                service.perform(withItems: [file])
            } catch {
                showConnectionMessage(
                    L10n.text("Unable to send the shortcut: %@", error.localizedDescription)
                )
                setSending(false)
            }
        }
    }

    private func saveShortcutName(_ name: String) {
        do {
            var sender = inbox.configuration.sender
            sender.shortcutName = name
            try inbox.apply(sender: sender)
        } catch {
            showConnectionMessage(error.localizedDescription)
        }
    }

    private func cleanUpSharedFile() -> Bool {
        guard let file = sharedFile else {
            return true
        }
        do {
            try ShortcutInstaller.cleanUp(file)
            sharedFile = nil
            return true
        } catch {
            showConnectionMessage(L10n.text("shortcut.cleanup.failed", error.localizedDescription))
            return false
        }
    }

    @objc private func exportShortcut() {
        guard
            let source = Bundle.main.url(
                forResource: "发送到 Mac",
                withExtension: "shortcut",
                subdirectory: "Shortcuts"
            )
        else {
            showConnectionMessage(L10n.text("shortcut.resource.missing"))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L10n.text("Send to Mac") + ".shortcut"
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { showConnectionMessage(L10n.text(
                "Export failed: %@",
                error.localizedDescription
            )) }
        }
    }
}

@MainActor
private final class SettingsGroup: NSView {
    override func draw(_: NSRect) {
        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 10,
            yRadius: 10
        )
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
