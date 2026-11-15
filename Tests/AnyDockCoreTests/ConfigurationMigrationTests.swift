import Foundation
import Testing

@testable import AnyDockCore

@Test("旧配置与偏好复制到新位置，旧数据保留且成功后不再迁移")
func migratesLegacyConfigurationOnce() throws {
  let fixture = try MigrationFixture()
  defer { fixture.cleanUp() }
  let data = try fixture.writeLegacyConfiguration()
  fixture.defaults.setPersistentDomain(
    [
      "appearance": "dark", "AppleLanguages": ["zh-Hans"], "thumbnailColumns": 4,
      "copyNewItems": true,
      "personalizedShortcutName": "发送到测试 Mac",
    ], forName: fixture.legacyDomain)

  #expect(fixture.migrate() == nil)
  #expect(try Data(contentsOf: fixture.configuration) == data)
  #expect(try Data(contentsOf: fixture.legacyConfiguration) == data)
  let preferences = fixture.defaults.persistentDomain(forName: fixture.domain)
  #expect(preferences?["appearance"] as? String == "dark")
  #expect(preferences?["thumbnailColumns"] as? Int == 4)
  #expect(preferences?["copyNewItems"] as? Bool == true)
  #expect(preferences?["personalizedShortcutName"] as? String == "发送到测试 Mac")
  #expect(AppLanguage.current(in: fixture.defaults, domain: fixture.domain) == .simplifiedChinese)
  let legacyPreferences = fixture.defaults.persistentDomain(forName: fixture.legacyDomain)
  #expect(legacyPreferences?["appearance"] as? String == "dark")

  try FileManager.default.removeItem(at: fixture.configuration)
  #expect(fixture.migrate() == nil)
  #expect(!FileManager.default.fileExists(atPath: fixture.configuration.path))
}

@Test("新配置已存在时不覆盖文件和偏好")
func preservesExistingConfiguration() throws {
  let fixture = try MigrationFixture()
  defer { fixture.cleanUp() }
  _ = try fixture.writeLegacyConfiguration()
  fixture.defaults.setPersistentDomain(
    [
      "appearance": "dark", "thumbnailColumns": 5, "AppleLanguages": ["zh-Hans"],
      "copyNewItems": true,
      "personalizedShortcutName": "发送到原来的 Mac",
    ], forName: fixture.legacyDomain)
  fixture.defaults.setPersistentDomain(
    ["appearance": "light", "copyNewItems": false], forName: fixture.domain)
  try FileManager.default.createDirectory(
    at: fixture.configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
  let current = Data("existing-new-configuration".utf8)
  try current.write(to: fixture.configuration)

  #expect(fixture.migrate() == nil)
  #expect(try Data(contentsOf: fixture.configuration) == current)
  let preferences = fixture.defaults.persistentDomain(forName: fixture.domain)
  #expect(preferences?["appearance"] as? String == "light")
  #expect(preferences?["copyNewItems"] as? Bool == false)
  #expect(preferences?["thumbnailColumns"] as? Int == 5)
  #expect(preferences?["personalizedShortcutName"] as? String == "发送到原来的 Mac")
  #expect(AppLanguage.current(in: fixture.defaults, domain: fixture.domain) == .simplifiedChinese)
}

@Test("没有旧配置或偏好时不创建新数据")
func skipsMissingLegacyConfiguration() throws {
  let fixture = try MigrationFixture()
  defer { fixture.cleanUp() }
  #expect(fixture.migrate() == nil)
  #expect(
    !FileManager.default.fileExists(atPath: fixture.configuration.deletingLastPathComponent().path))
  #expect(fixture.defaults.persistentDomain(forName: fixture.domain) == nil)
}

@Test("失败不写完成标记或新偏好，修复后下次可以成功迁移且保留新偏好")
func retriesMigrationAfterFailure() throws {
  let fixture = try MigrationFixture()
  defer { fixture.cleanUp() }
  let data = try fixture.writeLegacyConfiguration()
  fixture.defaults.setPersistentDomain(
    ["appearance": "dark", "AppleLanguages": ["zh-Hans"]], forName: fixture.legacyDomain)
  let blockedDirectory = fixture.configuration.deletingLastPathComponent()
  try Data("blocked".utf8).write(to: blockedDirectory)
  #expect(fixture.migrate() == .copyFailed)
  #expect(fixture.defaults.persistentDomain(forName: fixture.domain) == nil)
  #expect(try Data(contentsOf: fixture.legacyConfiguration) == data)

  try FileManager.default.removeItem(at: blockedDirectory)
  fixture.defaults.setPersistentDomain(
    ["appearance": "light", "copyNewItems": false], forName: fixture.domain)
  #expect(fixture.migrate() == nil)
  #expect(try Data(contentsOf: fixture.configuration) == data)
  #expect(
    fixture.defaults.persistentDomain(forName: fixture.domain)?["appearance"] as? String == "light")
  #expect(AppLanguage.current(in: fixture.defaults, domain: fixture.domain) == .simplifiedChinese)
}

@Test("旧目录不可读时不能当成不存在而写入新配置")
func preservesRetryWhenLegacyDirectoryIsUnreadable() throws {
  let fixture = try MigrationFixture()
  defer { fixture.cleanUp() }
  _ = try fixture.writeLegacyConfiguration()
  fixture.defaults.setPersistentDomain(["appearance": "dark"], forName: fixture.legacyDomain)
  let directory = fixture.legacyConfiguration.deletingLastPathComponent()
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
  try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
  #expect(fixture.migrate() == .readFailed)
  #expect(!FileManager.default.fileExists(atPath: fixture.configuration.path))
  #expect(fixture.defaults.persistentDomain(forName: fixture.domain) == nil)
}

private struct MigrationFixture {
  let directory: URL
  let defaults: UserDefaults
  let domain: String
  let legacyDomain: String
  var configuration: URL { directory.appendingPathComponent("new/configuration.json") }
  var legacyConfiguration: URL { directory.appendingPathComponent("old/configuration.json") }

  init() throws {
    let identifier = UUID().uuidString
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
    domain = "AnyDockMigrationTests.new.\(identifier)"
    legacyDomain = "AnyDockMigrationTests.old.\(identifier)"
    defaults = try #require(UserDefaults(suiteName: domain))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func migrate() -> ConfigurationMigration.Failure? {
    ConfigurationMigration.migrate(
      defaults: defaults, legacyDomain: legacyDomain, domain: domain,
      legacyConfiguration: legacyConfiguration, configuration: configuration)
  }

  func writeLegacyConfiguration() throws -> Data {
    try FileManager.default.createDirectory(
      at: legacyConfiguration.deletingLastPathComponent(), withIntermediateDirectories: true)
    let configuration = ReceiverConfiguration(
      port: 9876, directory: directory.appendingPathComponent("inbox"),
      token: String(repeating: "fixture-", count: 5))
    let data = try JSONEncoder().encode(configuration)
    try data.write(to: legacyConfiguration)
    return data
  }

  func cleanUp() {
    defaults.removePersistentDomain(forName: domain)
    defaults.removePersistentDomain(forName: legacyDomain)
    try? FileManager.default.removeItem(at: directory)
  }
}
