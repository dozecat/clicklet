import Foundation

struct ScriptConfig: Codable, Equatable {
    var name: String?
    var icon: String?
    var context: ScriptContext?
    var multiple: Bool?
    var extensions: [String]?
    var confirm: Bool?
    var order: Int?
    /// Bundle identifier of an app whose icon stands in for this script. Lets a
    /// bundled script show its tool's real artwork without redistributing an
    /// icon that belongs to someone else.
    var applicationBundleIdentifier: String?

    init(
        name: String? = nil,
        icon: String? = nil,
        context: ScriptContext? = nil,
        multiple: Bool? = nil,
        extensions: [String]? = nil,
        confirm: Bool? = nil,
        order: Int? = nil,
        applicationBundleIdentifier: String? = nil
    ) {
        self.name = name
        self.icon = icon
        self.context = context
        self.multiple = multiple
        self.extensions = extensions
        self.confirm = confirm
        self.order = order
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }
}

enum ScriptContext: String, Codable, CaseIterable {
    case selection
    case files
    case folders
    case background
    case all
}

struct ScriptPackage: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let relativeDirectory: String
    let entrypoint: String
    let iconPath: String?
    let context: ScriptContext
    let allowsMultipleSelection: Bool
    let extensions: [String]
    let requiresConfirmation: Bool
    let order: Int
    let isEnabled: Bool
    /// See `ScriptConfig.applicationBundleIdentifier`.
    let applicationBundleIdentifier: String?
}

struct ScriptPreference: Codable, Equatable {
    var isEnabled: Bool?
    var order: Int?
}

struct TemplatePreference: Codable, Equatable {
    var isEnabled: Bool?
    var order: Int?
}

struct ToolboxPreference: Codable, Equatable {
    var isEnabled: Bool?
    var order: Int?
}

enum TemplateContentSource: String, Codable {
    case emptyText
    case bundledResource
    case userFile
}

struct FileTemplate: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let fileExtension: String
    let icon: String?
    let contentSource: TemplateContentSource
    let contentPath: String?
    let order: Int
}

extension FileTemplate {
    /// Templates live either in the app bundle or in the App Group `Templates/`
    /// folder; the latter are the ones the user can remove.
    var isUserTemplate: Bool {
        contentSource == .userFile
    }

    func applying(_ preference: TemplatePreference?) -> FileTemplate {
        guard let preference else {
            return self
        }

        return FileTemplate(
            id: id,
            name: name,
            fileExtension: fileExtension,
            icon: icon,
            contentSource: contentSource,
            contentPath: contentPath,
            order: preference.order ?? order
        )
    }
}

extension ScriptPackage {
    func applying(_ preference: ScriptPreference?) -> ScriptPackage {
        guard let preference else {
            return self
        }

        return ScriptPackage(
            id: id,
            name: name,
            relativeDirectory: relativeDirectory,
            entrypoint: entrypoint,
            iconPath: iconPath,
            context: context,
            allowsMultipleSelection: allowsMultipleSelection,
            extensions: extensions,
            requiresConfirmation: requiresConfirmation,
            order: preference.order ?? order,
            isEnabled: preference.isEnabled ?? isEnabled,
            applicationBundleIdentifier: applicationBundleIdentifier
        )
    }
}

struct AppPreferences: Codable, Equatable {
    /// Bumped whenever a change has to be applied to preferences written by an
    /// older build. See `AppGroupStore.migrate`.
    static let currentVersion = 2

    var version: Int?
    var scripts: [String: ScriptPreference]
    var templates: [String: TemplatePreference]
    var toolbox: [String: ToolboxPreference]
    var compressorIdentifier: String?

    init(
        scripts: [String: ScriptPreference] = [:],
        templates: [String: TemplatePreference] = [:],
        toolbox: [String: ToolboxPreference] = [:],
        compressorIdentifier: String? = nil,
        version: Int? = AppPreferences.currentVersion
    ) {
        self.version = version
        self.scripts = scripts
        self.templates = templates
        self.toolbox = toolbox
        self.compressorIdentifier = compressorIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case scripts
        case templates
        case toolbox
        case compressorIdentifier
    }

    /// Decoded field by field so that a preferences file written by an older or
    /// newer build never fails to load as a whole and silently resets settings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        scripts = try container.decodeIfPresent(
            [String: ScriptPreference].self,
            forKey: .scripts
        ) ?? [:]
        templates = try container.decodeIfPresent(
            [String: TemplatePreference].self,
            forKey: .templates
        ) ?? [:]
        toolbox = try container.decodeIfPresent(
            [String: ToolboxPreference].self,
            forKey: .toolbox
        ) ?? [:]
        compressorIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .compressorIdentifier
        )
    }
}

/// Keys under which `MenuSnapshot` stores menu icons.
///
/// The keys live in Shared because the extension looks them up; rendering them
/// lives in AppCore because only the main app can resolve application and
/// document icons.
enum MenuIconKey {
    static func toolbox(_ id: ToolboxItemID) -> String {
        "toolbox:\(id.rawValue)"
    }

    static func template(_ id: String) -> String {
        "template:\(id)"
    }

    static func script(_ id: String) -> String {
        "script:\(id)"
    }
}

struct MenuSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let generatedAt: Date
    let scripts: [ScriptPackage]
    let templates: [FileTemplate]
    let toolbox: [ToolboxItem]
    /// Small PNGs for the menu items, keyed by `MenuIconRenderer` — see there
    /// for why the extension cannot resolve them itself. Absent in snapshots
    /// written before this field existed.
    let icons: [String: Data]

    init(
        schemaVersion: Int = MenuSnapshot.currentSchemaVersion,
        generatedAt: Date = Date(),
        scripts: [ScriptPackage],
        templates: [FileTemplate],
        toolbox: [ToolboxItem] = ToolboxCatalog.defaultItems,
        icons: [String: Data] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.scripts = scripts
        self.templates = templates
        self.toolbox = toolbox
        self.icons = icons
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case scripts
        case templates
        case toolbox
        case icons
    }

    /// Decoded field by field: a snapshot written by an older build has no
    /// `toolbox` key, and failing the whole decode would leave the extension with
    /// no menu at all until the app happens to run again.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? MenuSnapshot.currentSchemaVersion
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        scripts = try container.decodeIfPresent([ScriptPackage].self, forKey: .scripts) ?? []
        templates = try container.decodeIfPresent([FileTemplate].self, forKey: .templates) ?? []
        toolbox = try container.decodeIfPresent(
            [ToolboxItem].self,
            forKey: .toolbox
        ) ?? ToolboxCatalog.defaultItems
        icons = try container.decodeIfPresent([String: Data].self, forKey: .icons) ?? [:]
    }
}

struct ScriptJobRequest: Codable, Equatable {
    let requestID: UUID
    let scriptID: String
    let arguments: [String]
    let workingDirectory: String
}

struct ScriptJobResult: Codable, Equatable {
    let requestID: UUID
    let succeeded: Bool
    let exitCode: Int32?
    let timedOut: Bool
    let logPath: String?
    let errorMessage: String?
}

/// 压缩器能读的归档扩展名，用于展示能力列表。
///
/// 和 `ArchiveFormats.extensions` 不是一回事：那个判断「用户选中的东西算不算
/// 压缩包」（更宽，含 zst / lz4 之类），这个是「这个压缩器能解哪些格式」。
enum CompressionSupport {
    static let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "tbz2", "lz", "lzma"
    ]
}
