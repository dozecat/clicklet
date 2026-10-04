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
    /// A PNG inside the app bundle to use instead of `icon`. Only language marks go
    /// here — the ones the project ships for the same reason it ships the Python
    /// logo: they indicate what a file is, rather than redistribute an application's
    /// artwork. Application icons come from `SystemIcon.file(for:)` instead.
    var iconResourcePath: String? = nil
    let contentSource: TemplateContentSource
    let contentPath: String?
    let order: Int
    /// Whether the template starts switched on. `nil` means "on", which is both the
    /// old behaviour and what all but a few templates want, so most definitions can
    /// leave it out.
    var defaultEnabled: Bool? = nil
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
            iconResourcePath: iconResourcePath,
            contentSource: contentSource,
            contentPath: contentPath,
            order: preference.order ?? order,
            defaultEnabled: defaultEnabled
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

/// The UI language. `system` means follow the system; the rest are the matching
/// lproj codes.
///
/// The two UIs need **two different mechanisms**, and they must not be mixed:
/// - Main app: the process-level `AppleLanguages`, which needs a relaunch after a
///   change
/// - Finder extension: it runs inside Finder's process, and a process-level
///   preference would change **Finder's** language too, so it can only pick an
///   lproj explicitly from the preference and look the string up (see
///   LocalizedText)
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// The lproj code.
    var lprojCode: String { rawValue }

    /// When the preference holds no language yet, pick a concrete one from the
    /// system preference.
    /// The user explicitly asked for no "Follow System" entry, so what is returned
    /// here is one definite language.
    static var defaultFromSystem: AppLanguage {
        // Read the system preference rather than Locale.preferredLanguages: that one is
        // filtered by this bundle's own localizations, and only en.lproj is compiled —
        // Chinese is the catalogue's source language and produces no lproj — so inside
        // the app it always answers "en", even on a Chinese system.
        //
        // The app's own domain holds no AppleLanguages (an older build used to write
        // one), so `UserDefaults.standard` resolves to the global setting.
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
            ?? Locale.preferredLanguages.first
            ?? "en"

        return preferred.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }

    /// The name shown in the UI, each written natively in its own language; neither
    /// is translated.
    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
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
    /// Optional: older configurations have no such key, and the default is to follow
    /// the system.
    var language: AppLanguage?

    /// The language actually in effect.
    var resolvedLanguage: AppLanguage { language ?? .defaultFromSystem }

    init(
        scripts: [String: ScriptPreference] = [:],
        templates: [String: TemplatePreference] = [:],
        toolbox: [String: ToolboxPreference] = [:],
        compressorIdentifier: String? = nil,
        language: AppLanguage? = nil,
        version: Int? = AppPreferences.currentVersion
    ) {
        self.version = version
        self.scripts = scripts
        self.templates = templates
        self.toolbox = toolbox
        self.compressorIdentifier = compressorIdentifier
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case scripts
        case templates
        case toolbox
        case compressorIdentifier
        case language
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
        // A new field has to be added here as well: this is a hand-written
        // field-by-field decoder, and adding it to the struct and CodingKeys alone
        // is not enough — miss it here and every read from disk drops that field,
        // so the UI looks like "the setting changed itself back".
        // `try?` on purpose: an old file may hold a language value that has since
        // been removed (for example "system"), and strict decoding would throw,
        // while a caller that fails falls back to the defaults as a whole and loses
        // the other settings along with it.
        language = (try? container.decodeIfPresent(
            AppLanguage.self,
            forKey: .language
        )) ?? nil
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

/// The archive extensions the compressor can read, used to show the capabilities
/// list.
///
/// Not the same thing as `ArchiveFormats.extensions`: that one decides "does what
/// the user selected count as an archive" (broader, including things like zst /
/// lz4), while this one is "which formats this compressor can decompress".
enum CompressionSupport {
    static let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "tbz2", "lz", "lzma"
    ]
}
