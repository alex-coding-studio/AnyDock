import AppKit
import PockyFoundation

@main
@MainActor
enum AnyDockApp {
    static func main() {
        let app = NSApplication.shared
        app.appearance = Preferences.appearance.storedMode().nsAppearance
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServiceProvider?

    func applicationDidFinishLaunching(_: Notification) {
        let store = ConnectionConfigurationStore()
        guard let configuration = AppServiceProvider.loadConfiguration(from: store) else {
            return
        }
        let services = AppServiceProvider(configuration: configuration, store: store)
        self.services = services
        services.start(arguments: CommandLine.arguments)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool)
        -> Bool {
        services?.showSettings()
        return true
    }
}
