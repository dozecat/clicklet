import Foundation

/// Copies the script packages shipped inside the app into the user's scripts
/// directory, once each.
///
/// The scripts directory stays the single source of truth: a package the user
/// edits is never overwritten, and one they delete is not recreated — that is
/// what the seeded-names record is for. A package added by a later version of
/// the app is not in the record yet, so it still gets offered.
enum BuiltinScriptSeeder {
    static let bundledDirectoryName = "BuiltinScripts"

    /// Names of the packages offered so far.
    private struct Record: Codable {
        var seeded: [String] = []
    }

    /// The folder inside the app bundle holding the packages.
    static func bundledScriptsURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: bundledDirectoryName, withExtension: nil)
    }

    @discardableResult
    static func seedIfNeeded(
        bundle: Bundle = .main,
        scriptsDirectory: URL = AppPaths.scriptsDirectory,
        recordURL: URL = AppPaths.seededScriptsRecord,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let source = bundledScriptsURL(bundle: bundle) else {
            DiagnosticsLog.log("builtin scripts: no \(bundledDirectoryName) folder in the bundle")
            return []
        }

        return seed(
            from: source,
            into: scriptsDirectory,
            recordURL: recordURL,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func seed(
        from source: URL,
        into scriptsDirectory: URL,
        recordURL: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        let record = loadRecord(at: recordURL, fileManager: fileManager)
        let packages = (try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var seeded = record.seeded

        for package in packages {
            let name = package.lastPathComponent

            guard (try? package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !seeded.contains(name) else {
                continue
            }

            let destination = scriptsDirectory.appendingPathComponent(name, isDirectory: true)

            do {
                try fileManager.createDirectory(
                    at: scriptsDirectory,
                    withIntermediateDirectories: true
                )
                // Never clobber a directory the user already made by hand.
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: package, to: destination)
                    makeExecutable(
                        destination.appendingPathComponent("script.sh"),
                        fileManager: fileManager
                    )
                }
                seeded.append(name)
                DiagnosticsLog.log("builtin script seeded: \(name)")
            } catch {
                // Not fatal: the app still runs, the script is just missing.
                DiagnosticsLog.log("builtin script \(name) failed to seed: \(error.localizedDescription)")
            }
        }

        saveRecord(Record(seeded: seeded), at: recordURL, fileManager: fileManager)
        return seeded
    }

    private static func makeExecutable(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func loadRecord(at url: URL, fileManager: FileManager) -> Record {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            return Record()
        }
        return record
    }

    private static func saveRecord(_ record: Record, at url: URL, fileManager: FileManager) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
