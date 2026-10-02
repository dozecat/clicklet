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

/// 偏好里**每个字段都必须能往返**。
///
/// AppPreferences 用的是手写的逐字段解码（为了老/新版本的文件都不会整体加载失败），
/// 所以新增字段要改三个地方：属性、CodingKeys、以及那个解码器。漏掉第三个时，
/// 存进去的值读回来就没了，界面看起来像"设置完又自己变回去"。
final class AppPreferencesRoundTripTests: XCTestCase {
    func testLanguageSurvivesARoundTrip() throws {
        let original = AppPreferences(language: .english)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(decoded.language, .english)
        XCTAssertEqual(decoded.resolvedLanguage, .english)
    }

    /// 老文件没有 language 这个键，必须能正常加载，并且退化成跟随系统。
    func testMissingLanguageDecodesAsFollowSystem() throws {
        let legacy = Data(#"{"version":2,"scripts":{},"templates":{},"toolbox":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        XCTAssertNil(decoded.language)
        XCTAssertEqual(decoded.resolvedLanguage, .system)
    }

    /// 其它字段也不能在往返中丢失。
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
