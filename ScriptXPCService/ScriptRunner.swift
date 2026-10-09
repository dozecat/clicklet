import Darwin
import Foundation

final class ScriptRunner: NSObject, ScriptXPCProtocol {
    private let executionQueue = DispatchQueue(label: "com.dozecat.Clicklet.script-runner")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let timeout: TimeInterval = 300

    func executeScript(_ requestData: Data, reply: @escaping (Data) -> Void) {
        let decodedRequest = try? decoder.decode(ScriptJobRequest.self, from: requestData)

        executionQueue.async { [self] in
            let result: ScriptJobResult
            if let request = decodedRequest {
                result = run(request)
            } else {
                result = ScriptJobResult(
                    requestID: UUID(),
                    succeeded: false,
                    exitCode: nil,
                    timedOut: false,
                    logPath: nil,
                    errorMessage: "The script request is invalid."
                )
            }

            let responseData = (try? encoder.encode(result)) ?? Data()
            reply(responseData)
        }
    }

    private func run(_ request: ScriptJobRequest) -> ScriptJobResult {
        var activeProcess: Process?
        do {
            guard let snapshot = AppGroupStore.loadMenuSnapshot(),
                  let script = snapshot.scripts.first(where: {
                      $0.id == request.scriptID && $0.isEnabled
                  }) else {
                throw ScriptRunnerError.scriptUnavailable(request.scriptID)
            }

            let scriptURL = try validatedScriptURL(for: script)
            let workingDirectory = URL(
                fileURLWithPath: request.workingDirectory,
                isDirectory: true
            )
            guard FileManager.default.fileExists(atPath: workingDirectory.path) else {
                throw ScriptRunnerError.invalidWorkingDirectory(workingDirectory.path)
            }

            let logURL = try makeLogURL(scriptID: script.id, requestID: request.requestID)
            let logHandle = try FileHandle(forWritingTo: logURL)
            try writeHeader(
                to: logHandle,
                request: request,
                scriptURL: scriptURL,
                workingDirectory: workingDirectory
            )

            let process = Process()
            process.executableURL = scriptURL
            process.arguments = request.arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = logHandle
            process.standardError = logHandle

            var environment = ProcessInfo.processInfo.environment
            environment["CLICKLET_DIR"] = workingDirectory.path
            environment["CLICKLET_FILES"] = request.arguments.joined(separator: "\n")
            process.environment = environment

            activeProcess = process
            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.5)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            try? logHandle.close()

            let exitCode = process.terminationStatus
            let succeeded = !timedOut && exitCode == 0
            return ScriptJobResult(
                requestID: request.requestID,
                succeeded: succeeded,
                exitCode: exitCode,
                timedOut: timedOut,
                logPath: logURL.path,
                errorMessage: timedOut
                    ? "脚本超过 300 秒超时。"
                    : nil
            )
        } catch {
            if let activeProcess, activeProcess.isRunning {
                activeProcess.terminate()
            }
            return ScriptJobResult(
                requestID: request.requestID,
                succeeded: false,
                exitCode: nil,
                timedOut: false,
                logPath: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func validatedScriptURL(for script: ScriptPackage) throws -> URL {
        let rootURL = AppPaths.scriptsDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let scriptURL = rootURL
            .appendingPathComponent(script.relativeDirectory, isDirectory: true)
            .appendingPathComponent(script.entrypoint)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard scriptURL.path.hasPrefix(rootPrefix),
              FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw ScriptRunnerError.invalidScript(scriptURL.path)
        }

        return scriptURL
    }

    private func makeLogURL(scriptID: String, requestID: UUID) throws -> URL {
        let safeScriptID = scriptID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let directory = AppPaths.scriptLogsDirectory
            .appendingPathComponent(safeScriptID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(timestamp)-\(requestID.uuidString.prefix(8)).log"
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ScriptRunnerError.logCreationFailed(url.path)
        }
        return url
    }

    private func writeHeader(
        to handle: FileHandle,
        request: ScriptJobRequest,
        scriptURL: URL,
        workingDirectory: URL
    ) throws {
        let header = """
        Clicklet script execution
        request: \(request.requestID.uuidString)
        script: \(scriptURL.path)
        working directory: \(workingDirectory.path)
        arguments:
        \(request.arguments.joined(separator: "\n"))

        """
        try handle.write(contentsOf: Data(header.utf8))
    }
}

enum ScriptRunnerError: LocalizedError {
    case scriptUnavailable(String)
    case invalidScript(String)
    case invalidWorkingDirectory(String)
    case logCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .scriptUnavailable(identifier):
            return "The script is unavailable: \(identifier)"
        case let .invalidScript(path):
            return "The script path is invalid or not executable: \(path)"
        case let .invalidWorkingDirectory(path):
            return "The working directory is invalid: \(path)"
        case let .logCreationFailed(path):
            return "Unable to create the log file: \(path)"
        }
    }
}
