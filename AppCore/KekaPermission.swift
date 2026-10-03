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
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".rightkit-keka-probe", isDirectory: true)

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
        process.arguments = ["--cli", "7zz", "a", "-y", "probe.7z", "probe.txt"]
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
        DiagnosticsLog.log("keka permission probe failed (\(process.terminationStatus)): \(output.suffix(200))")
        return .missing
    }
}
