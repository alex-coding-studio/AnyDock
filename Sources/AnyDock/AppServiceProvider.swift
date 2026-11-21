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
    private let updates = SparkleUpdates(bundle: .main)
    private let notifications = ReceiveNotifications(bundle: .main)
    private let mainMenu = MainMenu()
    private var subscriptions = Set<AnyCancellable>()

    private lazy var statusItem = StatusItemController(status: inbox.status)

    private lazy var trayPopover = TrayPopoverController(
        inbox: inbox,
        clipboard: clipboard,
        statusItem: statusItem,
        updates: updates
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
        NSApp.mainMenu = mainMenu.make()
        _ = hotKeys.register(Preferences.wakeHotKey)
        Task { await inbox.start() }
        Task {
            await notifications.requestAuthorizationOnFirstLaunch(
                preferences: UserSettingsPreferences()
            )
        }
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
        let preferences = UserSettingsPreferences()
        let connection = ConnectionSettingsViewModel(
            receiver: inbox,
            host: SystemHostInformation(),
            sharing: AirDropShortcutSharing(),
            pasteboard: SettingsPasteboardWriter()
        )
        let general = GeneralSettingsViewModel(
            preferences: preferences,
            loginItem: SystemLoginItem(),
            notifications: notifications,
            hotKeys: hotKeys,
            restarter: ApplicationRestarter(),
            sharing: connection.isSending
        )
        return SettingsWindowController(
            viewModel: SettingsViewModel(
                status: inbox.status,
                about: about,
                updates: updates
            ),
            general: general,
            connection: connection,
            receiving: ReceivingSettingsViewModel(receiver: inbox, preferences: preferences)
        )
    }

    private func subscribeEvents() {
        trayPopover.settingsRequests
            .merge(with: mainMenu.settingsRequests)
            .sink { [weak self] in self?.showSettings() }
            .store(in: &subscriptions)
        inbox.received
            .sink { [weak self] _ in self?.notifications.postArrival() }
            .store(in: &subscriptions)
        notifications.trayRequests
            .sink { [weak self] in self?.trayPopover.show() }
            .store(in: &subscriptions)
        hotKeys.presses
            .sink { [weak self] in self?.trayPopover.toggle() }
            .store(in: &subscriptions)
    }
}
