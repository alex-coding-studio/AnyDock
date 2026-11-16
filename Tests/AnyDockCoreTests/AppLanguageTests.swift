import Foundation
import Testing
@testable import AnyDockCore

@Test("语言覆盖只使用 App 自己的偏好，跟随系统会移除覆盖")
func languageOverrideUsesOnlyApplicationPreferences() throws {
    let domain = "AnyDockTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.register(defaults: ["AppleLanguages": ["zh-Hans"]])
    #expect(AppLanguage.current(in: defaults, domain: domain) == .system)
    AppLanguage.english.save(in: defaults)
    #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["en"])
    #expect(AppLanguage.current(in: defaults, domain: domain) == .english)
    AppLanguage.simplifiedChinese.save(in: defaults)
    #expect(AppLanguage.current(in: defaults, domain: domain) == .simplifiedChinese)
    AppLanguage.system.save(in: defaults)
    #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
    #expect(AppLanguage.current(in: defaults, domain: domain) == .system)
}
