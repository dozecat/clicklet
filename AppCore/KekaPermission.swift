import AppKit

/// Whether Keka can be driven from the command line.
///
/// Keka is sandboxed and only reaches locations the user has picked, so its CLI
/// fails with "no file access" until the user turns on
/// Keka → Settings → File Access → "Enable access to the home folder".
///
/// There is no API to ask Keka about that setting, so this actually compresses a
/// throwaway file inside the home folder. That location is exactly what the setting
/// controls, and it is what a Finder action would run against.
enum KekaPermission {
    enum State: Equatable {
        case granted
        case missing
        case notInstalled
        case unknown
    }

    static func check() async -> State {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: KekaAdapter().identifier
        ) else {
            return .notInstalled
        }

        let fileManager = FileManager.default
        // Directly under the home folder, not somewhere inside ~/Library: the
        // setting is "access to the home folder", and ~/Library may be reachable
        // regardless, which would make the probe report success while the setting
        // is off. The folder is temporary and removed below.
        // A unique name per run: the pane can trigger this from more than one place,
        // and two runs sharing a folder would delete each other's files.
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".rightkit-keka-probe-\(UUID().uuidString)", isDirectory: true)

        try? fileManager.removeItem(at: directory)
        guard (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return .unknown
        }
        defer { try? fileManager.removeItem(at: directory) }

        let sample = directory.appendingPathComponent("probe.txt")
        guard (try? Data("probe".utf8).write(to: sample)) != nil else { return .unknown }

        let process = Process()
        process.executableURL = app
            .appendingPathComponent("Contents/MacOS/Keka")
        // Absolute paths for both the archive and the input. Relative names relied on
        // the child's working directory being honoured, and the log showed it is not:
        // the probe failed with "Add new data to archive: 0 files, 0 bytes" and exit 1
        // — 7zz ran, but never saw the file. That is not a permission refusal, which
        // would have said "no file access" and exited 2.
        let archive = directory.appendingPathComponent("probe.7z")
        process.arguments = ["--cli", "7zz", "a", "-y", archive.path, sample.path]
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        guard (try? process.run()) != nil else { return .unknown }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return .granted
        }

        // Anything other than success means the command line could not do the job,
        // so the permission is not in place. An earlier version of this treated any
        // failure whose text did not say "no file access" as success, and the sandbox
        // also refuses with errno=2 — so turning the setting off still reported
        // "already set up". Only proven success counts now.
        let output = String(data: data, encoding: .utf8) ?? ""
        let reason = output.contains("no file access")
            ? "refused by Keka's sandbox"
            : "7zz did not fail on permissions"
        DiagnosticsLog.log(
            "keka permission probe failed (\(process.terminationStatus), \(reason)): \(output.suffix(200))"
        )
        return .missing
    }
}
