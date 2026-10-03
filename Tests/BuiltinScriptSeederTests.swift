import XCTest

/// A factory reset should bring back a bundled script the user deleted, without
/// touching anything else in the scripts folder.
final class BuiltinScriptSeederTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    /// Builds a source folder shaped like BuiltinScripts/.
    private func makeSource() throws -> URL {
        let source = root.appendingPathComponent("BuiltinScripts", isDirectory: true)
        let package = source.appendingPathComponent("Example", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("{\"name\":\"Example\"}".utf8).write(to: package.appendingPathComponent("config.json"))
        try Data("echo hi\n".utf8).write(to: package.appendingPathComponent("script.sh"))
        return source
    }

    func testSeedsAPackageThatIsNotThere() throws {
        let source = try makeSource()
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        let record = root.appendingPathComponent("record.json")

        let added = BuiltinScriptSeeder.seed(
            from: source, into: scripts, recordURL: record, fileManager: fm
        )

        XCTAssertEqual(added, ["Example"])
        XCTAssertTrue(fm.fileExists(atPath: scripts.appendingPathComponent("Example/script.sh").path))
    }

    func testDoesNotResurrectADeletedPackageWhileTheRecordStands() throws {
        let source = try makeSource()
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        let record = root.appendingPathComponent("record.json")

        _ = BuiltinScriptSeeder.seed(from: source, into: scripts, recordURL: record, fileManager: fm)
        try fm.removeItem(at: scripts.appendingPathComponent("Example", isDirectory: true))

        let added = BuiltinScriptSeeder.seed(
            from: source, into: scripts, recordURL: record, fileManager: fm
        )

        XCTAssertEqual(added, [], "记录还在时不该复活")
        XCTAssertFalse(fm.fileExists(atPath: scripts.appendingPathComponent("Example").path))
    }

    func testDroppingTheRecordBringsTheDeletedPackageBack() throws {
        let source = try makeSource()
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        let record = root.appendingPathComponent("record.json")

        _ = BuiltinScriptSeeder.seed(from: source, into: scripts, recordURL: record, fileManager: fm)
        try fm.removeItem(at: scripts.appendingPathComponent("Example", isDirectory: true))

        // 恢复出厂设置做的事：丢掉记录，再发放一次
        try fm.removeItem(at: record)
        let added = BuiltinScriptSeeder.seed(
            from: source, into: scripts, recordURL: record, fileManager: fm
        )

        XCTAssertEqual(added, ["Example"], "丢掉记录后应该重新发放")
        XCTAssertTrue(fm.fileExists(atPath: scripts.appendingPathComponent("Example/script.sh").path))
    }

    func testLeavesAUserMadePackageAlone() throws {
        let source = try makeSource()
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        let record = root.appendingPathComponent("record.json")

        // 用户自己建了一个同名但内容不同的包
        let mine = scripts.appendingPathComponent("Example", isDirectory: true)
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try Data("mine\n".utf8).write(to: mine.appendingPathComponent("script.sh"))

        let added = BuiltinScriptSeeder.seed(
            from: source, into: scripts, recordURL: record, fileManager: fm
        )

        XCTAssertEqual(added, [], "同名但不是内置的包不该被动")
        let body = try String(contentsOf: mine.appendingPathComponent("script.sh"), encoding: .utf8)
        XCTAssertEqual(body, "mine\n", "内容必须原样保留")
    }
}
