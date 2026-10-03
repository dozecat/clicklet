import AppKit
import Foundation

enum ArchiveError: LocalizedError {
    case noSelection
    case unsupportedOperation
    case compressorUnavailable
    case unsupportedForSelectedTool(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "没有选中任何项目。"
        case .unsupportedOperation:
            return "不支持这个操作。"
        case .compressorUnavailable:
            return "找不到 Keka，无法处理这个格式。"
        case let .unsupportedForSelectedTool(name):
            return "所选的压缩软件不支持 \(name)。可在「压缩解压」页改用 Keka。"
        case let .commandFailed(message):
            return message
        }
    }
}

/// Runs the archive commands the toolbox offers, without going through the
/// archive tool's user interface.
///
/// ZIP uses the system's own tools. Everything else goes to the command-line
/// helpers Keka ships — `Keka --cli 7zz …`, the invocation Keka documents inside
/// its own binary — because macOS has no built-in 7-Zip. Every command is
/// written to the diagnostics log, which is the only way to see what a silent
/// menu action actually did.
enum ArchiveService {
    enum Format {
        case zip
        case sevenZip

        var fileExtension: String {
            switch self {
            case .zip:
                return "zip"
            case .sevenZip:
                return "7z"
            }
        }
    }

    static func perform(
        _ kind: FinderActionKind,
        urls: [URL],
        in directory: URL
    ) async throws -> URL? {
        guard !urls.isEmpty else {
            throw ArchiveError.noSelection
        }

        switch kind {
        case .compressZip:
            return try await compress(urls, in: directory, format: .zip)
        case .compressSevenZip:
            return try await compress(urls, in: directory, format: .sevenZip)
        case .decompressHere:
            try await decompress(urls, into: directory)
            // Returning nil = the caller does not "reveal the result".
            //
            // This used to return directory (the folder itself), and the caller
            // would then activateFileViewerSelecting it, which **steals Finder to
            // the front and selects that folder** — the user is already in this
            // folder, so it looked like "extraction opened Finder".
            // The separate-folder path returns a new directory, where revealing
            // does make sense, so only this case was changed to nil.
            return nil
        case .decompressIntoFolder:
            return try await decompressIntoOwnFolders(urls, in: directory)
        default:
            throw ArchiveError.unsupportedOperation
        }
    }

    // MARK: - Compression

    private static func compress(
        _ urls: [URL],
        in directory: URL,
        format: Format
    ) async throws -> URL? {
        let baseName = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : directory.lastPathComponent
        let output = NewFileService.uniqueURL(
            for: "\(baseName).\(format.fileExtension)",
            in: directory
        )
        let names = urls.map(\.lastPathComponent)

        // Delete the half-finished output on failure: archivers often create an
        // empty archive first and only then report the error, and leaving it
        // behind makes people think the compression succeeded.
        func discardOutputOnFailure(_ body: () async throws -> Void) async throws {
            do {
                try await body()
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }

        switch format {
        case .zip:
            // `-r` for folders, `-X` to skip Finder metadata.
            try await discardOutputOnFailure {
                try await run(
                    URL(fileURLWithPath: "/usr/bin/zip"),
                    ["-r", "-X", output.lastPathComponent] + names,
                    in: directory
                )
            }
        case .sevenZip:
            // macOS has no system 7z writer, and Keka's CLI cannot be used: measured
            // in a terminal it refuses every path, including /tmp, because it runs in
            // Keka's sandbox with no user gesture behind the call.
            //
            // Handing the files to Keka's own window is the route that works — it is
            // exactly what dragging files onto Keka does.
            try await handToKeka(urls)
            return nil
        }

        return output
    }

    // MARK: - Extraction

    private static func decompress(_ archives: [URL], into directory: URL) async throws {
        for archive in archives {
            try await extract(archive, into: directory)
        }
    }

    private static func decompressIntoOwnFolders(
        _ archives: [URL],
        in directory: URL
    ) async throws -> URL? {
        var firstCreated: URL?

        for archive in archives {
            let name = archive.deletingPathExtension().lastPathComponent
            let destination = uniqueDirectory(named: name, in: directory)
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            try await extract(archive, into: destination)

            if firstCreated == nil {
                firstCreated = destination
            }
        }

        return firstCreated
    }

    /// Formats the built-in tools can unpack without Keka.
    /// Extensions the system's bsdtar can read. zip is handled separately by ditto.
    private static let systemExtractable: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz",
        "7z", "rar", "lz", "lzma", "zst", "lz4", "br", "cab"
    ]

    private static func extract(_ archive: URL, into destination: URL) async throws {
        let fileExtension = archive.pathExtension.lowercased()

        // zip goes through ditto: it keeps resource forks and is what Finder uses.
        if fileExtension == "zip" {
            try await run(
                URL(fileURLWithPath: "/usr/bin/ditto"),
                ["-x", "-k", archive.path, destination.path],
                in: destination
            )
            return
        }

        // Everything else goes through the system's bsdtar (libarchive). Measured: it
        // reads 7z, rar, tar, gz and xz, so Keka is not needed for extraction at all.
        //
        // Keka's CLI is deliberately not used here: it runs inside Keka's own app
        // sandbox and a background call carries no user gesture, so Keka refuses every
        // path. Reproduced in a terminal — it fails even for /tmp.
        guard systemExtractable.contains(fileExtension) else {
            throw ArchiveError.unsupportedForSelectedTool(".\(fileExtension)")
        }

        try await run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            ["-xf", archive.path, "-C", destination.path],
            in: destination
        )
    }

    /// Capabilities of the compressor currently chosen in the settings window.
    private static var capabilities: CompressorCapabilities {
        CompressionService.shared.selectedCompressor.capabilities
    }

    // MARK: - Helpers

    private static func uniqueDirectory(named name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(name) \(index)",
                isDirectory: true
            )
            index += 1
        }

        return candidate
    }

    private static func kekaExecutable() throws -> URL {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: KekaAdapter().identifier
        ) else {
            throw ArchiveError.compressorUnavailable
        }

        return app
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Keka")
    }

    /// Runs `executable` inside `directory`.
    ///
    /// The cwd is forced with `/bin/sh -c 'cd …; exec …'` instead of relying only
    /// on `Process.currentDirectoryURL`: Keka's `--cli` is a wrapper that execs
    /// the real 7zz, and in practice (user logs) 7zz could not find the input file
    /// sitting in the same directory (errno=2), which shows it did not inherit the
    /// working directory we set.
    ///
    /// The arguments reach sh through argv with no string concatenation, so spaces
    /// and Chinese characters in file names are safe.
    /// Hands the selection to Keka's window — the same thing dragging files onto
    /// Keka does. Its command line cannot be used; see the note in extract().
    private static func handToKeka(_ urls: [URL]) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: KekaAdapter().identifier
        ) else {
            throw ArchiveError.compressorUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(
            urls,
            withApplicationAt: app,
            configuration: configuration
        )
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL
    ) async throws {
        DiagnosticsLog.log(
            "archive: \(executable.path) \(arguments.joined(separator: " ")) (cwd: \(directory.path))"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", #"cd "$1" || exit 66; shift; exec "$@""#,
            "sh", directory.path, executable.path
        ] + arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ArchiveError.commandFailed(error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            DiagnosticsLog.log("archive failed (\(process.terminationStatus)): \(output)")
            throw ArchiveError.commandFailed(
                output.isEmpty ? "命令退出码 \(process.terminationStatus)" : output
            )
        }

        DiagnosticsLog.log("archive ok: \(output.suffix(300))")
    }
}
