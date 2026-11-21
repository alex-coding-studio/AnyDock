import Combine
import Foundation
import OSLog
import UserNotifications

@MainActor
protocol NotificationAuthorizing: AnyObject {
    func isDenied() async -> Bool
    func requestAuthorization() async throws -> Bool
}

@MainActor
final class ReceiveNotifications: NSObject, NotificationAuthorizing, UNUserNotificationCenterDelegate {
    private nonisolated static let logger = Logger(
        subsystem: "com.cuxiao.mac.anydock",
        category: "Notifications"
    )

    private let center: UNUserNotificationCenter?
    private let trayRequestSubject = PassthroughSubject<Void, Never>()

    var trayRequests: AnyPublisher<Void, Never> {
        trayRequestSubject.eraseToAnyPublisher()
    }

    init(bundle: Bundle) {
        center = bundle.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
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
