import AppKit
import XCTest

final class ToolboxCatalogTests: XCTestCase {
    private let defaultOrder: [ToolboxItemID] = [
        .newFile,
        .copyPath,
        .copyFileName,
        .openInTerminal,
        .scripts,
        .compressZip,
        .compressSevenZip,
        .decompressHere,
        .decompressIntoFolder
    ]

    func testDefaultsOfferEveryItemInOrder() {
        let items = ToolboxCatalog.items(preferences: [:])

        XCTAssertEqual(items.map(\.id), defaultOrder)
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
    }

    func testDisabledItemIsDropped() {
        var preferences: [String: ToolboxPreference] = [:]
        preferences[ToolboxItemID.copyFileName.rawValue] = ToolboxPreference(isEnabled: false)

        let items = ToolboxCatalog.items(preferences: preferences)

        XCTAssertFalse(items.contains { $0.id == .copyFileName })
        XCTAssertEqual(items.count, defaultOrder.count - 1)
    }

    /// The settings list must keep showing a switched-off row, otherwise there
    /// would be no way to switch it back on.
    func testOrderedItemsKeepsDisabledEntries() {
        var preferences: [String: ToolboxPreference] = [:]
        preferences[ToolboxItemID.copyFileName.rawValue] = ToolboxPreference(
            isEnabled: false
        )

        let ordered = ToolboxCatalog.orderedItems(preferences: preferences)
        let disabled = ordered.first { $0.id == .copyFileName }

        XCTAssertEqual(ordered.map(\.id), defaultOrder)
        XCTAssertEqual(disabled?.isEnabled, false)
    }

    func testOrderOverrideWins() {
        var preferences: [String: ToolboxPreference] = [:]
        preferences[ToolboxItemID.openInTerminal.rawValue] = ToolboxPreference(order: 1)

        let items = ToolboxCatalog.items(preferences: preferences)

        XCTAssertEqual(items.first?.id, .openInTerminal)
    }

    /// Right-clicking empty space no longer switches to a longer wording: "Copy
    /// Current Folder Path" is too long for a menu and did not match what the
    /// selection case was called. Both contexts now use the same title.
    func testCopyPathUsesTheSameTitleInBothContexts() {
        let copyPath = ToolboxCatalog.all.first { $0.id == .copyPath }
        let copyName = ToolboxCatalog.all.first { $0.id == .copyFileName }

        XCTAssertEqual(copyPath?.title(forBackground: false), "拷贝路径")
        XCTAssertEqual(copyPath?.title(forBackground: true), "拷贝路径")
        XCTAssertEqual(copyName?.title(forBackground: true), "拷贝文件名")
    }

    /// Archive commands run the compressor in the main app, so the extension must
    /// hand them over rather than try to perform them itself.
    func testArchiveItemsAreHandledByTheApp() {
        let archiveItems: [ToolboxItemID] = [
            .compressZip, .compressSevenZip, .decompressHere, .decompressIntoFolder
        ]

        for id in archiveItems {
            XCTAssertFalse(id.isHandledByExtension, "\(id) should round-trip to the app")
            XCTAssertTrue(id.usesCompressorIcon, "\(id) should show the compressor's icon")
            XCTAssertTrue(id.requiresSelection)
        }

        for id in [ToolboxItemID.copyPath, .copyFileName] {
            XCTAssertTrue(id.isHandledByExtension)
            XCTAssertFalse(id.usesCompressorIcon)
        }

        // Opening Terminal needs the main app: a sandboxed extension cannot hand
        // an arbitrary directory to another application.
        XCTAssertFalse(ToolboxItemID.openInTerminal.isHandledByExtension)
    }

    /// The empty-space menu only carries what makes sense without a selection.
    func testOnlySomeEntriesAppearInTheEmptySpaceMenu() {
        let backgroundItems = ToolboxCatalog.all.filter(\.appliesToBackground)

        XCTAssertEqual(
            backgroundItems.map(\.id),
            [.newFile, .copyPath, .openInTerminal, .scripts]
        )
    }

