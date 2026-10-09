import Foundation

/// The basic right-click actions the toolbox offers, independently of scripts
/// and file templates.
enum ToolboxItemID: String, Codable, CaseIterable {
    case newFile
    case copyPath
    case copyFileName
    case openInTerminal
    case scripts
    case compressZip
    case compressSevenZip
    case decompressHere
    case decompressIntoFolder
}

extension ToolboxItemID {
    /// Performed by the extension itself. The rest round-trip to the main app,
    /// which is the only place allowed to run the archive tool.
    var isHandledByExtension: Bool {
        switch self {
        case .copyPath, .copyFileName:
            return true
        case .newFile, .scripts, .openInTerminal, .compressZip, .compressSevenZip,
             .decompressHere, .decompressIntoFolder:
            return false
        }
    }

    /// Archive work: the settings window shows the chosen compressor's own icon.
    var usesCompressorIcon: Bool {
        switch self {
        case .compressZip, .compressSevenZip,
             .decompressHere, .decompressIntoFolder:
            return true
        case .newFile, .scripts, .copyPath, .copyFileName, .openInTerminal:
            return false
        }
    }

    /// Only offered when something is selected.
    var requiresSelection: Bool {
        switch self {
        case .copyPath, .openInTerminal:
            return false
        default:
            return true
        }
    }
}

/// One entry of the Finder menu's toolbox section.
///
/// The extension renders these from the menu snapshot and performs them locally:
/// writing to the pasteboard and asking LaunchServices for a terminal both work
/// inside the sandbox, so they need no main-app round trip.
struct ToolboxItem: Codable, Equatable, Identifiable {
    let id: ToolboxItemID
    let title: String
    /// Title used when right-clicking empty space, when it should read differently.
    let backgroundTitle: String?
    let icon: String
    let appliesToSelection: Bool
    let appliesToBackground: Bool
    let order: Int
    let isEnabled: Bool

    func title(forBackground isBackground: Bool) -> String {
        isBackground ? (backgroundTitle ?? title) : title
    }

    func replacingOrder(_ order: Int) -> ToolboxItem {
        ToolboxItem(
            id: id,
            title: title,
            backgroundTitle: backgroundTitle,
            icon: icon,
            appliesToSelection: appliesToSelection,
            appliesToBackground: appliesToBackground,
            order: order,
            isEnabled: isEnabled
        )
    }

    func replacingEnabled(_ isEnabled: Bool) -> ToolboxItem {
        ToolboxItem(
            id: id,
            title: title,
            backgroundTitle: backgroundTitle,
            icon: icon,
            appliesToSelection: appliesToSelection,
            appliesToBackground: appliesToBackground,
            order: order,
            isEnabled: isEnabled
        )
    }
}

/// The type of what is selected, which decides which archive actions should appear
/// in the menu.
///
/// It used to distinguish only "selection / empty space", so selecting a folder
/// still showed "Extract Here" and selecting a zip still showed "Compress to ZIP" —
/// neither of which makes sense.
struct SelectionContext {
    var isEmpty: Bool
    var containsArchive: Bool
    /// Non-empty, and every item is an archive.
    var allAreArchives: Bool

    init(urls: [URL]) {
        isEmpty = urls.isEmpty
        let flags = urls.map(ArchiveFormats.isArchive)
        containsArchive = flags.contains(true)
        allAreArchives = !urls.isEmpty && flags.allSatisfy { $0 }
    }
}

