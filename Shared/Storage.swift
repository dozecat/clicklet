import Foundation

enum AppGroup {
    static let fallbackIdentifier = "group.com.dozecat.RightKit"

    static var identifier: String {
        Bundle.main.object(forInfoDictionaryKey: "RightKitAppGroupIdentifier") as? String
            ?? fallbackIdentifier
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RightKit", isDirectory: true)
    }

    static var scriptsDirectory: URL {
        supportDirectory.appendingPathComponent("Scripts", isDirectory: true)
    }

    /// Records which built-in script packages have already been offered, so a
    /// package the user deleted is not recreated while packages added by a later
    /// version still are.
    static var seededScriptsRecord: URL {
        supportDirectory.appendingPathComponent("seeded-scripts.json")
    }

    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RightKit", isDirectory: true)
    }

    static var scriptLogsDirectory: URL {
        logsDirectory.appendingPathComponent("Scripts", isDirectory: true)
    }
}

enum AppGroupStore {
    static let catalogDidChangeNotification = Notification.Name("com.dozecat.RightKit.catalogDidChange")

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The first-run marker. It lives in the user's support directory (not the
    /// shared container — that one is for the extension), so deleting the container
    /// or reinstalling the extension does not send the user through onboarding
    /// again.
    static var firstRunMarker: URL {
        AppPaths.supportDirectory.appendingPathComponent("first-run-done")
    }

    static var hasCompletedFirstRun: Bool {
        FileManager.default.fileExists(atPath: firstRunMarker.path)
    }

    static func markFirstRunCompleted() {
        try? FileManager.default.createDirectory(
            at: AppPaths.supportDirectory, withIntermediateDirectories: true
        )
        try? Data().write(to: firstRunMarker)
    }

    static func loadMenuSnapshot() -> MenuSnapshot? {
        guard let url = menuSnapshotURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode(MenuSnapshot.self, from: data)
    }

    static func menuSnapshotModificationDate() -> Date? {
        guard let url = menuSnapshotURL else {
            return nil
        }

        return try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    static func saveMenuSnapshot(_ snapshot: MenuSnapshot) throws {
        guard let url = menuSnapshotURL else {
            throw AppGroupError.containerUnavailable
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        DistributedNotificationCenter.default().post(name: catalogDidChangeNotification, object: nil)
    }

    static func loadPreferences() -> AppPreferences {
        guard let url = preferencesURL,
              let data = try? Data(contentsOf: url),
              var preferences = try? decoder.decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }

        if (preferences.version ?? 1) < AppPreferences.currentVersion {
            preferences = migrate(preferences)
            try? savePreferences(preferences)
        }

        return preferences
    }

    /// v1 → v2: the built-in starter documents used to be missing from the app
    /// bundle, so creating Word/Excel/PowerPoint files always failed and users
    /// switched those templates off. They ship and work now, so switch them back
    /// on once. Any ordering override is kept.
    static func migrate(_ preferences: AppPreferences) -> AppPreferences {
        var migrated = preferences

        for template in BuiltinTemplates.all {
            guard var preference = migrated.templates[template.id] else {
                continue
            }
            preference.isEnabled = nil
            migrated.templates[template.id] = preference
        }

        migrated.version = AppPreferences.currentVersion
        return migrated
    }

    static func savePreferences(_ preferences: AppPreferences) throws {
        guard let url = preferencesURL else {
            throw AppGroupError.containerUnavailable
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(preferences).write(to: url, options: .atomic)
    }

    static func saveActionRequest(_ request: FinderActionRequest) throws {
        guard let url = actionRequestURL(id: request.id) else {
            throw AppGroupError.containerUnavailable
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(request).write(to: url, options: .atomic)
    }

    static func pendingActionRequestIDs() -> [UUID] {
        guard let directory = actionRequestsDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension == "json" else {
                return nil
            }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }

    static func loadActionRequest(id: UUID) throws -> FinderActionRequest {
        guard let url = actionRequestURL(id: id) else {
            throw AppGroupError.containerUnavailable
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(FinderActionRequest.self, from: data)
    }

    static func removeActionRequest(id: UUID) {
        guard let url = actionRequestURL(id: id) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func encodeScriptJobResult(_ result: ScriptJobResult) throws -> Data {
        try encoder.encode(result)
    }

    static func decodeScriptJobRequest(_ data: Data) throws -> ScriptJobRequest {
        try decoder.decode(ScriptJobRequest.self, from: data)
    }

    static func decodeScriptJobResult(_ data: Data) throws -> ScriptJobResult {
        try decoder.decode(ScriptJobResult.self, from: data)
    }

    private static var menuSnapshotURL: URL? {
        AppGroup.containerURL?
            .appendingPathComponent("State", isDirectory: true)
            .appendingPathComponent("menu-snapshot.json")
    }

    private static var preferencesURL: URL? {
        AppGroup.containerURL?
            .appendingPathComponent("State", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    private static func actionRequestURL(id: UUID) -> URL? {
        actionRequestsDirectory?
            .appendingPathComponent("\(id.uuidString).json")
    }

    static var actionRequestsDirectory: URL? {
        AppGroup.containerURL?
            .appendingPathComponent("Requests", isDirectory: true)
    }
}

enum AppGroupError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "RightKit App Group container is unavailable."
        }
    }
}
