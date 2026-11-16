import AnyDockCore
import AppKit
import Combine
import OSLog

@MainActor
final class AppServiceProvider {
    private static let logger = Logger(subsystem: "com.cuxiao.mac.anydock", category: "Receiver")
    private static let settingsArgument = "--settings"
    private static let trayArgument = "--tray"

    private let inbox: Inbox
    private let clipboard = ClipboardMonitor(isEnabled: Preferences.keepsClipboardHistoryChanges)
    private let hotKeys = GlobalHotKeyCenter()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var statusItem = StatusItemController(status: inbox.status)

    private lazy var trayPopover = TrayPopoverController(
        inbox: inbox,
        clipboard: clipboard,
        statusItem: statusItem
    )

    private lazy var settings = makeSettings()

    init(configuration: ConnectionConfiguration, store: ConnectionConfigurationStore) {
        inbox = Inbox(configuration: configuration, store: store)
        subscribeEvents()
    }

    static func loadConfiguration(
        from store: ConnectionConfigurationStore
    ) -> ConnectionConfiguration? {
        do {
            return try store.load()
        } catch {
            logger.error(
                "Configuration could not be loaded: \(error.localizedDescription, privacy: .public)"
            )
            let alert = NSAlert(error: error)
            alert.messageText = L10n.text("Unable to Read AnyDock Configuration")
            alert.informativeText = L10n.text("configuration.recovery")
            alert.runModal()
            NSApp.terminate(nil)
            return nil
        }
    }

    func start(arguments: [String]) {
        _ = hotKeys.register(Preferences.wakeHotKey)
        Task { await inbox.start() }
        if arguments.contains(Self.settingsArgument) {
            showSettings()
        }
        if arguments.contains(Self.trayArgument) {
            trayPopover.toggle()
        }
    }

    func showSettings() {
        trayPopover.close()
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    private func makeSettings() -> SettingsWindowController {
        let about = AboutInfo(bundle: .main)
        let connection = ConnectionSettingsViewModel(
            receiver: inbox,
            host: SystemHostInformation(),
            sharing: AirDropShortcutSharing(),
            pasteboard: SettingsPasteboardWriter()
        )
        let general = GeneralSettingsViewModel(
            preferences: UserSettingsPreferences(),
            loginItem: SystemLoginItem(),
            hotKeys: hotKeys,
            restarter: ApplicationRestarter(),
            sharing: connection.isSending
        )
        return SettingsWindowController(rootView: SettingsRootView(
            viewModel: SettingsViewModel(status: inbox.status, about: about),
            general: general,
            connection: connection,
            receiving: ReceivingSettingsViewModel(receiver: inbox)
        ))
    }

    private func subscribeEvents() {
        trayPopover.settingsRequests
            .sink { [weak self] in self?.showSettings() }
            .store(in: &subscriptions)
        hotKeys.presses
            .sink { [weak self] in self?.trayPopover.toggle() }
            .store(in: &subscriptions)
    }
}
