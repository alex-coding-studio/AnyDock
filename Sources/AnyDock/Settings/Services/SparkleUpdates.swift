import Combine
import Foundation
import Sparkle

@MainActor
final class SparkleUpdates: UpdateChecking {
    private let controller: SPUStandardUpdaterController

    var availability: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    init?() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
