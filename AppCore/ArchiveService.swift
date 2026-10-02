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
            // 返回 nil = 调用方不去"显示结果"。
            //
            // 这里原来返回 directory（就是这个文件夹本身），调用方随后
            // activateFileViewerSelecting 它会**把访达抢到前台并选中该文件夹**——
            // 用户本来就在这个文件夹里，看上去就像"解压却打开了访达"。
            // 新建独立文件夹那条返回的是新目录，显示它才有意义，所以只有这里改为 nil。
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
    ) async throws -> URL {
        let baseName = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : directory.lastPathComponent
        let output = NewFileService.uniqueURL(
            for: "\(baseName).\(format.fileExtension)",
            in: directory
        )
        let names = urls.map(\.lastPathComponent)

        // 失败时把半成品删掉：压缩工具常常先建出一个 0 文件的包再报错，
        // 留着它会让人以为压缩成功了。
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
            guard capabilities.supportsSevenZip else {
                // The built-in tools cannot make 7z archives; the toolbox hides
                // this command in that case, so this is a last-resort guard.
                throw ArchiveError.unsupportedForSelectedTool("7z")
            }
            try await discardOutputOnFailure {
                try await run(
                    try kekaExecutable(),
                    ["--cli", "7zz", "a", "-y", output.lastPathComponent] + names,
                    in: directory
                )
            }
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
    private static let systemExtractable: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz"
    ]

    private static func extract(_ archive: URL, into destination: URL) async throws {
        let fileExtension = archive.pathExtension.lowercased()

        if fileExtension == "zip" {
            // `ditto` keeps resource forks and is what Finder itself uses.
            try await run(
                URL(fileURLWithPath: "/usr/bin/ditto"),
                ["-x", "-k", archive.path, destination.path],
                in: destination
            )
            return
        }

        if capabilities.supportsSevenZip {
            try await run(
                try kekaExecutable(),
                ["--cli", "7zz", "x", archive.path, "-o\(destination.path)", "-y"],
                in: destination
            )
            return
        }

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

    /// 在 `directory` 里执行 `executable`。
    ///
    /// cwd 用 `/bin/sh -c 'cd …; exec …'` 强制设置，而不是只依赖
    /// `Process.currentDirectoryURL`：Keka 的 `--cli` 是个包装器，它会再 exec
    /// 真正的 7zz，而实测（用户日志）那条路径下 7zz 找不到同一目录里的输入文件
    /// （errno=2），说明它没有继承我们设的工作目录。
    ///
    /// 参数走 argv 传给 sh，不做字符串拼接，所以文件名里的空格、中文都安全。
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
