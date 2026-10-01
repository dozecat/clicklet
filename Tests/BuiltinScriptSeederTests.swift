import XCTest

/// The seeder is the only thing that writes into the user's scripts directory,
/// so its two rules matter: never overwrite what the user has, and never bring
/// back what the user deleted — while still offering packages added later.
final class BuiltinScriptSeederTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var scripts: URL!
    private var record: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("BuiltinScripts", isDirectory: true)
        scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        record = root.appendingPathComponent("seeded-scripts.json")

        try makePackage(named: "Open in VS Code")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makePackage(named name: String, body: String = "#!/bin/zsh\nexit 0\n") throws {
        let package = source.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: package.appendingPathComponent("script.sh"))
        try Data(#"{"name":"\#(name)"}"#.utf8)
            .write(to: package.appendingPathComponent("config.json"))
    }

    private func seed() -> [String] {
        BuiltinScriptSeeder.seed(from: source, into: scripts, recordURL: record)
    }

    func testSeedsMissingPackage() {
        let seeded = seed()

        XCTAssertEqual(seeded, ["Open in VS Code"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scripts.appendingPathComponent("Open in VS Code/config.json").path
            )
        )
    }

    /// The bundle keeps the bit, but a copy through a zip or a git checkout may
    /// not, and a script without it is simply ignored by the scanner.
    func testSeededScriptIsExecutable() {
        _ = seed()

        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: scripts.appendingPathComponent("Open in VS Code/script.sh").path
            )
        )
    }

    func testDoesNotOverwriteWhatTheUserChanged() throws {
        let destination = scripts.appendingPathComponent("Open in VS Code", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let edited = destination.appendingPathComponent("script.sh")
        try Data("#!/bin/zsh\n# my own version\n".utf8).write(to: edited)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: edited.path
        )

        _ = seed()

        let contents = try String(contentsOf: edited, encoding: .utf8)
        XCTAssertTrue(contents.contains("my own version"))
    }

    /// Deleting a built-in script is a decision; a later launch must respect it.
    func testDeletedPackageIsNotRestored() throws {
        _ = seed()
        let destination = scripts.appendingPathComponent("Open in VS Code", isDirectory: true)
        try FileManager.default.removeItem(at: destination)

        let secondRun = seed()

        XCTAssertTrue(secondRun.contains("Open in VS Code"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    /// A package shipped by a later version has not been offered yet, so it is.
    func testPackageAddedLaterIsStillOffered() throws {
        _ = seed()
        try makePackage(named: "Resize Images")

        let seeded = seed()

        XCTAssertEqual(seeded, ["Open in VS Code", "Resize Images"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scripts.appendingPathComponent("Resize Images/script.sh").path
            )
        )
    }

    func testSeedingTwiceIsIdempotent() {
        let first = seed()
        let second = seed()

        XCTAssertEqual(first, second)
    }

    func testMissingSourceIsHarmless() {
        let seeded = BuiltinScriptSeeder.seed(
            from: root.appendingPathComponent("Nope", isDirectory: true),
            into: scripts,
            recordURL: record
        )

        XCTAssertTrue(seeded.isEmpty)
    }
}
