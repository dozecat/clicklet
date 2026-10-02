import XCTest

/// The seeder is the only thing that writes into the user's scripts directory,
/// so its three rules matter: never overwrite the user's edits, never resurrect
/// what they deleted, and still deliver updates to packages they left alone.
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

        try makePackage(named: "Open in VS Code", body: "#!/bin/zsh\nexit 0\n")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makePackage(named name: String, body: String) throws {
        let package = source.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: package.appendingPathComponent("script.sh"))
        try Data(#"{"name":"\#(name)"}"#.utf8)
            .write(to: package.appendingPathComponent("config.json"))
    }

    private func rewriteBundled(named name: String, body: String) throws {
        let package = source.appendingPathComponent(name, isDirectory: true)
        try Data(body.utf8).write(to: package.appendingPathComponent("script.sh"))
    }

    private func installedScript(named name: String) throws -> String {
        try String(
            contentsOf: scripts
                .appendingPathComponent(name)
                .appendingPathComponent("script.sh"),
            encoding: .utf8
        )
    }

    private func seed() -> [String] {
        BuiltinScriptSeeder.seed(from: source, into: scripts, recordURL: record)
    }

    // MARK: - Seeding

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

    func testSeedingAgainChangesNothing() throws {
        _ = seed()
        let first = try installedScript(named: "Open in VS Code")

        let second = seed()

        XCTAssertTrue(second.isEmpty, "already up to date, nothing to touch")
        XCTAssertEqual(try installedScript(named: "Open in VS Code"), first)
    }

    /// A package the user made by hand under a name we also ship stays theirs.
    func testPreexistingPackageIsLeftAlone() throws {
        let destination = scripts.appendingPathComponent("Open in VS Code", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let edited = destination.appendingPathComponent("script.sh")
        try Data("#!/bin/zsh\n# my own version\n".utf8).write(to: edited)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: edited.path)

        _ = seed()

        XCTAssertTrue(try installedScript(named: "Open in VS Code").contains("my own version"))
    }

    // MARK: - Updates

    /// The whole point of fingerprinting: a shipped fix reaches a user who never
    /// touched the package.
    func testDeliversAnUpdateWhenTheCopyIsUntouched() throws {
        _ = seed()
        try rewriteBundled(named: "Open in VS Code", body: "#!/bin/zsh\n# v2\n")

        let seeded = seed()

        XCTAssertEqual(seeded, ["Open in VS Code"])
        XCTAssertTrue(try installedScript(named: "Open in VS Code").contains("v2"))
    }

    func testDoesNotDeliverAnUpdateAfterTheUserEditedTheCopy() throws {
        _ = seed()
        let installed = scripts
            .appendingPathComponent("Open in VS Code/script.sh")
        try Data("#!/bin/zsh\n# mine now\n".utf8).write(to: installed)
        try rewriteBundled(named: "Open in VS Code", body: "#!/bin/zsh\n# v2\n")

        let seeded = seed()

        XCTAssertTrue(seeded.isEmpty)
        XCTAssertTrue(try installedScript(named: "Open in VS Code").contains("mine now"))
    }

    /// Deleting a built-in script is a decision; a later launch must respect it.
    func testDeletedPackageIsNotRestored() throws {
        _ = seed()
        let destination = scripts.appendingPathComponent("Open in VS Code", isDirectory: true)
        try FileManager.default.removeItem(at: destination)
        try rewriteBundled(named: "Open in VS Code", body: "#!/bin/zsh\n# v2\n")

        _ = seed()

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    /// A package shipped by a later version has not been offered yet, so it is.
    func testPackageAddedLaterIsStillOffered() throws {
        _ = seed()
        try makePackage(named: "Resize Images", body: "#!/bin/zsh\nexit 0\n")

        let seeded = seed()

        XCTAssertEqual(seeded, ["Resize Images"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scripts.appendingPathComponent("Resize Images/script.sh").path
            )
        )
    }

    /// Records written before fingerprints existed held a bare name list. Those
    /// copies are ours, so they get upgraded once and then carry a fingerprint.
    func testUpgradesALegacyRecordOnce() throws {
        _ = seed()
        try rewriteBundled(named: "Open in VS Code", body: "#!/bin/zsh\n# v2\n")
        try Data(#"{"seeded":["Open in VS Code"]}"#.utf8).write(to: record)

        let seeded = seed()

        XCTAssertEqual(seeded, ["Open in VS Code"])
        XCTAssertTrue(try installedScript(named: "Open in VS Code").contains("v2"))

        let saved = try String(contentsOf: record, encoding: .utf8)
        XCTAssertFalse(
            saved.contains(#""Open in VS Code":"""#),
            "the record should now hold a real fingerprint"
        )
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
