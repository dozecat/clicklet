import CryptoKit
import Foundation

/// Copies the script packages shipped inside the app into the user's scripts
/// directory, and keeps them up to date afterwards.
///
/// The scripts directory stays the single source of truth. Three rules, in
/// order of priority:
///
/// 1. **Never overwrite what the user changed.** After seeding we record a
///    fingerprint of the files we wrote; if the package on disk no longer
///    matches it, the user has edited it and we back off for good.
/// 2. **Never resurrect what the user deleted.** A package that is recorded but
///    missing from disk stays missing.
/// 3. **Do ship updates.** If the app bundle's version changed while the copy on
///    disk is still exactly what we wrote, it is replaced.
enum BuiltinScriptSeeder {
    static let bundledDirectoryName = "BuiltinScripts"

    /// Fingerprint stored by versions that recorded only names. Those packages
    /// were written by us and had no fingerprint to compare against, so they are
    /// allowed one upgrade — after which they carry a real fingerprint.
    private static let unknownFingerprint = ""

    private struct Record: Codable {
        var seeded: [String: String]

        init(seeded: [String: String] = [:]) {
            self.seeded = seeded
        }

        private enum CodingKeys: String, CodingKey {
            case seeded
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let map = try? container.decode([String: String].self, forKey: .seeded) {
                seeded = map
            } else if let list = try? container.decode([String].self, forKey: .seeded) {
                seeded = Dictionary(
                    uniqueKeysWithValues: list.map { ($0, unknownFingerprint) }
                )
            } else {
                seeded = [:]
            }
        }
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

    /// Returns the names of the packages this call actually wrote.
    @discardableResult
    static func seed(
        from source: URL,
        into scriptsDirectory: URL,
        recordURL: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        var record = loadRecord(at: recordURL, fileManager: fileManager)
        let packages = (try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var touched: [String] = []

        for package in packages {
            let name = package.lastPathComponent
            guard (try? package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let destination = scriptsDirectory.appendingPathComponent(name, isDirectory: true)
            let recorded = record.seeded[name]
            let disk = fingerprint(of: destination, fileManager: fileManager)
            let bundled = fingerprint(of: package, fileManager: fileManager)

            switch (recorded, disk) {
            case (nil, nil):
                // Never offered and not present: offer it.
                if write(package, to: destination, fileManager: fileManager) {
                    record.seeded[name] = bundled
                    touched.append(name)
                }

            case (.some, nil):
                // Recorded but gone: the user deleted it. Leave it deleted.
                continue

            case (nil, .some):
                // A package the user made themselves, with the same name.
                continue

            case let (.some(recorded), .some(disk)):
                guard recorded == disk || recorded == unknownFingerprint else {
                    // Changed on disk since we wrote it: the user's version wins.
                    continue
                }
                guard disk != bundled else {
                    // Already current; just make sure the fingerprint is real.
                    record.seeded[name] = bundled
                    continue
                }
                if recorded == unknownFingerprint {
                    DiagnosticsLog.log("builtin script \(name): upgrading a pre-fingerprint copy")
                }
                if write(package, to: destination, fileManager: fileManager) {
                    record.seeded[name] = bundled
                    touched.append(name)
                }
            }
        }

        saveRecord(record, at: recordURL, fileManager: fileManager)
        return touched
    }

    // MARK: - Helpers

    private static func write(
        _ package: URL,
        to destination: URL,
        fileManager: FileManager
    ) -> Bool {
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: package, to: destination)
            makeExecutable(
                destination.appendingPathComponent("script.sh"),
                fileManager: fileManager
            )
            DiagnosticsLog.log("builtin script written: \(destination.lastPathComponent)")
            return true
        } catch {
            // Not fatal: the app still runs, the script is just missing.
            DiagnosticsLog.log(
                "builtin script \(destination.lastPathComponent) failed to write: \(error.localizedDescription)"
            )
            return false
        }
    }

    private static func makeExecutable(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Stable fingerprint of a package's regular files: relative path plus a
    /// SHA-256 of the contents. Swift's `hashValue` is salted per process, so it
    /// cannot be persisted.
    private static func fingerprint(of directory: URL, fileManager: FileManager) -> String? {
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }

        // Resolve symlinks before comparing prefixes. macOS reports
        // `temporaryDirectory` as /var/... while directory enumeration returns
        // /private/var/..., and a mismatch there would leave the absolute path in
        // the fingerprint — making an untouched package look user-edited and
        // silently disabling every future update.
        let base = directory.resolvingSymlinksInPath().path

        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var entries: [String] = []

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else {
                continue
            }

            let path = url.resolvingSymlinksInPath().path
            let relative: String
            if path.hasPrefix(base + "/") {
                relative = String(path.dropFirst(base.count + 1))
            } else {
                // Should not happen; the name still detects content changes.
                relative = url.lastPathComponent
            }

            let data = (try? Data(contentsOf: url)) ?? Data()
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            entries.append("\(relative):\(digest)")
        }

        return entries.sorted().joined(separator: "|")
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
