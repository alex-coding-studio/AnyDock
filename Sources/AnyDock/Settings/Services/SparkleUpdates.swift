import Combine
import Foundation
import Sparkle

@MainActor
final class SparkleUpdates: NSObject, UpdateChecking, SPUStandardUserDriverDelegate {
    private let availableUpdateSubject = CurrentValueSubject<String?, Never>(nil)

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    var availability: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    var availableUpdate: AnyPublisher<String?, Never> {
        availableUpdateSubject.eraseToAnyPublisher()
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    init?(bundle: Bundle) {
        guard bundle.bundleURL.pathExtension == "app" else {
            return nil
        }
        super.init()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus _: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated { availableUpdateSubject.send(version) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableUpdateSubject.send(nil) }
    }
}
