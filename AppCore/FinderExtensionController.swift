import Foundation

enum FinderExtensionError: LocalizedError {
    case pluginkitUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .pluginkitUnavailable:
            return "RightKit could not run pluginkit to change the Finder extension."
        case let .commandFailed(message):
            return "pluginkit failed: \(message)"
        }
    }
}

/// Reads and changes whether the Finder Sync extension is enabled.
///
/// A Finder Sync extension is hosted by Finder, not by the containing app, so
/// quitting RightKit leaves the right-click menu running. macOS keeps the on/off
/// state in the PlugInKit election database, and `pluginkit(1)` is the supported
/// way for an app to read and change it.
enum FinderExtensionController {
    static let bundleIdentifier = "com.dozecat.RightKit.FinderExtension"

    enum State: Equatable {
        case enabled
        case disabled
        case unknown
    }

    static func currentState() -> State {
        guard let result = runPluginkit(["-m", "-i", bundleIdentifier]),
              result.status == 0 else {
            return .unknown
        }

        return parseState(from: result.output)
    }


    /// Makes pkd reload the extension.
    ///
    /// Finder does not load a Finder Sync extension by itself after a reboot: it waits
    /// for the extension's election to change. That is why the menu is missing after a
    /// restart until the switch in System Settings has been flipped off and on — the
    /// "off" half is what does the work. Doing the same thing once per launch is this
    /// method's whole purpose.
    ///
    /// Only runs when the extension is currently elected, so a user who turned it off
    /// on purpose keeps it off.
    @discardableResult
    static func reelect() -> Bool {
        guard currentState() == .enabled else { return false }

        do {
            try setEnabled(false)
            try setEnabled(true)
            DiagnosticsLog.log("extension re-elected at launch")
            return true
        } catch {
            DiagnosticsLog.log("extension re-election failed: \(error)")
            return false
        }
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        let election = isEnabled ? "use" : "ignore"
        guard let result = runPluginkit(["-e", election, "-i", bundleIdentifier]) else {
            throw FinderExtensionError.pluginkitUnavailable
        }

        guard result.status == 0 else {
            // pluginkit chats on stderr (for example "Unable to obtain a task
            // name port right for pid ..."), which is not actionable and should
            // never reach the settings window. Keep the detail in the
            // diagnostics log and show a short, useful message instead.
            DiagnosticsLog.log(
                "pluginkit -e \(election) failed status=\(result.status) "
                    + "stdout=[\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))] "
                    + "stderr=[\(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))]"
            )
            throw FinderExtensionError.commandFailed(
                "macOS would not change the extension state. Use System Settings instead."
            )
        }

        DiagnosticsLog.log("pluginkit -e \(election) succeeded")
    }

    /// `pluginkit -m` prefixes every match with its election state: `+` when the
    /// extension is in use and `-` when it has been ignored. Anything else (or no
    /// match at all) is reported as unknown so the UI can fall back to the
    /// system settings pane instead of showing a wrong switch position.
    static func parseState(from output: String) -> State {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains(bundleIdentifier),
                  let marker = line.first(where: { !$0.isWhitespace }) else {
                continue
            }

            switch marker {
            case "+":
                return .enabled
            case "-":
                return .disabled
            default:
                return .unknown
            }
        }

        return .unknown
    }

    private struct PluginkitResult {
        let output: String
        let errorOutput: String
        let status: Int32
    }

    private static func runPluginkit(_ arguments: [String]) -> PluginkitResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments

        // stdout and stderr are kept apart: only stdout should influence the
        // parsed state, and stderr is purely diagnostic noise.
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            DiagnosticsLog.log("could not run pluginkit: \(error.localizedDescription)")
            NSLog("RightKit could not run pluginkit: %@", error.localizedDescription)
            return nil
        }

        // Drain both pipes before waiting so the child can never block on a full
        // pipe buffer.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return PluginkitResult(
            output: String(data: outputData, encoding: .utf8) ?? "",
            errorOutput: String(data: errorData, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}
