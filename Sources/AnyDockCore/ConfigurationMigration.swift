import Foundation

public enum ConfigurationMigration {
  public static let completionKey = "bundleIDMigrationCompleted"

  public enum Failure: String, Error, Sendable {
    case supportUnavailable
    case readFailed
    case invalidConfiguration
    case copyFailed
  }

  public static func migrate(
    defaults: UserDefaults, legacyDomain: String, domain: String,
    legacyConfiguration: URL, configuration: URL
  ) -> Failure? {
    let manager = FileManager.default
    let preferences = defaults.persistentDomain(forName: domain) ?? [:]
    guard preferences[completionKey] as? Bool != true,
      !manager.fileExists(atPath: configuration.path)
    else { return nil }
    let legacyPreferences = defaults.persistentDomain(forName: legacyDomain) ?? [:]
    let hasLegacyFile: Bool
    do {
      _ = try manager.attributesOfItem(atPath: legacyConfiguration.path)
      hasLegacyFile = true
    } catch let error as CocoaError {
      guard error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile else {
        return .readFailed
      }
      hasLegacyFile = false
    } catch {
      return .readFailed
    }
    guard hasLegacyFile || !legacyPreferences.isEmpty else { return nil }

    if hasLegacyFile {
      let data: Data
      do {
        data = try Data(contentsOf: legacyConfiguration)
      } catch {
        return .readFailed
      }
      guard let legacy = try? JSONDecoder().decode(ReceiverConfiguration.self, from: data),
        legacy.port >= 1024, legacy.token.utf8.count >= 32, legacy.directory.isFileURL
      else { return .invalidConfiguration }
      let directory = configuration.deletingLastPathComponent()
      let temporary = directory.appendingPathComponent(".migration-\(UUID().uuidString)")
      do {
        try manager.createDirectory(
          at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try manager.moveItem(at: temporary, to: configuration)
      } catch {
        return .copyFailed
      }
    }

    var migrated = legacyPreferences.merging(preferences) { _, current in current }
    migrated[completionKey] = true
    defaults.setPersistentDomain(migrated, forName: domain)
    return nil
  }
}
