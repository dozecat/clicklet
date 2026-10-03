import XCTest
@testable import RightKit

/// The terminal path used to be computed inline as "parent of the selection", which
/// sent a right-clicked folder's terminal one level up.
final class TerminalDirectoryTests: XCTestCase {
    private let fm = FileManager.default

    func testSelectedFolderOpensAtTheFolderItself() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("img", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let resolved = TerminalTarget.directory(
            selectedPaths: [folder.path],
            directoryPath: root.path
        )
        XCTAssertEqual(resolved.path, folder.path, "选中的文件夹就应该在它自己里打开")
    }

    func testSelectedFileOpensAtItsFolder() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        defer { try? fm.removeItem(at: root) }

        let resolved = TerminalTarget.directory(
            selectedPaths: [file.path],
            directoryPath: root.path
        )
        XCTAssertEqual(resolved.path, root.path, "选中的是文件，就在它所在的文件夹打开")
    }

    func testNothingSelectedUsesTheMenuFolder() {
        let resolved = TerminalTarget.directory(
            selectedPaths: [],
            directoryPath: "/tmp"
        )
        XCTAssertEqual(resolved.path, "/tmp")
    }

    func testSeveralItemsUseTheFirstOne() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("img", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let resolved = TerminalTarget.directory(
            selectedPaths: [folder.path, root.path],
            directoryPath: root.path
        )
        XCTAssertEqual(resolved.path, folder.path)
    }
}
