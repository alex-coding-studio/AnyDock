import AppKit
import Foundation
import Testing
@testable import AnyDock
@testable import AnyDockCore

@MainActor
private struct Fixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func entry(
        _ name: String,
        kind: ReceivedKind,
        contents: Data,
        plainText: Bool = false
    ) throws -> TrayEntry {
        let url = folder.appendingPathComponent("AnyDock-\(name)")
        try contents.write(to: url)
        return TrayEntry(item: ReceivedItem(
            url: url,
            kind: kind,
            thumbnail: nil,
            receivedAt: Date(),
            isPlainText: plainText
        ))
    }

    func text(_ name: String, _ value: String) throws -> TrayEntry {
        try entry(name, kind: .text, contents: Data(value.utf8))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

private let columnWidth: CGFloat = 99

@MainActor
@Test("拍立得卡片按内容计算高度：短内容比长内容矮，超长内容被上限截住")
func polaroidHeightFollowsContentUpToLimit() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let sizing = TrayCardSizing()
    let short = try sizing.heightRatio(
        of: fixture.text("short.txt", "hi"),
        columnWidth: columnWidth,
        singleColumn: false
    )
    let medium = try sizing.heightRatio(
        of: fixture.text("medium.txt", String(repeating: "word ", count: 12)),
        columnWidth: columnWidth,
        singleColumn: false
    )
    let long = try sizing.heightRatio(
        of: fixture.text("long.txt", String(repeating: "word ", count: 100)),
        columnWidth: columnWidth,
        singleColumn: false
    )
    let longer = try sizing.heightRatio(
        of: fixture.text("longer.txt", String(repeating: "word ", count: 190)),
        columnWidth: columnWidth,
        singleColumn: false
    )
    #expect(short < medium)
    #expect(medium < long)
    #expect(long == longer)
}

@MainActor
@Test("无法预览的文件卡比纯文本文件卡矮，单列文本同样按内容计算并有上限")
func genericFileIsShorterThanTextFile() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let sizing = TrayCardSizing()
    let binary = try sizing.heightRatio(
        of: fixture.entry(
            "archive.bin",
            kind: .file,
            contents: Data((0 ..< 2048).map { UInt8($0 % 251) })
        ),
        columnWidth: columnWidth,
        singleColumn: false
    )
    let notes = try sizing.heightRatio(
        of: fixture.entry(
            "notes.txt",
            kind: .file,
            contents: Data(String(repeating: "line of notes\n", count: 40).utf8),
            plainText: true
        ),
        columnWidth: columnWidth,
        singleColumn: false
    )
    #expect(binary < notes)
    let wide: CGFloat = 432
    let shortRow = try sizing.heightRatio(
        of: fixture.text("row.txt", "hi"),
        columnWidth: wide,
        singleColumn: true
    )
    let longRow = try sizing.heightRatio(
        of: fixture.text("rows.txt", String(repeating: "word ", count: 150)),
        columnWidth: wide,
        singleColumn: true
    )
    let longerRow = try sizing.heightRatio(
        of: fixture.text("more.txt", String(repeating: "word ", count: 190)),
        columnWidth: wide,
        singleColumn: true
    )
    #expect(shortRow < longRow)
    #expect(longRow == longerRow)
}
