import XCTest

final class ScriptConfigTests: XCTestCase {
    func testDecodesNameAndMultiple() throws {
        let json = #"{"name":"Demo","multiple":true}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(ScriptConfig.self, from: json)

        XCTAssertEqual(config.name, "Demo")
        XCTAssertEqual(config.multiple, true)
    }

    func testUniqueURLUsesDirectory() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("untitled.txt").path,
            contents: Data()
        )

        let url = NewFileService.uniqueURL(for: "untitled.txt", in: directory)

        XCTAssertEqual(url.lastPathComponent, "untitled 2.txt")
    }

    func testFinderActionURLRoundTrip() throws {
        let requestID = UUID()
        let url = try XCTUnwrap(FinderActionURL.make(for: requestID))

        XCTAssertEqual(FinderActionURL.requestID(from: url), requestID)
    }

    func testScannerNormalizesScriptPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let package = root.appendingPathComponent("Convert WebP", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = package.appendingPathComponent("script.sh")
        try Data("#!/bin/zsh\nexit 0\n".utf8).write(to: script)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )

        let config = """
        {
          "name": "Convert to WebP",
          "context": "files",
          "multiple": true,
          "extensions": [".PNG", "jpg"],
          "order": 42
        }
        """
        try Data(config.utf8).write(to: package.appendingPathComponent("config.json"))

        let scripts = try ScriptScanner.scan(
            at: root,
            preferences: AppPreferences()
        )

        let scanned = try XCTUnwrap(scripts.first)
        XCTAssertEqual(scanned.name, "Convert to WebP")
        XCTAssertEqual(scanned.context, .files)
        XCTAssertTrue(scanned.allowsMultipleSelection)
        XCTAssertEqual(scanned.extensions, ["png", "jpg"])
        XCTAssertEqual(scanned.order, 42)
    }
}
