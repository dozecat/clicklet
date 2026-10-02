import AppKit
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
            let disk = fingerprint(of: destination, matching: package, fileManager: fileManager)
            let bundled = fingerprint(of: package, matching: package, fileManager: fileManager)

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
                    // Already current. The icon is generated on this machine and
                    // is not part of the bundle, so a package that was seeded
                    // before icons existed still needs one — check every launch
                    // rather than only when the shipped files change.
                    materialiseIcon(for: destination, fileManager: fileManager)
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
            // Create the package folder itself: copyContents writes into it
            // rather than replacing it, so it must exist first.
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            // Copy the shipped files over the top instead of replacing the whole
            // folder: anything the user or a previous run added (their own icon,
            // notes, extra scripts) survives an update.
            try copyContents(of: package, into: destination, fileManager: fileManager)
            makeExecutable(
                destination.appendingPathComponent("script.sh"),
                fileManager: fileManager
            )
            materialiseIcon(for: destination, fileManager: fileManager)
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

    private static func copyContents(
        of package: URL,
        into destination: URL,
        fileManager: FileManager
    ) throws {
        let items = try fileManager.contentsOfDirectory(
            at: package,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }

    /// Renders the icon of the application named by the package's config into
    /// `icon.png` inside the package.
    ///
    /// Done here, on the user's machine, rather than shipping the file: the
    /// artwork belongs to the app it came from, and keeping it out of the
    /// repository avoids redistributing someone else's trademark. It also means
    /// the icon stays put if that application is later removed.
    private static func materialiseIcon(for package: URL, fileManager: FileManager) {
        let iconURL = package.appendingPathComponent("icon.png")
        guard !fileManager.fileExists(atPath: iconURL.path) else {
            return
        }

        guard let data = try? Data(contentsOf: package.appendingPathComponent("config.json")),
              let config = try? JSONDecoder().decode(ScriptConfig.self, from: data),
              let identifier = config.applicationBundleIdentifier,
              let application = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: identifier
              ) else {
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: application.path)
        let side: CGFloat = 64
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try png.write(to: iconURL)
            DiagnosticsLog.log("builtin script icon written: \(package.lastPathComponent)")
        } catch {
            DiagnosticsLog.log("builtin script icon failed: \(error.localizedDescription)")
        }
    }

    private static func makeExecutable(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Fingerprint of `directory`, covering exactly the files `package` ships.
    ///
    /// Anything present only in `directory` — an icon this app generated, a note
    /// the user dropped in — is ignored. Counting it would make a package look
    /// user-edited the moment they add a file, freezing every future update.
    private static func fingerprint(
        of directory: URL,
        matching package: URL,
        fileManager: FileManager
    ) -> String? {
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }

        var entries: [String] = []

        for relative in relativeFiles(in: package, fileManager: fileManager) {
            let url = directory.appendingPathComponent(relative)
            let value = (try? Data(contentsOf: url)).map(digest) ?? "missing"
            entries.append("\(relative):\(value)")
        }

        return entries.sorted().joined(separator: "|")
    }

    /// Regular files inside a package, as paths relative to it.
    private static func relativeFiles(in package: URL, fileManager: FileManager) -> [String] {
        // Resolve symlinks first. macOS reports `temporaryDirectory` as /var/...
        // while enumeration returns /private/var/..., and a prefix mismatch there
        // would leave absolute paths in the fingerprint — making an untouched
        // package look user-edited and silently disabling every future update.
        let base = package.resolvingSymlinksInPath().path
        let keys: [URLResourceKey] = [.isRegularFileKey]

        guard let enumerator = fileManager.enumerator(
            at: package,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else {
                continue
            }
            let path = url.resolvingSymlinksInPath().path
            if path.hasPrefix(base + "/") {
                files.append(String(path.dropFirst(base.count + 1)))
            } else {
                files.append(url.lastPathComponent)
            }
        }

        return files
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
