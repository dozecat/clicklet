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
        let expected: Set<String> = [
            "builtin.docx", "builtin.xlsx", "builtin.pptx",   // ship with the app
            "builtin.pages", "builtin.numbers", "builtin.key" // dropped in by hand
        ]

        XCTAssertEqual(Set(bundled.map(\.id)), expected)
        for template in bundled {
            XCTAssertNotNil(template.contentPath, "\(template.id) has no resource name")
            XCTAssertFalse(template.contentPath!.isEmpty)
        }
    }

    /// Most templates start switched on; only the niche developer formats start off,
    /// so that the New File submenu stays short on a fresh install.
    func testTemplateDefaultEnablement() {
        let offByDefault: Set<String> = [
            "builtin.css", "builtin.js", "builtin.py", "builtin.sh",
            "builtin.yml", "builtin.csv", "builtin.rtf"
        ]

        for template in BuiltinTemplates.all {
            let expected = !offByDefault.contains(template.id)
            XCTAssertEqual(
                template.defaultEnabled ?? true, expected,
                "\(template.id) default enablement"
            )
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
            [
                // On by default: the everyday documents, the two most common code
                // formats, and the three iWork types. The rest of the developer
                // formats start switched off so the submenu stays short.
                "builtin.txt", "builtin.md", "builtin.docx", "builtin.xlsx",
                "builtin.pptx", "builtin.pages", "builtin.numbers", "builtin.key",
                "builtin.json", "builtin.html"
            ]
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

/// **Every field in the preferences must survive a round trip.**
///
/// AppPreferences uses a hand-written field-by-field decoder (so that files from an
/// older or newer build never fail to load as a whole), so a new field has to be
/// added in three places: the property, CodingKeys, and that decoder. Miss the
/// third and the value that was stored is gone when it is read back, so the UI
/// looks like "the setting changed itself back".
final class AppPreferencesRoundTripTests: XCTestCase {
    func testLanguageSurvivesARoundTrip() throws {
        let original = AppPreferences(language: .english)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(decoded.language, .english)
        XCTAssertEqual(decoded.resolvedLanguage, .english)
    }

    /// An old file has no language key, so it must load normally and pick a concrete
    /// language from the system.
    func testMissingLanguageDecodesToAConcreteLanguage() throws {
        let legacy = Data(#"{"version":2,"scripts":{},"templates":{},"toolbox":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        XCTAssertNil(decoded.language)
        XCTAssertEqual(decoded.resolvedLanguage, AppLanguage.defaultFromSystem)
    }

    /// An old file may hold a system value that has since been removed.
    /// Strict decoding would throw, and a caller that fails falls back to the
    /// defaults as a whole, losing the other settings along with it.
    func testUnknownLanguageValueDoesNotBreakLoading() throws {
        let legacy = Data(#"{"version":2,"scripts":{},"templates":{},"toolbox":{},"language":"system"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        XCTAssertNil(decoded.language)
        XCTAssertEqual(decoded.resolvedLanguage, AppLanguage.defaultFromSystem)
    }

    /// The other fields must not be lost in a round trip either.
    func testEveryFieldSurvivesARoundTrip() throws {
        let original = AppPreferences(
            scripts: ["a": ScriptPreference(isEnabled: true, order: 1)],
            templates: ["b": TemplatePreference(isEnabled: false, order: 2)],
            toolbox: ["copyPath": ToolboxPreference(isEnabled: true, order: 3)],
            compressorIdentifier: "keka",
            language: .simplifiedChinese
        )
        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }
}
