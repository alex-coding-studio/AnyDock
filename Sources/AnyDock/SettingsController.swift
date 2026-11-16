import AnyDockCore
import AppKit
import ServiceManagement

@MainActor
final class SettingsController: NSWindowController, NSTextFieldDelegate, NSSharingServiceDelegate {
    let statusIcon = NSImageView(
        image: NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: L10n.text("Starting")
        )
            ?? NSImage()
    )
    let hotKeyRecorder = HotKeyRecorder()
    let hotKeyStatus = NSTextField(wrappingLabelWithString: "")
    var apply: ((ReceiverConfiguration) async throws -> Void)?
    var clipboardHistoryChanged: ((Bool) -> Void)?
    var registerHotKey: ((HotKey?) -> Bool)?

    private var configuration: ReceiverConfiguration
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
    private let shortcutNamePreference = "personalizedShortcutName"
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

    init(configuration: ReceiverConfiguration) {
        self.configuration = configuration
        selectedDirectory = configuration.directory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
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
        if let savedName = UserDefaults.standard.string(forKey: shortcutNamePreference) {
            shortcutName.stringValue = savedName
        } else if let computerName = LocalHost.computerName()?
            .trimmingCharacters(in: .whitespacesAndNewlines), !computerName.isEmpty {
            shortcutName.stringValue = L10n.text("Send to %@", computerName)
        } else {
            shortcutName.stringValue = L10n.text("Send to Mac")
        }
        configureMessage(hotKeyStatus)
        hotKeyRecorder.hotKey = HotKey.saved
        hotKeyRecorder.onRecordingChanged = { [weak self] recording in
            self?.hotKeyStatus.isHidden = true
            if !recording {
                self?.registerSavedHotKey()
            } else {
                _ = self?.registerHotKey?(nil)
            }
        }
        hotKeyRecorder.onRecord = { [weak self] candidate in self?.recordHotKey(candidate) }
        hotKeyRecorder.onRejected = { [weak self] in
            self?.showHotKeyMessage(L10n.text("hotkey.modifierRequired"))
        }
        clearHotKey.target = self
        clearHotKey.action = #selector(clearSavedHotKey)
        clearHotKey.bezelStyle = .rounded
        clearHotKey.controlSize = .small
        clearHotKey.setAccessibilityLabel(L10n.text("hotkey.clear.accessibility"))
        clearHotKey.isEnabled = HotKey.saved != nil
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
        guard let saved = HotKey.saved else {
            _ = registerHotKey?(nil)
            return
        }
        if registerHotKey?(saved) == false {
            showHotKeyMessage(L10n.text("hotkey.unavailable", saved.displayString))
        }
    }

    func recordHotKey(_ candidate: HotKey) {
        guard registerHotKey?(candidate) != false else {
            registerSavedHotKey()
            showHotKeyMessage(L10n.text("hotkey.unavailable", candidate.displayString))
            return
        }
        HotKey.saved = candidate
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
        receiverStatus.textColor = isError ? .systemRed : .labelColor
        statusIcon.contentTintColor = isError ? .systemRed : .systemGreen
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

    private func showHotKeyMessage(_ text: String) {
        hotKeyStatus.stringValue = text
        hotKeyStatus.isHidden = false
    }

    @objc private func clearSavedHotKey() {
        hotKeyRecorder.endRecording()
        HotKey.saved = nil
        _ = registerHotKey?(nil)
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
        appearance.selectItem(at: AppAppearance.allCases.firstIndex(of: .current) ?? 0)
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
        languageNotice.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
        autoCopy.state = TrayPreferences.copiesNewItems ? .on : .off
        autoCopy.target = self
        autoCopy.action = #selector(toggleAutoCopy)
        autoCopy.setAccessibilityLabel(L10n.text("Copy new items automatically"))
        clipboardHistory.state = TrayPreferences.keepsClipboardHistory ? .on : .off
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
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let name = NSTextField(labelWithString: L10n.text("AnyDock"))
        name.font = .systemFont(ofSize: NSFont.systemFontSize + 7, weight: .semibold)
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
        identity.spacing = 8
        identity.setCustomSpacing(12, after: icon)
        identity.setCustomSpacing(16, after: tagline)
        identity.setCustomSpacing(16, after: links)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        for view in [identity, quit] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            identity.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            identity.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -24),
            identity.leadingAnchor.constraint(
                greaterThanOrEqualTo: content.leadingAnchor,
                constant: 24
            ),
            quit.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            quit.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            quit.topAnchor.constraint(greaterThanOrEqualTo: identity.bottomAnchor, constant: 24),
        ])
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
        address.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        refreshAddress()
        let key = NSTextField(labelWithString: "•••• •••• •••• ••••")
        key.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        key.textColor = .secondaryLabelColor
        send.target = self
        send.action = #selector(sendToPhone)
        send.bezelStyle = .rounded
        send.bezelColor = .controlAccentColor
        configureMessage(connectionStatus)
        configureMessage(shortcutNameStatus)
        shortcutName.delegate = self
        shortcutName.setAccessibilityLabel(L10n.text("Shortcut name"))
        shortcutName.widthAnchor.constraint(equalToConstant: 260).isActive = true
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
        port.stringValue = String(configuration.port)
        port.placeholderString = "8765"
        port.alignment = .right
        port.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        port.widthAnchor.constraint(equalToConstant: 76).isActive = true
        port.delegate = self
        port.setAccessibilityLabel(L10n.text("Listening port"))
        statusIcon.widthAnchor.constraint(equalToConstant: 9).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 9).isActive = true
        let statusRow = row([statusIcon, receiverStatus, NSView()])
        statusRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        configureMessage(receivingError)
        pending.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
        for element in stack.arrangedSubviews {
            element.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if let bottomBar {
            bottomBar.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(bottomBar)
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(separator)
            NSLayoutConstraint.activate([
                bottomBar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                bottomBar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
                separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),
                stack.bottomAnchor.constraint(
                    lessThanOrEqualTo: separator.topAnchor,
                    constant: -12
                ),
            ])
        } else {
            let bottom = stack.bottomAnchor.constraint(
                lessThanOrEqualTo: content.bottomAnchor,
                constant: -24
            )
            bottom.isActive = true
        }
        return tabItem(title, symbol: symbol, content: content)
    }

    private func tabItem(_ title: String, symbol: String, content: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.title = title
        controller.preferredContentSize = NSSize(width: 600, height: 600)
        controller.view = content
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
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
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return stack
    }

    private func footnote(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func configureMessage(_ label: NSTextField) {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .systemRed
        label.isHidden = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func section(_ title: String, rows: [NSView], note: String? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(
            views: [label, group(rows: rows)] + (note.map { [footnote($0)] } ?? [])
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        for view in stack.arrangedSubviews.dropFirst() {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
                separator.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
            }
            contents.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
        }
        let group = SettingsGroup()
        contents.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(contents)
        NSLayoutConstraint.activate([
            contents.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 14),
            contents.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -14),
            contents.topAnchor.constraint(equalTo: group.topAnchor, constant: 5),
            contents.bottomAnchor.constraint(equalTo: group.bottomAnchor, constant: -5),
        ])
        return group
    }

    private func refreshAddress() {
        address.stringValue = LocalHost.receiveAddress(port: configuration.port)
    }

    private func refreshFolder() {
        folder.stringValue = (selectedDirectory.path as NSString).abbreviatingWithTildeInPath
        folder.toolTip = selectedDirectory.path
    }

    private func updatePending() {
        let enteredPort = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces))
        let changed = selectedDirectory != configuration.directory || enteredPort != configuration.port
        pending.stringValue = changed ? L10n.text("Unapplied changes") : ""
        save.isEnabled = changed && !isApplying
    }

    private func updateShortcutName() {
        do {
            let name = try ShortcutInstaller.normalizedName(shortcutName.stringValue)
            if !configuration.token.isEmpty {
                UserDefaults.standard.set(name, forKey: shortcutNamePreference)
            }
            shortcutNameStatus.stringValue = L10n.text("shortcut.name.normalized", name)
            shortcutNameStatus.textColor = .secondaryLabelColor
            shortcutNameStatus.isHidden = name == shortcutName.stringValue
            send.isEnabled = !isSending && !configuration.token.isEmpty
        } catch {
            shortcutNameStatus.stringValue = error.localizedDescription
            shortcutNameStatus.textColor = .systemRed
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
        var next = configuration
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
                try await apply?(next)
                configuration = next
                refreshAddress()
            } catch {
                receivingError.stringValue = error.localizedDescription
                receivingError.isHidden = false
            }
        }
    }

    @objc private func changeAppearance() {
        let index = appearance.indexOfSelectedItem
        guard AppAppearance.allCases.indices.contains(index) else {
            return
        }
        let selected = AppAppearance.allCases[index]
        UserDefaults.standard.set(selected.rawValue, forKey: "appearance")
        selected.apply()
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
        TrayPreferences.copiesNewItems = autoCopy.state == .on
    }

    @objc private func toggleClipboardHistory() {
        TrayPreferences.keepsClipboardHistory = clipboardHistory.state == .on
        clipboardHistoryChanged?(clipboardHistory.state == .on)
    }

    @objc private func copyConnectionAddress() {
        copy(address.stringValue)
    }

    @objc private func copyToken() {
        copy(configuration.token, concealed: true)
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
        connectionStatus.textColor = isError ? .systemRed : .secondaryLabelColor
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
        let key = configuration.token
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
