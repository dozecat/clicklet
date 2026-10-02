import Foundation

enum ScriptCatalogError: LocalizedError {
    case scriptsDirectoryUnavailable
    case invalidEntrypoint(String)
    case scriptUnavailable(String)
    case templateUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .scriptsDirectoryUnavailable:
            return "The scripts directory is unavailable."
        case let .invalidEntrypoint(path):
            return "The script is missing or is not executable: \(path)"
        case let .scriptUnavailable(identifier):
            return "The script is unavailable: \(identifier)"
        case let .templateUnavailable(identifier):
            return "The file template is unavailable: \(identifier)"
        }
    }
}

enum ScriptScanner {
    static func scan(
        at root: URL = AppPaths.scriptsDirectory,
        preferences: AppPreferences = AppGroupStore.loadPreferences(),
        fileManager: FileManager = .default
    ) throws -> [ScriptPackage] {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let packageURLs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        return packageURLs.compactMap { packageURL -> ScriptPackage? in
            guard let values = try? packageURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true else {
                return nil
            }

            return scanPackage(
                at: packageURL,
                relativeTo: root,
                preferences: preferences.scripts[packageURL.lastPathComponent],
                fileManager: fileManager
            )
        }
        .sorted {
            if $0.order == $1.order {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    private static func scanPackage(
        at packageURL: URL,
        relativeTo root: URL,
        preferences: ScriptPreference?,
        fileManager: FileManager
    ) -> ScriptPackage? {
        let entrypoint = "script.sh"
        let scriptURL = packageURL.appendingPathComponent(entrypoint)
        guard fileManager.isExecutableFile(atPath: scriptURL.path) else {
            return nil
        }

        let relativeDirectory = packageURL.pathComponents
            .dropFirst(root.pathComponents.count)
            .joined(separator: "/")
        let identifier = relativeDirectory
        let configURL = packageURL.appendingPathComponent("config.json")
        let config: ScriptConfig
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(ScriptConfig.self, from: data) {
            config = decoded
        } else {
            config = ScriptConfig()
        }

        let iconPath: String?
        if let icon = config.icon {
            let candidate = packageURL.appendingPathComponent(icon)
            iconPath = fileManager.fileExists(atPath: candidate.path) ? candidate.path : nil
        } else {
            // Convenience: an icon.png dropped straight into the package works
            // without touching config.json, which is what makes the icon easy to
            // manage — replace one file.
            let implicit = packageURL.appendingPathComponent("icon.png")
            iconPath = fileManager.fileExists(atPath: implicit.path) ? implicit.path : nil
        }

        return ScriptPackage(
            id: identifier,
            name: config.name ?? packageURL.lastPathComponent,
            relativeDirectory: relativeDirectory,
            entrypoint: entrypoint,
            iconPath: iconPath,
            context: config.context ?? .selection,
            allowsMultipleSelection: config.multiple ?? false,
            extensions: (config.extensions ?? []).map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            },
            requiresConfirmation: config.confirm ?? false,
            order: config.order ?? 1_000,
            isEnabled: true,
            applicationBundleIdentifier: config.applicationBundleIdentifier
        )
        .applying(preferences)
    }
}

final class ScriptCatalogService {
    static let shared = ScriptCatalogService()

    private(set) var snapshot: MenuSnapshot?
    private let lock = NSLock()

    private init() {}

    @discardableResult
    func refresh() throws -> MenuSnapshot {
        let scripts = try ScriptScanner.scan()
        let templates = TemplateCatalogService.allTemplates()
        let toolbox = ToolboxCatalog.items(
            preferences: AppGroupStore.loadPreferences().toolbox,
            creatableFormats: CompressionService.shared
                .selectedCompressor
                .capabilities
                .createsFormats
        )
        let snapshot = MenuSnapshot(scripts: scripts, templates: templates, toolbox: toolbox)

        lock.lock()
        self.snapshot = snapshot
        lock.unlock()

        // Publishing the snapshot is how the extension learns about changes. If
        // that fails the catalog itself is still perfectly good, so it must not
        // throw: the caller would otherwise show an empty settings window for a
        // problem that only affects the Finder menu.
        do {
            try AppGroupStore.saveMenuSnapshot(snapshot)
        } catch {
            DiagnosticsLog.log(
                "menu snapshot not published: \(error.localizedDescription)"
            )
        }

        return snapshot
    }

    func currentSnapshot() -> MenuSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot ?? AppGroupStore.loadMenuSnapshot()
    }

    func script(id: String) -> ScriptPackage? {
        currentSnapshot()?.scripts.first { $0.id == id && $0.isEnabled }
    }
}

enum TemplateCatalogService {
    /// Every template in menu order, **including the ones switched off**.
    ///
    /// The settings list has to show disabled templates, otherwise switching one
    /// off removes it from the only place it could be switched back on.
    static func orderedTemplates(
        preferences: AppPreferences = AppGroupStore.loadPreferences(),
        fileManager: FileManager = .default
    ) -> [FileTemplate] {
        (BuiltinTemplates.all + userTemplates(fileManager: fileManager))
            .map { $0.applying(preferences.templates[$0.id]) }
            .sorted {
                if $0.order == $1.order {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.order < $1.order
            }
    }

    /// What the extension renders: enabled templates only.
    static func allTemplates(
        preferences: AppPreferences = AppGroupStore.loadPreferences(),
        fileManager: FileManager = .default
    ) -> [FileTemplate] {
        orderedTemplates(preferences: preferences, fileManager: fileManager)
            .filter { preferences.templates[$0.id]?.isEnabled ?? true }
    }

    /// The App Group `Templates/` folder that user templates are copied into.
    static var userTemplatesDirectory: URL? {
        AppGroup.containerURL?
            .appendingPathComponent("Templates", isDirectory: true)
    }

    private static func userTemplates(fileManager: FileManager = .default) -> [FileTemplate] {
        guard let root = userTemplatesDirectory else {
            return []
        }
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let urls = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.enumerated().compactMap { index, url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }

            let fileExtension = url.pathExtension
            guard !fileExtension.isEmpty else {
                return nil
            }

            return FileTemplate(
                id: "user.\(url.lastPathComponent)",
                name: url.deletingPathExtension().lastPathComponent,
                fileExtension: fileExtension,
                icon: "doc",
                contentSource: .userFile,
                contentPath: url.path,
                order: 100 + index
            )
        }
    }
}
