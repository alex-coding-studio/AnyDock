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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "anydock-settings-renders"
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let receiver = FakeReceiver()
    receiver.statusSubject.send(.listening(port: 8766))
    let preferences = FakePreferences()
    preferences.wakeHotKey = KeyCombination(keyCode: 49, modifiers: [.control, .option])
    let hotKeys = FakeHotKeys()
    _ = hotKeys.register(preferences.wakeHotKey)
    let general = GeneralSettingsViewModel(
        preferences: preferences,
        loginItem: FakeLoginItem(),
        hotKeys: hotKeys,
        restarter: FakeRestarter(),
        sharing: Just(false).eraseToAnyPublisher()
    )
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
    let generalNarrow = GeneralSettingsViewModel(
        preferences: longHotKeys,
        loginItem: FakeLoginItem(),
        hotKeys: FakeHotKeys(),
        restarter: FakeRestarter(),
        sharing: Just(false).eraseToAnyPublisher()
    )
    let pages: [(String, AnyView, NSSize)] = [
        ("general-minimum", AnyView(GeneralSettingsView(viewModel: generalNarrow)), narrow),
        ("sidebar", AnyView(SettingsSidebar(viewModel: settings)), NSSize(
            width: SettingsMetrics.sidebarWidth,
            height: SettingsMetrics.windowContentHeight
        )),
        ("general", AnyView(GeneralSettingsView(viewModel: general)), detail),
        ("connection", AnyView(ConnectionSettingsView(viewModel: connection)), detail),
        ("receiving", AnyView(ReceivingSettingsView(viewModel: receiving)), detail),
        ("about", AnyView(AboutSettingsView(about: settings.about)), detail),
    ]
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        for (name, view, size) in pages {
            let data = try render(view, size: size, appearance: appearance)
            try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
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
