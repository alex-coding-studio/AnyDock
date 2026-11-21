import AnyDockCore
import AppKit
import PockyFoundation
import ServiceManagement

@MainActor
final class UserSettingsPreferences: SettingsPreferences {
    private static let domain = "com.cuxiao.mac.anydock"

    var appearance: PKYAppearance.Mode {
        get { Preferences.appearance.storedMode() }
        set {
            Preferences.appearance.save(newValue)
            NSApp.appearance = newValue.nsAppearance
        }
    }

    var language: AppLanguage {
        get { AppLanguage.current(domain: Self.domain) }
        set { newValue.save() }
    }

    var receiveNotifications: Bool {
        get { Preferences.receiveNotifications }
        set { Preferences.receiveNotifications = newValue }
    }

    var opensTrayOnArrival: Bool {
        get { Preferences.opensTrayOnArrival }
        set { Preferences.opensTrayOnArrival = newValue }
    }

    var copiesNewItems: Bool {
        get { Preferences.copiesNewItems }
        set { Preferences.copiesNewItems = newValue }
    }

    var keepsClipboardHistory: Bool {
        get { Preferences.keepsClipboardHistory }
        set { Preferences.keepsClipboardHistory = newValue }
    }

    var convertsScreenshotsToPNG: Bool {
        get { Preferences.convertsScreenshotsToPNG }
        set { Preferences.convertsScreenshotsToPNG = newValue }
    }

    var wakeHotKey: KeyCombination? {
        get { Preferences.wakeHotKey }
        set { Preferences.wakeHotKey = newValue }
    }
}

@MainActor
final class SystemLoginItem: LoginItemControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class ApplicationRestarter: ApplicationRestarting {
    var canRestart: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func restart() throws {
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
        guard UserDefaults.standard.synchronize() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try process.run()
        NSApp.terminate(nil)
    }
}

@MainActor
final class SystemHostInformation: HostInformation {
    var computerName: String? {
        LocalHost.computerName()
    }

    func receiveAddress(port: UInt16) -> String {
        LocalHost.receiveAddress(port: port)
    }
}

@MainActor
final class SettingsPasteboardWriter: SettingsPasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ text: String, concealed: Bool) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if concealed {
            pasteboard.setString("", forType: ClipboardMonitor.concealedType)
        }
    }
}
