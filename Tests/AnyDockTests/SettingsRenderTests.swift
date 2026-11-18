import AnyDockCore
import AppKit
import Combine
import SwiftUI
import Testing
@testable import AnyDock

@MainActor
@Test(
    "离线渲染设置各页到临时目录，仅在设置 ANYDOCK_RENDER_SETTINGS 时运行",
    .enabled(if: ProcessInfo.processInfo.environment["ANYDOCK_RENDER_SETTINGS"] != nil)
)
func renderSettingsPages() throws {
    let language = ProcessInfo.processInfo.environment["ANYDOCK_RENDER_LANGUAGE"] ?? "en"
    let localization = try #require(Bundle.settingsLocalization(language))
    try L10n.$bundle.withValue(localization) {
        try renderPages(language: language)
    }
}

@MainActor
private func renderPages(language: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "anydock-settings-renders"
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        for (name, view, size) in makePages() {
            let data = try render(view, size: size, appearance: appearance)
            try data.write(
                to: directory.appendingPathComponent("\(name)-\(language)-\(suffix).png")
            )
        }
    }
}

@MainActor
private func makeGeneral(
    _ preferences: FakePreferences,
    hotKeys: FakeHotKeys = FakeHotKeys()
) -> GeneralSettingsViewModel {
    GeneralSettingsViewModel(
        preferences: preferences,
        loginItem: FakeLoginItem(),
        hotKeys: hotKeys,
        restarter: FakeRestarter(),
        sharing: Just(false).eraseToAnyPublisher()
    )
}

@MainActor
private func makePages() -> [(String, AnyView, NSSize)] {
    let receiver = FakeReceiver()
    receiver.statusSubject.send(.listening(port: 8766))
    let preferences = FakePreferences()
    preferences.wakeHotKey = KeyCombination(keyCode: 49, modifiers: [.control, .option])
    let hotKeys = FakeHotKeys()
    _ = hotKeys.register(preferences.wakeHotKey)
    let general = makeGeneral(preferences, hotKeys: hotKeys)
    general.selectLanguage(.simplifiedChinese)
    let connection = ConnectionSettingsViewModel(
        receiver: receiver,
        host: FakeHost(computerName: "MacBook Pro"),
        sharing: FakeSharing(),
        pasteboard: FakePasteboard()
    )
    let receiving = ReceivingSettingsViewModel(receiver: receiver)
    receiving.setPortText("8767")
    let settings = SettingsViewModel(
        status: receiver.status,
        about: AboutInfo(version: "Version 1.0.1 (2)")
    )
    let detail = NSSize(
        width: SettingsMetrics.windowContentWidth - SettingsMetrics.sidebarWidth,
        height: SettingsMetrics.windowContentHeight
    )
    let narrow = NSSize(
        width: SettingsMetrics.windowMinimumWidth - SettingsMetrics.sidebarWidth,
        height: SettingsMetrics.windowMinimumHeight
    )
    let longHotKeys = FakePreferences()
    longHotKeys.wakeHotKey = KeyCombination(
        keyCode: 49,
        modifiers: [.control, .option, .shift, .command]
    )
    let generalNarrow = makeGeneral(longHotKeys)
    let generalEmpty = makeGeneral(FakePreferences())
    return [
        ("general-minimum", AnyView(GeneralSettingsView(viewModel: generalNarrow)), narrow),
        ("general-no-shortcut", AnyView(GeneralSettingsView(viewModel: generalEmpty)), detail),
        (
            "general-no-shortcut-minimum",
            AnyView(GeneralSettingsView(viewModel: generalEmpty)),
            narrow
        ),
        ("sidebar", AnyView(SettingsSidebar(viewModel: settings)), NSSize(
            width: SettingsMetrics.sidebarWidth,
            height: SettingsMetrics.windowContentHeight
        )),
        ("general", AnyView(GeneralSettingsView(viewModel: general)), detail),
        ("connection", AnyView(ConnectionSettingsView(viewModel: connection)), detail),
        ("receiving", AnyView(ReceivingSettingsView(viewModel: receiving)), detail),
        ("about", AnyView(AboutSettingsView(viewModel: settings)), detail),
    ]
}

private extension Bundle {
    static func settingsLocalization(_ language: String) -> Bundle? {
        L10n.bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

@MainActor
private func render(_ view: AnyView, size: NSSize, appearance: NSAppearance.Name) throws -> Data {
    let host = NSHostingView(rootView: view
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.controlActiveState, .key))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: host.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: appearance)
    window.contentView = host
    for _ in 0 ..< 5 {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
