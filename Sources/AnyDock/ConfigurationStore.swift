import AnyDockCore
import Foundation
import Security

@MainActor
final class ConfigurationStore {
  private let url: URL

  init() throws {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("SnapDock", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    url = directory.appendingPathComponent("configuration.json")
  }

  func load() throws -> ReceiverConfiguration {
    if FileManager.default.fileExists(atPath: url.path) {
      let result = try JSONDecoder().decode(ReceiverConfiguration.self, from: Data(contentsOf: url))
      guard result.port >= 1024, result.token.utf8.count >= 32, result.directory.isFileURL else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return result
    }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw CocoaError(.fileWriteUnknown)
    }
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/SnapDock", isDirectory: true)
    let configuration = ReceiverConfiguration(
      directory: directory, token: bytes.map { String(format: "%02x", $0) }.joined())
    try save(configuration)
    return configuration
  }

  func save(_ configuration: ReceiverConfiguration) throws {
    try JSONEncoder().encode(configuration).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
