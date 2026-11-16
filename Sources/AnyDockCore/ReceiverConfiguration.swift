import Foundation

public struct ReceiverConfiguration: Codable, Sendable {
    public var port: UInt16
    public var directory: URL
    public var token: String

    public init(port: UInt16 = 8765, directory: URL, token: String) {
        self.port = port
        self.directory = directory
        self.token = token
    }
}
