#if DEBUG
    import AnyDockCore
    import Combine
    import Foundation
    import PockyFoundation
    import SwiftUI

    @MainActor
    private final class PreviewReceiver: ReceiverSettings {
        var configuration = ConnectionConfiguration(
            receiver: .init(
                directory: URL.downloadsDirectory.appending(
                    path: "AnyDock",
                    directoryHint: .isDirectory
                ),
                token: "preview"
            )
        )

        var status: AnyPublisher<InboxStatus, Never> {
            Just(.listening(
                port: ConnectionConfiguration.Receiver.defaultPort
            )).eraseToAnyPublisher()
        }

        func apply(receiver: ConnectionConfiguration.Receiver) async throws {
            configuration.receiver = receiver
        }

        func apply(sender: ConnectionConfiguration.Sender) throws {
            configuration.sender = sender
        }
    }

    @MainActor
    private final class PreviewPreferences: SettingsPreferences {
        var appearance = PKYAppearance.Mode.system
        var language = AppLanguage.system
        var copiesNewItems = false
        var keepsClipboardHistory = true
        var wakeHotKey = KeyCombination(keyCode: 49, modifiers: [.control, .option])
    }

    @MainActor
    private final class PreviewServices: LoginItemControlling, WakeHotKeyRegistering, ApplicationRestarting,
        HostInformation, SettingsPasteboard, ShortcutSharing {
        var isEnabled = false
        var requiresApproval = false
        var isRegistered = true
        var canRestart = true
        var computerName: String? = "MacBook Pro"

        func setEnabled(_: Bool) throws {}

        func register(_: KeyCombination?) -> Bool {
            true
        }

        func restart() throws {}

        func receiveAddress(port: UInt16) -> String {
            "http://MacBook-Pro.local:\(port)/upload"
        }

        func copy(_: String, concealed _: Bool) {}

        func prepare(address _: String, key _: String, name _: String) async throws -> URL {
            URL.temporaryDirectory
        }

        func share(_: URL) async throws {}

        func cleanUp(_: URL) throws {}

        func exportGenericShortcut(to _: URL) throws {}
    }

    @MainActor
    private enum PreviewModels {
        static let services = PreviewServices()
        static let receiver = PreviewReceiver()

        static var general: GeneralSettingsViewModel {
            GeneralSettingsViewModel(
                preferences: PreviewPreferences(),
                loginItem: services,
                hotKeys: services,
                restarter: services,
                sharing: Just(false).eraseToAnyPublisher()
            )
        }

        static var connection: ConnectionSettingsViewModel {
            ConnectionSettingsViewModel(
                receiver: receiver,
                host: services,
                sharing: services,
                pasteboard: services
            )
        }

        static var receiving: ReceivingSettingsViewModel {
            ReceivingSettingsViewModel(receiver: receiver)
        }

        static var root: some View {
            let settings = SettingsViewModel(
                status: receiver.status,
                about: AboutInfo(version: "Version 1.0.1 (2)")
            )
            return HStack(spacing: 0) {
                SettingsSidebar(viewModel: settings)
                    .frame(width: SettingsMetrics.sidebarWidth)
                    .background(.regularMaterial)
                SettingsDetailView(
                    viewModel: settings,
                    general: general,
                    connection: connection,
                    receiving: receiving
                )
            }
        }
    }

    #Preview("Settings · Light") {
        PreviewModels.root
            .frame(
                width: SettingsMetrics.windowContentWidth,
                height: SettingsMetrics.windowContentHeight
            )
            .preferredColorScheme(.light)
    }

    #Preview("Settings · Dark") {
        PreviewModels.root
            .frame(
                width: SettingsMetrics.windowContentWidth,
                height: SettingsMetrics.windowContentHeight
            )
            .preferredColorScheme(.dark)
    }

    #Preview("General · Light") {
        GeneralSettingsView(viewModel: PreviewModels.general).preferredColorScheme(.light)
    }

    #Preview("General · Dark") {
        GeneralSettingsView(viewModel: PreviewModels.general).preferredColorScheme(.dark)
    }

    #Preview("Connection · Light") {
        ConnectionSettingsView(viewModel: PreviewModels.connection).preferredColorScheme(.light)
    }

    #Preview("Connection · Dark") {
        ConnectionSettingsView(viewModel: PreviewModels.connection).preferredColorScheme(.dark)
    }

    #Preview("Receiving · Light") {
        ReceivingSettingsView(viewModel: PreviewModels.receiving).preferredColorScheme(.light)
    }

    #Preview("Receiving · Dark") {
        ReceivingSettingsView(viewModel: PreviewModels.receiving).preferredColorScheme(.dark)
    }

    #Preview("About · Light") {
        AboutSettingsView(about: AboutInfo(
            version: "Version 1.0.1 (2)"
        )).preferredColorScheme(.light)
    }

    #Preview("About · Dark") {
        AboutSettingsView(about: AboutInfo(
            version: "Version 1.0.1 (2)"
        )).preferredColorScheme(.dark)
    }
#endif
