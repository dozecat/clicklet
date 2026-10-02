import Foundation
import XCTest


/// 「解压到当前文件夹」不该让调用方去"显示结果"。
final class DecompressHereRevealTests: XCTestCase {
    func testDecompressHereReturnsNothingToReveal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 造一个真的 zip
        let payload = root.appendingPathComponent("payload.txt")
        try Data("hello\n".utf8).write(to: payload)

        let archive = root.appendingPathComponent("sample.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-X", archive.lastPathComponent, payload.lastPathComponent]
        zip.currentDirectoryURL = root
        try zip.run()
        zip.waitUntilExit()
        try FileManager.default.removeItem(at: payload)

        let result = try await ArchiveService.perform(
            .decompressHere,
            urls: [archive],
            in: root
        )

        XCTAssertNil(result, "就地解压没有新目录可显示，应该返回 nil")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("payload.txt").path),
            "文件应该已经解压到当前文件夹"
        )
    }
}
