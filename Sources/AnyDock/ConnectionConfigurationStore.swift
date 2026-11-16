import AnyDockCore
import Foundation
import Security

@MainActor
final class ConnectionConfigurationStore {
    private enum Constants {
        static let configurationFile = URL.applicationSupportDirectory.appending(
            path: "AnyDock/configuration.json"
        )
        static let defaultReceiveDirectory = URL.downloadsDirectory.appending(
            path: "AnyDock",
            directoryHint: .isDirectory
        )
        static let minimumPort: UInt16 = 1024
        static let minimumTokenLength = 32
        static let generatedTokenByteCount = 32
        static let configurationFolderPermissions = 0o700
        static let configurationFilePermissions = 0o600
    }

    private static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: Constants.generatedTokenByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func load() throws -> ConnectionConfiguration {
        if FileManager.default.fileExists(atPath: Constants.configurationFile.path) {
            let result = try JSONDecoder().decode(
                ConnectionConfiguration.self,
                from: Data(contentsOf: Constants.configurationFile)
            )
            guard result.receiver.port >= Constants.minimumPort,
                  result.receiver.token.utf8.count >= Constants.minimumTokenLength,
                  result.receiver.directory.isFileURL
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return result
        }
        let configuration = try ConnectionConfiguration(
            receiver: .init(directory: Constants.defaultReceiveDirectory, token: Self.makeToken())
        )
        try save(configuration)
        return configuration
    }

    func save(_ configuration: ConnectionConfiguration) throws {
        try FileManager.default.createDirectory(
            at: Constants.configurationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Constants.configurationFolderPermissions]
        )
        try JSONEncoder().encode(configuration).write(
            to: Constants.configurationFile,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: Constants.configurationFilePermissions],
            ofItemAtPath: Constants.configurationFile.path
        )
    }
}
