import XCTest

final class AppPreferencesTests: XCTestCase {
    func testDecodesEmptyObjectUsingDefaults() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))

        XCTAssertEqual(preferences.scripts, [:])
        XCTAssertEqual(preferences.templates, [:])
        XCTAssertEqual(preferences.toolbox, [:])
        XCTAssertNil(preferences.compressorIdentifier)
        // A missing `version` is what marks a file written before migrations.
        XCTAssertNil(preferences.version)
    }

    func testDecodesPartialObjectAndKeepsKnownKeys() throws {
        let json = #"{"compressorIdentifier":"com.aone.keka"}"#
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(preferences.compressorIdentifier, "com.aone.keka")
        XCTAssertTrue(preferences.scripts.isEmpty)
        XCTAssertTrue(preferences.templates.isEmpty)
    }

    func testIgnoresUnknownKeysWrittenByNewerBuilds() throws {
        let json = #"{"futureSetting":true,"templates":{"builtin.txt":{"isEnabled":false}}}"#
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(preferences.templates["builtin.txt"], TemplatePreference(isEnabled: false))
    }

    func testRoundTripsTemplatePreferences() throws {
        var preferences = AppPreferences()
        preferences.templates["builtin.txt"] = TemplatePreference(isEnabled: false, order: 42)
        preferences.compressorIdentifier = "com.aone.keka"

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }
}

final class NewFileServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAppendsTemplateExtensionWhenNameHasNone() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.md" })

        XCTAssertEqual(
            NewFileService.resolvedFileName(for: "notes", template: template),
            "notes.md"
        )
    }

    func testKeepsExtensionTypedByTheUser() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })

        XCTAssertEqual(
            NewFileService.resolvedFileName(for: "notes.md", template: template),
            "notes.md"
        )
    }

    func testEmptyTextTemplateCreatesFileWithExtension() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })

        let url = try NewFileService.createFile(from: template, named: "notes", in: directory)

        XCTAssertEqual(url.lastPathComponent, "notes.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSecondFileWithSameNameGetsSuffix() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })

        _ = try NewFileService.createFile(from: template, named: "notes", in: directory)
        let second = try NewFileService.createFile(from: template, named: "notes", in: directory)

        XCTAssertEqual(second.lastPathComponent, "notes 2.txt")
    }

    func testRejectsNameContainingSlash() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })

        XCTAssertThrowsError(
            try NewFileService.createFile(from: template, named: "a/b", in: directory)
        )
    }

    func testRejectsMissingDirectory() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })
        let missing = directory.appendingPathComponent("gone", isDirectory: true)

        XCTAssertThrowsError(
            try NewFileService.createFile(from: template, named: "notes", in: missing)
        )
    }

    func testBundledTemplatesDeclareAResourceName() {
        let bundled = BuiltinTemplates.all.filter { $0.contentSource == .bundledResource }

        XCTAssertEqual(bundled.count, 3)
        for template in bundled {
            XCTAssertNotNil(template.contentPath, "\(template.id) has no resource name")
            XCTAssertFalse(template.contentPath!.isEmpty)
        }
    }

    /// New files are created without a dialog now, so the default name has to
    /// read naturally in the user's language, like Finder's "untitled folder".
    func testDefaultNameFollowsLanguage() {
        XCTAssertEqual(
            NewFileService.defaultBaseName(preferredLanguage: "zh-Hans-CN"),
            "新建文件"
        )
        XCTAssertEqual(
            NewFileService.defaultBaseName(preferredLanguage: "en-US"),
            "Untitled"
        )
        XCTAssertEqual(NewFileService.defaultBaseName(preferredLanguage: nil), "Untitled")
    }

    func testDefaultFileNameCarriesTemplateExtension() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.docx" })

        XCTAssertEqual(
            NewFileService.defaultFileName(for: template, preferredLanguage: "en-US"),
            "Untitled.docx"
        )
        XCTAssertEqual(
            NewFileService.defaultFileName(for: template, preferredLanguage: "zh-Hant"),
            "新建文件.docx"
        )
    }

    func testCreatedDefaultNameGetsNumberedOnCollision() throws {
        let template = try XCTUnwrap(BuiltinTemplates.all.first { $0.id == "builtin.txt" })
        let name = NewFileService.defaultFileName(for: template, preferredLanguage: "en-US")

        let first = try NewFileService.createFile(from: template, named: name, in: directory)
        let second = try NewFileService.createFile(from: template, named: name, in: directory)

        XCTAssertEqual(first.lastPathComponent, "Untitled.txt")
        XCTAssertEqual(second.lastPathComponent, "Untitled 2.txt")
    }
}

final class TemplateCatalogServiceTests: XCTestCase {
    func testBuiltInTemplatesAreOfferedByDefault() {
        let identifiers = TemplateCatalogService.allTemplates()
            .map(\.id)

        XCTAssertEqual(
            identifiers,
            ["builtin.txt", "builtin.md", "builtin.docx", "builtin.xlsx", "builtin.pptx"]
        )
    }

    func testDisabledTemplateIsHidden() {
        var preferences = AppPreferences()
        preferences.templates["builtin.pptx"] = TemplatePreference(isEnabled: false)

        let identifiers = TemplateCatalogService.allTemplates(preferences: preferences)
            .map(\.id)

        XCTAssertFalse(identifiers.contains("builtin.pptx"))
    }

    func testOrderPreferenceWins() {
        var preferences = AppPreferences()
        preferences.templates["builtin.pptx"] = TemplatePreference(order: 1)

        let templates = TemplateCatalogService.allTemplates(preferences: preferences)

        XCTAssertEqual(templates.first?.id, "builtin.pptx")
    }
}
