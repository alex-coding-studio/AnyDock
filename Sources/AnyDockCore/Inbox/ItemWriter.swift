import Darwin
import Foundation

final class ItemWriter {
    let directory: URL

    private let rootHandle: FileHandle
    private let directoryHandle: FileHandle
    private let directoryName: String

    init(in root: URL, kind: ReceivedKind) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rootDescriptor = open(
            root.resolvingSymlinksInPath().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        rootHandle = FileHandle(fileDescriptor: rootDescriptor, closeOnDealloc: true)
        directoryName = kind.directoryName
        directory = root.appendingPathComponent(directoryName, isDirectory: true)
        guard mkdirat(rootDescriptor, directoryName, 0o700) == 0 || errno == EEXIST else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let descriptor = openat(
            rootDescriptor,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        directoryHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try validateDirectory()
    }

    func write(_ data: Data, named filename: String, quarantined: Bool) throws {
        let parent = directoryHandle.fileDescriptor
        let staging = "." + UUID().uuidString + ".pending"
        defer { unlinkat(parent, staging, 0) }
        let descriptor = openat(
            parent,
            staging,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        if quarantined {
            let timestamp = String(UInt64(Date().timeIntervalSince1970), radix: 16)
            let properties = Data("0083;\(timestamp);AnyDock;\(UUID().uuidString)".utf8)
            let result = properties.withUnsafeBytes {
                fsetxattr(descriptor, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0)
            }
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard fgetxattr(descriptor, "com.apple.quarantine", nil, 0, 0, 0) > 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try handle.close()
        try validateDirectory()
        guard renameatx_np(parent, staging, parent, filename, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try validateDirectory()
        } catch {
            unlinkat(parent, filename, 0)
            throw error
        }
    }

    private func validateDirectory() throws {
        var opened = stat()
        var named = stat()
        guard fstat(directoryHandle.fileDescriptor, &opened) == 0,
              fstatat(rootHandle.fileDescriptor, directoryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino,
              named.st_mode & S_IFMT == S_IFDIR
        else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }
}