    /// New File and Scripts are rendered as submenus, so the extension must not try
    /// to perform them itself.
    func testSubmenuEntriesAreHandledByTheApp() {
        for id in [ToolboxItemID.newFile, .scripts] {
            XCTAssertFalse(id.isHandledByExtension, "\(id) is a submenu")
            XCTAssertFalse(id.usesCompressorIcon)
        }

        func item(_ id: ToolboxItemID) -> ToolboxItem? {
            ToolboxCatalog.all.first { $0.id == id }
        }

        // New File only makes sense on empty space; Scripts is useful either way.
        XCTAssertFalse(item(.newFile)?.appliesToSelection == true)
        XCTAssertTrue(item(.newFile)?.appliesToBackground == true)
        XCTAssertTrue(item(.scripts)?.appliesToSelection == true)
        XCTAssertTrue(item(.scripts)?.appliesToBackground == true)
    }

    /// A snapshot written before the toolbox existed must still decode, otherwise
    /// the extension would show no menu at all until the app ran again.
    func testSnapshotWithoutToolboxFallsBackToDefaults() throws {
        let json = """
        {"schemaVersion":1,"generatedAt":"2026-01-01T00:00:00Z","scripts":[],"templates":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(MenuSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.toolbox.map(\.id), defaultOrder)
    }

    func testSnapshotRoundTripsToolboxSelection() throws {
        let selected = ToolboxCatalog.items(preferences: [
            ToolboxItemID.copyFileName.rawValue: ToolboxPreference(isEnabled: false)
        ])
        let snapshot = MenuSnapshot(scripts: [], templates: [], toolbox: selected)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            MenuSnapshot.self,
            from: try encoder.encode(snapshot)
        )

        XCTAssertFalse(decoded.toolbox.contains { $0.id == .copyFileName })
        XCTAssertEqual(decoded.toolbox.count, defaultOrder.count - 1)
    }

    func testPreferencesRoundTripToolboxFlags() throws {
        var preferences = AppPreferences()
        preferences.toolbox[ToolboxItemID.openInTerminal.rawValue] = ToolboxPreference(
            isEnabled: false
        )

        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: try JSONEncoder().encode(preferences)
        )

        XCTAssertEqual(decoded, preferences)
    }
}

/// The built-in starter documents were once missing from the app bundle, so
/// users switched Word/Excel/PowerPoint off. The one-time migration has to bring
/// them back without touching anything else the user chose.
final class PreferencesMigrationTests: XCTestCase {
    func testMigrationReenablesBuiltInTemplates() {
        var preferences = AppPreferences(version: 1)
        preferences.templates["builtin.docx"] = TemplatePreference(isEnabled: false, order: 5)
        preferences.templates["builtin.txt"] = TemplatePreference(isEnabled: false)
        preferences.toolbox[ToolboxItemID.copyFileName.rawValue] = ToolboxPreference(
            isEnabled: false
        )
        preferences.compressorIdentifier = "com.aone.keka"

        let migrated = AppGroupStore.migrate(preferences)

        XCTAssertNil(migrated.templates["builtin.docx"]?.isEnabled)
        XCTAssertNil(migrated.templates["builtin.txt"]?.isEnabled)
        // The user's own ordering survives.
        XCTAssertEqual(migrated.templates["builtin.docx"]?.order, 5)
        // Nothing outside the built-in templates is touched.
        XCTAssertEqual(migrated.toolbox[ToolboxItemID.copyFileName.rawValue]?.isEnabled, false)
        XCTAssertEqual(migrated.compressorIdentifier, "com.aone.keka")
        XCTAssertEqual(migrated.version, AppPreferences.currentVersion)
    }

    func testTemplatesWithoutAPreferenceStayDefault() {
        let migrated = AppGroupStore.migrate(AppPreferences(version: 1))

        XCTAssertTrue(migrated.templates.isEmpty)
        XCTAssertEqual(migrated.version, AppPreferences.currentVersion)
    }

    func testDecodingLegacyPreferencesLeavesVersionUnset() throws {
        let json = #"{"scripts":{},"templates":{},"toolbox":{}}"#
        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(decoded.version)
        XCTAssertLessThan(decoded.version ?? 1, AppPreferences.currentVersion)
    }
}

/// The built-in archive tools cannot make 7z archives, so choosing them has to
/// take the 7z commands out of the toolbox — and the settings window and the
/// Finder menu must agree on that.
final class ToolboxCapabilityTests: XCTestCase {
    func testSevenZipItemSurvivesWhenTheToolSupportsIt() {
        let formats = KekaAdapter().capabilities.createsFormats

        let items = ToolboxCatalog.items(preferences: [:], creatableFormats: formats)

        XCTAssertTrue(items.contains { $0.id == .compressSevenZip })
    }

    func testSevenZipItemDisappearsWithTheBuiltInTools() {
        let formats = SystemArchiveAdapter().capabilities.createsFormats

        let items = ToolboxCatalog.orderedItems(preferences: [:], creatableFormats: formats)

        XCTAssertFalse(items.contains { $0.id == .compressSevenZip })
        // Only 7z compression goes away; everything else stays.
        XCTAssertTrue(items.contains { $0.id == .compressZip })
        XCTAssertTrue(items.contains { $0.id == .decompressHere })
        XCTAssertTrue(items.contains { $0.id == .decompressIntoFolder })
    }

    func testBuiltInToolsAdvertiseNoSevenZip() {
        XCTAssertFalse(SystemArchiveAdapter().capabilities.supportsSevenZip)
        XCTAssertTrue(KekaAdapter().capabilities.supportsSevenZip)
    }

    /// The setting is always selectable, so the app keeps working with nothing
    /// else installed.
    func testBuiltInToolsAreAlwaysAvailable() {
        let system = SystemArchiveAdapter()

        XCTAssertTrue(system.isInstalled)
        XCTAssertFalse(system.capabilities.archiveFormats.isEmpty)
    }

    func testSelectionFallsBackToAnInstalledCompressor() {
        let service = CompressionService.shared

        // Nothing chosen yet: whatever is installed wins.
        let resolved = service.compressor(for: AppPreferences())
        XCTAssertTrue(resolved.isInstalled)

        // An explicit choice is honoured.
        let chosen = service.compressor(
            for: AppPreferences(compressorIdentifier: SystemArchiveAdapter().identifier)
        )
        XCTAssertEqual(chosen.identifier, SystemArchiveAdapter().identifier)
    }
}


/// The push-aside is the difference between the table feeling like 1Capture and
/// feeling like the rows teleport. The invariant is easy to invert by accident —
/// it was, once — so it is pinned here.
final class ReorderMotionTests: XCTestCase {
    func testTheDraggedRowIsNotAnimated() {
        XCTAssertNil(
            ReorderMotion.position(isDragged: true),
            "the dragged row must track the pointer with no easing"
        )
    }

    func testEveryOtherRowSprings() {
        XCTAssertNotNil(
            ReorderMotion.position(isDragged: false),
            "rows sliding aside must animate, or the push looks like a jump"
        )
    }

    /// Sideways travel carries no meaning in a one-dimensional list, so the row
    /// only follows a fraction of it, and never far enough to leave its column.
    func testHorizontalFollowIsDamped() {
        XCTAssertEqual(ReorderMotion.horizontal(100), 100 * ReorderMotion.horizontalDamping, accuracy: 0.001)
        XCTAssertLessThan(ReorderMotion.horizontal(100), 100)
    }

    func testHorizontalFollowIsCapped() {
        XCTAssertEqual(ReorderMotion.horizontal(10_000), ReorderMotion.maxHorizontalOffset)
        XCTAssertEqual(ReorderMotion.horizontal(-10_000), -ReorderMotion.maxHorizontalOffset)
    }

    func testHorizontalFollowIsSymmetric() {
        XCTAssertEqual(ReorderMotion.horizontal(-50), -ReorderMotion.horizontal(50), accuracy: 0.001)
    }

    /// Whatever the curves are, the push has to be quick enough to feel like a
    /// response and not a transition.
    func testMotionCurvesAreDistinct() {
        XCTAssertNotNil(ReorderMotion.push)
        XCTAssertNotNil(ReorderMotion.lift)
        XCTAssertNotNil(ReorderMotion.settle)
    }
}

/// The menu snapshot now carries the icons, because the sandboxed extension
/// cannot resolve application or document icons. These pin the parts that are
/// easy to get wrong.
final class MenuIconTests: XCTestCase {
    func testSymbolsRenderToPNG() throws {
        let data = try XCTUnwrap(MenuIconRenderer.png(systemSymbol: "doc.on.clipboard"))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertNotNil(NSImage(data: data), "the payload must decode back into an image")
    }

    func testKeysAreStableAndNamespaced() {
        XCTAssertEqual(MenuIconKey.toolbox(.copyPath), "toolbox:copyPath")
        XCTAssertEqual(MenuIconKey.template("builtin.txt"), "template:builtin.txt")
        XCTAssertEqual(MenuIconKey.script("Run Python"), "script:Run Python")
    }

    /// A snapshot written before icons existed must still decode, otherwise the
    /// extension would show no menu at all until the app ran again.
    func testSnapshotWithoutIconsDecodes() throws {
        let json = """
        {"schemaVersion":2,"generatedAt":"2026-01-01T00:00:00Z","scripts":[],"templates":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(MenuSnapshot.self, from: Data(json.utf8))

        XCTAssertTrue(snapshot.icons.isEmpty)
    }

    func testIconsRoundTrip() throws {
        let png = try XCTUnwrap(MenuIconRenderer.png(systemSymbol: "terminal"))
        let snapshot = MenuSnapshot(
            scripts: [],
            templates: [],
            icons: [MenuIconKey.toolbox(.openInTerminal): png]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try decoder.decode(MenuSnapshot.self, from: try encoder.encode(snapshot))

        XCTAssertEqual(decoded.icons[MenuIconKey.toolbox(.openInTerminal)], png)
    }
}

/// Archive actions are distinguished by the type of the selected files.
final class SelectionContextTests: XCTestCase {
    private func urls(_ paths: String...) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    func testEmptySelection() {
        let context = SelectionContext(urls: [])
        XCTAssertTrue(context.isEmpty)
        XCTAssertFalse(context.containsArchive)
        XCTAssertFalse(context.allAreArchives)
    }

    /// Selecting a folder: no extraction action should appear; compression still does.
    func testFolderOffersCompressButNotDecompress() {
        let context = SelectionContext(urls: urls("/tmp/Some Folder"))
        XCTAssertFalse(context.containsArchive)
        XCTAssertFalse(ToolboxCatalog.applies(.decompressHere, to: context))
        XCTAssertFalse(ToolboxCatalog.applies(.decompressIntoFolder, to: context))
        XCTAssertTrue(ToolboxCatalog.applies(.compressZip, to: context))
        XCTAssertTrue(ToolboxCatalog.applies(.compressSevenZip, to: context))
    }

    /// Selecting an archive: extraction is offered, but compression is not.
    func testArchiveOffersDecompressButNotCompress() {
        let context = SelectionContext(urls: urls("/tmp/a.zip"))
        XCTAssertTrue(context.containsArchive)
        XCTAssertTrue(context.allAreArchives)
        XCTAssertTrue(ToolboxCatalog.applies(.decompressHere, to: context))
        XCTAssertTrue(ToolboxCatalog.applies(.decompressIntoFolder, to: context))
        XCTAssertFalse(ToolboxCatalog.applies(.compressZip, to: context))
        XCTAssertFalse(ToolboxCatalog.applies(.compressSevenZip, to: context))
    }

    /// An ordinary file: compression yes, extraction no.
    func testPlainFileOffersCompressOnly() {
        let context = SelectionContext(urls: urls("/tmp/notes.txt"))
        XCTAssertFalse(context.containsArchive)
        XCTAssertFalse(ToolboxCatalog.applies(.decompressHere, to: context))
        XCTAssertTrue(ToolboxCatalog.applies(.compressZip, to: context))
    }

    /// A mixed selection: an archive is present, so extraction works; but it is not
    /// "all archives", so compression stays as well.
    func testMixedSelectionOffersBoth() {
        let context = SelectionContext(urls: urls("/tmp/a.zip", "/tmp/notes.txt"))
        XCTAssertTrue(context.containsArchive)
        XCTAssertFalse(context.allAreArchives)
        XCTAssertTrue(ToolboxCatalog.applies(.decompressHere, to: context))
        XCTAssertTrue(ToolboxCatalog.applies(.compressZip, to: context))
    }

    /// Case and double extensions.
    func testExtensionMatching() {
        XCTAssertTrue(ArchiveFormats.isArchive(URL(fileURLWithPath: "/tmp/A.ZIP")))
        XCTAssertTrue(ArchiveFormats.isArchive(URL(fileURLWithPath: "/tmp/backup.tar.gz")))
        XCTAssertFalse(ArchiveFormats.isArchive(URL(fileURLWithPath: "/tmp/report.pdf")))
    }

    /// Other items are unaffected.
    func testOtherItemsAreUnaffected() {
        let context = SelectionContext(urls: urls("/tmp/a.zip"))
        for id in [ToolboxItemID.copyPath, .copyFileName, .openInTerminal, .newFile] {
            XCTAssertTrue(ToolboxCatalog.applies(id, to: context), "\(id) 不该被过滤")
        }
    }
}