enum ArchiveFormats {
    /// Decides "is this an archive".
    ///
    /// Deliberately does not follow the compressor the user picked: whether a .rar
    /// is an archive has nothing to do with which tool Clicklet uses to handle it.
    static let extensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz",
        "xz", "txz", "lz", "lzma", "zst", "lz4", "br", "cab"
    ]

    static func isArchive(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

enum ToolboxCatalog {
    /// Application the "open in terminal" item launches.
    static let terminalBundleIdentifier = "com.apple.Terminal"

    /// Every item the toolbox can offer, with the state used before the user has
    /// expressed a preference.
    static let all: [ToolboxItem] = [
        ToolboxItem(
            id: .newFile,
            title: "新建文件",
            backgroundTitle: nil,
            icon: "doc.badge.plus",
            appliesToSelection: false,
            appliesToBackground: true,
            order: 10,
            isEnabled: true
        ),
        ToolboxItem(
            id: .copyPath,
            title: "拷贝路径",
            // Right-clicking empty space uses the same title too. It used to be
            // called "Copy Current Folder Path", which is too long for a menu and
            // did not match what the selection case was called.
            backgroundTitle: nil,
            icon: "doc.on.clipboard",
            appliesToSelection: true,
            appliesToBackground: true,
            order: 20,
            isEnabled: true
        ),
        ToolboxItem(
            id: .copyFileName,
            title: "拷贝文件名",
            backgroundTitle: nil,
            icon: "doc.text",
            appliesToSelection: true,
            appliesToBackground: false,
            order: 30,
            isEnabled: true
        ),
        ToolboxItem(
            id: .openInTerminal,
            // The former title read as "open the selected item with Terminal".
            // The action opens a terminal *at* the folder, so say that.
            title: "在此处打开终端",
            backgroundTitle: nil,
            icon: "terminal",
            appliesToSelection: true,
            appliesToBackground: true,
            order: 40,
            isEnabled: true
        ),
        ToolboxItem(
            id: .scripts,
            title: "脚本",
            backgroundTitle: nil,
            icon: "chevron.left.forwardslash.chevron.right",
            appliesToSelection: true,
            appliesToBackground: true,
            order: 45,
            isEnabled: true
        ),
        ToolboxItem(
            id: .compressZip,
            title: "压缩为 ZIP",
            backgroundTitle: nil,
            icon: "doc.zipper",
            appliesToSelection: true,
            appliesToBackground: false,
            order: 50,
            isEnabled: true
        ),
        ToolboxItem(
            id: .compressSevenZip,
            title: "压缩为 7Z",
            backgroundTitle: nil,
            icon: "doc.zipper",
            appliesToSelection: true,
            appliesToBackground: false,
            order: 60,
            isEnabled: true
        ),
        ToolboxItem(
            id: .decompressHere,
            title: "解压到当前文件夹",
            backgroundTitle: nil,
            icon: "arrow.down.doc",
            appliesToSelection: true,
            appliesToBackground: false,
            order: 70,
            isEnabled: true
        ),
        ToolboxItem(
            id: .decompressIntoFolder,
            title: "解压到独立文件夹",
            backgroundTitle: nil,
            icon: "folder.badge.plus",
            appliesToSelection: true,
            appliesToBackground: false,
            order: 80,
            isEnabled: true
        )
    ]

    /// Used when no snapshot has been written yet, so a fresh install still gets
    /// the basic actions.
    static var defaultItems: [ToolboxItem] {
        all
    }

    /// Everything the settings list shows, in menu order, including entries the
    /// user has switched off — otherwise a disabled row could never be turned
    /// back on.
    static func orderedItems(
        preferences: [String: ToolboxPreference],
        creatableFormats: Set<String> = ["zip", "7z"]
    ) -> [ToolboxItem] {
        all
            .filter { supports($0.id, creatableFormats: creatableFormats) }
            .map { item in
                let preference = preferences[item.id.rawValue]
                return item.replacingOrder(preference?.order ?? item.order)
                    .replacingEnabled(preference?.isEnabled ?? item.isEnabled)
            }
            .sorted(by: precede)
    }

    /// What the extension should render: enabled entries only, in menu order.
    static func items(
        preferences: [String: ToolboxPreference],
        creatableFormats: Set<String> = ["zip", "7z"]
    ) -> [ToolboxItem] {
        orderedItems(
            preferences: preferences,
            creatableFormats: creatableFormats
        )
        .filter(\.isEnabled)
    }

    /// 7z compression is only offered while the chosen archive tool can produce
    /// 7z archives at all; the built-in tools cannot.
    /// Whether this item should appear for the given selection state.
    ///
    /// Used for **menu building** only. The toolbox list in the settings window has
    /// to list every item, otherwise the user cannot see it at all and therefore
    /// cannot turn the "Extract" item on — so that path does not go through here.
    static func applies(_ id: ToolboxItemID, to selection: SelectionContext) -> Bool {
        switch id {
        case .compressZip, .compressSevenZip:
            // It is already an archive, so compressing it again is pointless.
            return !selection.allAreArchives
        case .decompressHere, .decompressIntoFolder:
            // The selection needs at least one archive, otherwise there is nothing
            // to extract.
            return selection.containsArchive
        default:
            return true
        }
    }

    private static func supports(
        _ id: ToolboxItemID,
        creatableFormats: Set<String>
    ) -> Bool {
        switch id {
        case .compressSevenZip:
            return creatableFormats.contains("7z")
        default:
            return true
        }
    }

    private static func precede(_ lhs: ToolboxItem, _ rhs: ToolboxItem) -> Bool {
        if lhs.order == rhs.order {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.order < rhs.order
    }
}
