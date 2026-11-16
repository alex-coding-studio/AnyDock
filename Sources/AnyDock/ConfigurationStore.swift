import AnyDockCore
import Foundation
import Security

@MainActor
final class ConfigurationStore {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Downloads/AnyDock",
            isDirectory: true
        )
    }

    private let url: URL

    init() throws {
        url = try Self.applicationSupportDirectory()
            .appendingPathComponent("AnyDock/configuration.json")
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    func load() throws -> ReceiverConfiguration {
        if FileManager.default.fileExists(atPath: url.path) {
            let result = try JSONDecoder().decode(
                ReceiverConfiguration.self,
                from: Data(contentsOf: url)
            )
            guard result.port >= 1024, result.token.utf8.count >= 32, result.directory.isFileURL else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return result
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let configuration = ReceiverConfiguration(
            directory: Self.defaultDirectory,
            token: bytes.map { String(
                format: "%02x",
                $0
            ) }.joined()
        )
        try save(configuration)
        return configuration
    }

    func save(_ configuration: ReceiverConfiguration) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(configuration).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
