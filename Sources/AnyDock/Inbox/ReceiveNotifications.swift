import Combine
import Foundation
import OSLog
import UserNotifications

@MainActor
protocol NotificationAuthorizing: AnyObject {
    var canRequestAuthorization: Bool { get }
    var authorizationChanges: AnyPublisher<Void, Never> { get }
    func isDenied() async -> Bool
    func requestAuthorization() async throws -> Bool
}

@MainActor
protocol NotificationLaunchPreferences: AnyObject {
    var receiveNotifications: Bool { get set }
    var hasReceiveNotificationsPreference: Bool { get }
    var hasRequestedNotificationPermission: Bool { get set }
}

@MainActor
final class ReceiveNotifications: NSObject, NotificationAuthorizing, UNUserNotificationCenterDelegate {
    private nonisolated static let logger = Logger(
        subsystem: "com.cuxiao.mac.anydock",
        category: "Notifications"
    )

    private let center: UNUserNotificationCenter?
    private let trayRequestSubject = PassthroughSubject<Void, Never>()
    private let authorizationChangeSubject = PassthroughSubject<Void, Never>()

    var canRequestAuthorization: Bool {
        center != nil
    }

    var trayRequests: AnyPublisher<Void, Never> {
        trayRequestSubject.eraseToAnyPublisher()
    }

    var authorizationChanges: AnyPublisher<Void, Never> {
        authorizationChangeSubject.eraseToAnyPublisher()
    }

    init(bundle: Bundle) {
        center = bundle.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
    }

    static func requestInitialAuthorizationIfNeeded(
        using authorizer: any NotificationAuthorizing,
        preferences: any NotificationLaunchPreferences
    ) async -> Bool {
        guard authorizer.canRequestAuthorization,
              !preferences.hasRequestedNotificationPermission,
              !preferences.hasReceiveNotificationsPreference
        else {
            return false
        }
        preferences.hasRequestedNotificationPermission = true
        do {
            let granted = try await authorizer.requestAuthorization()
            if granted, !preferences.hasReceiveNotificationsPreference {
                preferences.receiveNotifications = true
            }
        } catch {
            logger.error(
                "Unable to request initial notification authorization: \(error.localizedDescription)"
            )
        }
        return true
    }

    func requestAuthorizationOnFirstLaunch(
        preferences: any NotificationLaunchPreferences
    ) async {
        if await Self.requestInitialAuthorizationIfNeeded(
            using: self,
            preferences: preferences
        ) {
            authorizationChangeSubject.send()
        }
    }

    func isDenied() async -> Bool {
        await center?.notificationSettings().authorizationStatus == .denied
    }

    func requestAuthorization() async throws -> Bool {
        guard let center else {
            throw CocoaError(.featureUnsupported)
        }
        return try await center.requestAuthorization(options: [.alert, .sound])
    }

    func postArrival() {
        guard Preferences.receiveNotifications, let center else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = L10n.text("New item received")
        content.body = L10n.text("Open the tray to view it.")
        content.sound = .default
        content.threadIdentifier = "receipts"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                Self.logger.error(
                    "Unable to deliver receipt notification: \(error.localizedDescription)"
                )
            }
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await showTray()
        }
    }

    private func showTray() {
        trayRequestSubject.send()
    }
}
