import AnyDockCore
import Combine
import PockyFoundation

struct GeneralSettingsState: Equatable {
    var appearance: PKYAppearance.Mode
    var language: AppLanguage
    var showsRestartNotice: Bool
    var restartMessage: String?
    var launchesAtLogin: Bool
    var loginMessage: String?
    var receiveNotifications: Bool
    var opensTrayOnArrival: Bool
    var notificationsDenied = false
    var requestingNotifications = false
    var notificationError: String?
    var copiesNewItems: Bool
    var keepsClipboardHistory: Bool
    var hotKey: KeyCombination?
    var hotKeyMessage: String?
    var isRecordingHotKey = false
}

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published private(set) var state: GeneralSettingsState

    private let preferences: any SettingsPreferences
    private let loginItem: any LoginItemControlling
    private let notifications: any NotificationAuthorizing
    private let hotKeys: any WakeHotKeyRegistering
    private let restarter: any ApplicationRestarting
    private let launchLanguage: AppLanguage
    private var isSharing = false
    private var subscriptions = Set<AnyCancellable>()

    init(
        preferences: any SettingsPreferences,
        loginItem: any LoginItemControlling,
        notifications: any NotificationAuthorizing,
        hotKeys: any WakeHotKeyRegistering,
        restarter: any ApplicationRestarting,
        sharing: AnyPublisher<Bool, Never>
    ) {
        self.preferences = preferences
        self.loginItem = loginItem
        self.notifications = notifications
        self.hotKeys = hotKeys
        self.restarter = restarter
        launchLanguage = preferences.language
        let saved = preferences.wakeHotKey
        state = GeneralSettingsState(
            appearance: preferences.appearance,
            language: preferences.language,
            showsRestartNotice: false,
            launchesAtLogin: loginItem.isEnabled,
            receiveNotifications: preferences.receiveNotifications,
            opensTrayOnArrival: preferences.opensTrayOnArrival,
            copiesNewItems: preferences.copiesNewItems,
            keepsClipboardHistory: preferences.keepsClipboardHistory,
            hotKey: saved,
            hotKeyMessage: saved.flatMap { hotKeys.isRegistered ? nil : Self.unavailable($0) }
        )
        sharing
            .sink { [weak self] in self?.isSharing = $0 }
            .store(in: &subscriptions)
        notifications.authorizationChanges
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task { await self.refreshNotificationPermission() }
            }
            .store(in: &subscriptions)
    }

    private static func unavailable(_ hotKey: KeyCombination) -> String {
        L10n.text("hotkey.unavailable", hotKey.displayString)
    }

    func selectAppearance(_ mode: PKYAppearance.Mode) {
        preferences.appearance = mode
        update { $0.appearance = mode }
    }

    func selectLanguage(_ language: AppLanguage) {
        preferences.language = language
        update {
            $0.language = language
            $0.showsRestartNotice = language != launchLanguage
            $0.restartMessage = nil
        }
    }

    func restart() {
        guard !isSharing else {
            update { $0.restartMessage = L10n.text("Finish sharing before restarting AnyDock.") }
            return
        }
        guard restarter.canRestart else {
            update { $0.restartMessage = L10n.text("settings.restart.unbundled") }
            return
        }
        do {
            try restarter.restart()
        } catch {
            update {
                $0.restartMessage = L10n.text(
                    "Unable to restart AnyDock: %@",
                    error.localizedDescription
                )
            }
        }
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            update {
                $0.launchesAtLogin = enabled
                $0.loginMessage = loginItem.requiresApproval
                    ? L10n.text("Allow AnyDock in System Settings → Login Items.") : nil
            }
        } catch {
            update {
                $0.launchesAtLogin = loginItem.isEnabled
                $0.loginMessage = L10n.text(
                    "Unable to change the login item: %@",
                    error.localizedDescription
                )
            }
        }
    }

    func refreshNotificationPermission() async {
        let denied = await notifications.isDenied()
        guard !Task.isCancelled, !state.requestingNotifications else {
            return
        }
        update {
            $0.notificationsDenied = denied
            $0.receiveNotifications = preferences.receiveNotifications
        }
    }

    func setReceiveNotifications(_ enabled: Bool) async {
        guard !state.requestingNotifications else {
            return
        }
        update { $0.notificationError = nil }
        if enabled {
            update { $0.requestingNotifications = true }
            defer { update { $0.requestingNotifications = false } }
            do {
                let granted = try await notifications.requestAuthorization()
                update { $0.notificationsDenied = !granted }
                guard granted else {
                    return
                }
            } catch {
                update { $0.notificationError = error.localizedDescription }
                return
            }
        }
        preferences.receiveNotifications = enabled
        update { $0.receiveNotifications = enabled }
    }

    func setOpensTrayOnArrival(_ enabled: Bool) {
        preferences.opensTrayOnArrival = enabled
        update { $0.opensTrayOnArrival = enabled }
    }

    func setCopiesNewItems(_ enabled: Bool) {
        preferences.copiesNewItems = enabled
        update { $0.copiesNewItems = enabled }
    }

    func setKeepsClipboardHistory(_ enabled: Bool) {
        preferences.keepsClipboardHistory = enabled
        update { $0.keepsClipboardHistory = enabled }
    }

    func beginHotKeyRecording() {
        _ = hotKeys.register(nil)
        update {
            $0.hotKeyMessage = nil
            $0.isRecordingHotKey = true
        }
    }

    func endHotKeyRecording() {
        update {
            $0.hotKeyMessage = nil
            $0.isRecordingHotKey = false
        }
        registerSavedHotKey()
    }

    func record(_ candidate: KeyCombination) {
        guard hotKeys.register(candidate) else {
            registerSavedHotKey()
            update { $0.hotKeyMessage = Self.unavailable(candidate) }
            return
        }
        preferences.wakeHotKey = candidate
        update {
            $0.hotKey = candidate
            $0.hotKeyMessage = nil
        }
    }

    func rejectHotKey(_ rejection: HotKeyRejection) {
        update { $0.hotKeyMessage = L10n.text(rejection.rawValue) }
    }

    func clearHotKey() {
        preferences.wakeHotKey = nil
        _ = hotKeys.register(nil)
        update {
            $0.hotKey = nil
            $0.hotKeyMessage = nil
            $0.isRecordingHotKey = false
        }
    }

    private func registerSavedHotKey() {
        guard let saved = preferences.wakeHotKey else {
            _ = hotKeys.register(nil)
            return
        }
        if !hotKeys.register(saved) {
            update { $0.hotKeyMessage = Self.unavailable(saved) }
        }
    }

    private func update(_ change: (inout GeneralSettingsState) -> Void) {
        var next = state
        change(&next)
        state = next
    }
}
