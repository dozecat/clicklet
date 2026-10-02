import AppKit
import CryptoKit
import Foundation
import ImageIO

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

    /// What we wrote for one package: relative path -> SHA-256 of the contents.
    ///
    /// Per file rather than one hash for the whole package, because the set of
    /// shipped files changes. A whole-package fingerprint taken over the *current*
    /// bundle's file list stops matching a record written over the previous list,
    /// and the package is then misread as user-edited and never updated again.
    private struct Entry: Codable {
        var files: [String: String]
    }

    private struct Record: Codable {
        var seeded: [String: Entry]

        init(seeded: [String: Entry] = [:]) {
            self.seeded = seeded
        }

        private enum CodingKeys: String, CodingKey {
            case seeded
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let map = try? container.decode([String: Entry].self, forKey: .seeded) {
                seeded = map
                return
            }

            // Older records: a bare name list, or one fingerprint per package.
            // The names are kept so a deleted package stays deleted, but there is
            // no per-file detail, so those packages are upgraded once.
            var names: [String] = []
            if let legacy = try? container.decode([String: String].self, forKey: .seeded) {
                names = Array(legacy.keys)
            } else if let list = try? container.decode([String].self, forKey: .seeded) {
                names = list
            }
            seeded = Dictionary(
                uniqueKeysWithValues: names.map { ($0, Entry(files: [:])) }
            )
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
            let exists = fileManager.fileExists(atPath: destination.path)

            switch (recorded, exists) {
            case (nil, false):
                // Never offered and not present: offer it.
                if write(package, to: destination, fileManager: fileManager) {
                    record.seeded[name] = entry(for: package, fileManager: fileManager)
                    touched.append(name)
                }

            case (.some, false):
                // Recorded but gone: the user deleted it. Leave it deleted.
                continue

            case (nil, true):
                // A package the user made themselves, with the same name.
                continue

            case let (.some(entry), true):
                let onDisk = hashes(in: destination, fileManager: fileManager)
                let shipped = hashes(in: package, fileManager: fileManager)

                guard !entry.files.isEmpty else {
                    // Written by a version that recorded no per-file detail.
                    DiagnosticsLog.log("builtin script \(name): upgrading a pre-hash copy")
                    if write(package, to: destination, fileManager: fileManager) {
                        record.seeded[name] = self.entry(for: package, fileManager: fileManager)
                        touched.append(name)
                    }
                    continue
                }

                // Only the files we wrote are compared: anything the user or a
                // previous run added is none of our business.
                let edited = entry.files.contains { path, hash in
                    onDisk[path] != hash
                }
                guard !edited else {
                    continue
                }

                // Files we wrote last time that the bundle no longer ships are
                // removed, so a renamed script does not leave the old one behind.
                // Anything else in the folder belongs to the user and is left
                // alone — which is why this is driven by the record, not by
                // diffing the directory.
                for stale in entry.files.keys where shipped[stale] == nil {
                    try? fileManager.removeItem(
                        at: destination.appendingPathComponent(stale)
                    )
                }

                guard shipped != entry.files else {
                    // Already current; the icon may still be missing on this
                    // machine, so check every launch rather than only on change.
                    materialiseIcon(for: destination, fileManager: fileManager)
                    continue
                }

                if write(package, to: destination, fileManager: fileManager) {
                    record.seeded[name] = self.entry(for: package, fileManager: fileManager)
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

        // The artwork belongs to that application. Writing it is fine — it is a
        // local copy made from software this user already has, for their own
        // screen — but a script package is meant to be shareable, and passing the
        // folder on would redistribute it. Record the provenance in the file so
        // that is discoverable wherever the PNG ends up. Deleting it is safe: the
        // next launch regenerates it on the receiving machine.
        let provenance = "Generated locally by RightKit from \(identifier). "
            + "Do not redistribute; delete this file before sharing the script package."

        guard let png = pngData(from: image, provenance: provenance) else {
            DiagnosticsLog.log("builtin script icon: could not encode \(package.lastPathComponent)")
            return
        }

        do {
            try png.write(to: iconURL)
            DiagnosticsLog.log("builtin script icon written: \(package.lastPathComponent)")
        } catch {
            DiagnosticsLog.log("builtin script icon failed: \(error.localizedDescription)")
        }
    }

    /// PNG with a `Description` text chunk carrying the provenance note.
    private static func pngData(from image: NSImage, provenance: String) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: provenance
            ]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func makeExecutable(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func entry(for package: URL, fileManager: FileManager) -> Entry {
        Entry(files: hashes(in: package, fileManager: fileManager))
    }

    /// Relative path -> SHA-256 for every regular file in a package.
    private static func hashes(in package: URL, fileManager: FileManager) -> [String: String] {
        var result: [String: String] = [:]

        for relative in relativeFiles(in: package, fileManager: fileManager) {
            let url = package.appendingPathComponent(relative)
            result[relative] = (try? Data(contentsOf: url)).map(digest) ?? "missing"
        }

        return result
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
