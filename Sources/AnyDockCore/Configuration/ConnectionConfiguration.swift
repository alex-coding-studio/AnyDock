import Foundation

public struct ConnectionConfiguration: Codable, Sendable {
    public struct Receiver: Codable, Equatable, Sendable {
        public static let defaultPort: UInt16 = 8765

        public var port: UInt16
        public var directory: URL
        public var token: String

        public init(port: UInt16 = defaultPort, directory: URL, token: String) {
            self.port = port
            self.directory = directory
            self.token = token
        }
    }

    public struct Sender: Codable, Equatable, Sendable {
        public var shortcutName: String?

        public init(shortcutName: String? = nil) {
            self.shortcutName = shortcutName
        }
    }

    public var receiver: Receiver
    public var sender: Sender

    public init(receiver: Receiver, sender: Sender = Sender()) {
        self.receiver = receiver
        self.sender = sender
    }
}
