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
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/RightKit/keka-permission-probe", isDirectory: true)

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

        // Only the sandbox refusal counts as "needs permission". Anything else — a
        // corrupt archive, a full disk — is not something the user can fix in Keka.
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("no file access") ? .missing : .granted
    }
}
