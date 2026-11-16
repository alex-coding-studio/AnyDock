import Foundation
import UniformTypeIdentifiers

enum FileTypeDetector {
    private struct Signature {
        let offset: Int
        let bytes: [UInt8]
        let type: UTType
    }

    private static let signatures = [
        Signature(offset: 0, bytes: Array("%PDF-".utf8), type: .pdf),
        Signature(offset: 0, bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], type: .png),
        Signature(offset: 0, bytes: [0xFF, 0xD8, 0xFF], type: .jpeg),
        Signature(offset: 0, bytes: Array("GIF8".utf8), type: .gif),
        Signature(offset: 4, bytes: Array("ftypheic".utf8), type: .heic),
        Signature(offset: 4, bytes: Array("ftypheix".utf8), type: .heic),
        Signature(offset: 0, bytes: [0x50, 0x4B, 0x03, 0x04], type: .zip),
    ]

    static func filename(_ filename: String, matching data: Data) -> String {
        guard let detected = detectedType(of: data),
              let detectedExtension = detected.preferredFilenameExtension
        else {
            return filename
        }
        if let declared = declaredType(of: filename) {
            let matchesContent = declared.conforms(to: detected)
            let canBeChecked = isDetectable(declared) || declared.conforms(to: .text)
            if matchesContent || !canBeChecked {
                return filename
            }
        }
        return filename + "." + detectedExtension
    }

    static func isPlainText(_ data: Data, filename: String) -> Bool {
        guard declaredType(of: filename)?.conforms(to: .text) == true, !data.contains(0) else {
            return false
        }
        return String(data: data, encoding: .utf8) != nil
    }

    static func isPlainTextFile(_ url: URL) -> Bool {
        guard declaredType(of: url.lastPathComponent)?.conforms(to: .text) == true,
              let data = try? Data(contentsOf: url)
        else {
            return false
        }
        return isPlainText(data, filename: url.lastPathComponent)
    }

    private static func detectedType(of data: Data) -> UTType? {
        signatures.first { data.dropFirst($0.offset).starts(with: $0.bytes) }?.type
    }

    private static func declaredType(of filename: String) -> UTType? {
        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension),
              type.isDeclared
        else {
            return nil
        }
        return type
    }

    private static func isDetectable(_ type: UTType) -> Bool {
        signatures.contains { type.conforms(to: $0.type) }
    }
}
