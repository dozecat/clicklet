import Foundation

/// Append-only diagnostic log shared by the app and the Finder extension.
///
/// The Finder extension runs in its own process, so its `NSLog` output is not
/// visible from the containing app and is awkward to collect from Console.
/// Writing to a file inside the App Group gives both processes one place to
/// explain what they did, which makes "the menu item does nothing" reports
/// actionable instead of guesswork.
enum DiagnosticsLog {
    static let directoryName = "Logs"
    static let fileName = "clicklet.log"

    /// Small enough to stay cheap to rewrite, large enough to cover a session.
    private static let maximumBytes = 128 * 1024
    private static let lock = NSLock()

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let processTag = ProcessInfo.processInfo.processName

    static var logURL: URL? {
        AppGroup.containerURL?
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func log(_ message: String) {
        guard let url = logURL else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let line = "\(formatter.string(from: Date())) [\(processTag)] \(message)\n"
        guard let lineData = line.data(using: .utf8) else {
            return
        }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var contents = (try? Data(contentsOf: url)) ?? Data()
        contents.append(lineData)
        if contents.count > maximumBytes {
            contents = Data(contents.suffix(maximumBytes / 2))
        }

        try? contents.write(to: url, options: .atomic)
    }
}
