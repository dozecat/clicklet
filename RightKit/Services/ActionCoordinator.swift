import AppKit
import Darwin
import Foundation

@MainActor
final class ActionCoordinator {
    static let shared = ActionCoordinator()

    private let xpcClient = ScriptXPCClient()
    private var activityTokens: [UUID: NSObjectProtocol] = [:]
    private var handledRequestIDs: Set<UUID> = []
    private var requestDirectorySource: DispatchSourceFileSystemObject?

    private init() {}

    func start() {
        DiagnosticsLog.log(
            "coordinator start; pending=\(AppGroupStore.pendingActionRequestIDs().count) "
                + "requestsDir=\(AppGroupStore.actionRequestsDirectory?.path ?? "UNAVAILABLE")"
        )
        processPendingRequests()
        startMonitoringRequestDirectory()
    }

    func handle(url: URL) {
        DiagnosticsLog.log("received url \(url.absoluteString)")
        guard let requestID = FinderActionURL.requestID(from: url) else {
            DiagnosticsLog.log("ignored invalid action URL")
            NSLog("RightKit ignored invalid action URL: %@", url.absoluteString)
            return
        }
        process(requestID: requestID)
    }

    func invalidate() {
        requestDirectorySource?.cancel()
        requestDirectorySource = nil
        xpcClient.invalidate()
    }

    func processPendingRequests() {
        for requestID in AppGroupStore.pendingActionRequestIDs() {
            process(requestID: requestID)
        }
    }

    private func process(requestID: UUID) {
        guard !handledRequestIDs.contains(requestID) else {
            return
        }
        handledRequestIDs.insert(requestID)
        if handledRequestIDs.count > 50 {
            handledRequestIDs.removeFirst()
        }

        do {
            let request = try AppGroupStore.loadActionRequest(id: requestID)
            AppGroupStore.removeActionRequest(id: requestID)
            DiagnosticsLog.log(
                "loaded request \(request.id.uuidString) kind=\(request.kind.rawValue) "
                    + "template=\(request.templateID ?? "nil") dir=\(request.directoryPath)"
            )
            NSLog(
                "RightKit handling action %@ request %@",
                request.kind.rawValue,
                request.id.uuidString
            )
            // Run the interaction on a later main-actor turn. When Finder cold
            // launches the app through rightkit://, running a modal alert from
            // inside application(_:open:) can leave the app without a key window
            // and the alert never becomes visible.
            Task { @MainActor [weak self] in
                self?.handle(request)
            }
        } catch {
            DiagnosticsLog.log("failed to load request \(requestID.uuidString): \(error.localizedDescription)")
            NSLog("RightKit failed to load action request %@: %@", requestID.uuidString, error.localizedDescription)
            presentError(error)
        }
    }

    private func startMonitoringRequestDirectory() {
        guard requestDirectorySource == nil,
              let directory = AppGroupStore.actionRequestsDirectory else {
            return
        }

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.processPendingRequests()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        requestDirectorySource = source
    }

    private func handle(_ request: FinderActionRequest) {
        switch request.kind {
        case .newFile:
            createFile(for: request)
        case .runScript:
            runScript(for: request)
        case .compressZip, .compressSevenZip, .decompressHere, .decompressIntoFolder:
            performArchive(request.kind, for: request)
        case .openInTerminal:
            openInTerminal(for: request)
        }
    }

    /// Runs an archive command off the main actor: these can take seconds and
    /// must never block the settings window.
    private func performArchive(_ kind: FinderActionKind, for request: FinderActionRequest) {
        let urls = request.selectedPaths.map { URL(fileURLWithPath: $0) }
        let directory = URL(fileURLWithPath: request.directoryPath, isDirectory: true)

        DiagnosticsLog.log(
            "archive \(kind.rawValue): \(urls.count) item(s) in \(directory.path)"
        )

        Task.detached { [weak self] in
            do {
                // Nothing is revealed on success, and no notification is posted: the
                // archive lands in the very folder the menu was opened in, so Finder
                // already shows it. Being pulled forward added nothing. Failures still
                // speak, below.
                _ = try await ArchiveService.perform(
                    kind,
                    urls: urls,
                    in: directory
                )
            } catch {
                await self?.presentError(error, title: "压缩 / 解压")
            }
        }
    }

    private func createFile(for request: FinderActionRequest) {
        guard let templateID = request.templateID,
              let template = resolveTemplate(id: templateID) else {
            DiagnosticsLog.log("template unavailable: \(request.templateID ?? "nil")")
            presentError(
                ScriptCatalogError.templateUnavailable(request.templateID ?? "unknown"),
                title: "New File"
            )
            return
        }

        let directory = URL(fileURLWithPath: request.directoryPath, isDirectory: true)
        let name = NewFileService.defaultFileName(for: template)
        DiagnosticsLog.log(
            "createFile template=\(template.id) source=\(template.contentSource.rawValue) "
                + "resource=\(template.contentPath ?? "nil") dir=\(directory.path) "
                + "name=\(name) "
                + "dirExists=\(FileManager.default.fileExists(atPath: directory.path))"
        )

        // No dialog: the item is created straight away and left in Finder with
        // its name ready to edit, exactly like Finder's own "New Folder".
        do {
            let createdURL = try NewFileService.createFile(
                from: template,
                named: name,
                in: directory
            )
            DiagnosticsLog.log("created file \(createdURL.path)")
            NSLog("RightKit created file: %@", createdURL.path)
            revealForRenaming(createdURL)
        } catch {
            DiagnosticsLog.log("create failed: \(error.localizedDescription)")
            NSLog("RightKit failed to create file: %@", error.localizedDescription)
            presentError(error, title: "Could not create \(template.name) file")
        }
    }

    /// Brings Finder forward with the new item selected and starts its inline
    /// rename. This app was only woken up to do the work, so it gets out of the
    /// way instead of leaving its settings window in front.
    private func revealForRenaming(_ url: URL) {
        // No hiding here. The app is woken in the background now, so it is not in
        // the way; hiding up front would make an open settings window vanish for
        // no reason. `FinderRenameService` steps aside only if it has to.
        NSWorkspace.shared.activateFileViewerSelecting([url])
        FinderRenameService.beginRename(of: url)
    }

    /// Prefers the menu snapshot, which reflects the user's settings, and only
    /// falls back to the bundled catalog when no snapshot has been written yet.
    private func resolveTemplate(id: String) -> FileTemplate? {
        if let snapshot = ScriptCatalogService.shared.currentSnapshot() {
            return snapshot.templates.first { $0.id == id }
        }

        return BuiltinTemplates.all.first { $0.id == id }
    }


    private func runScript(for request: FinderActionRequest) {
        guard let scriptID = request.scriptID,
              let script = ScriptCatalogService.shared.script(id: scriptID) else {
            presentError(
                ScriptCatalogError.scriptUnavailable(request.scriptID ?? "unknown"),
                title: "Script"
            )
            return
        }

        if script.requiresConfirmation, !confirmScriptExecution(script) {
            return
        }

        let arguments = request.selectedPaths.isEmpty
            ? [request.directoryPath]
            : request.selectedPaths
        let job = ScriptJobRequest(
            requestID: request.id,
            scriptID: script.id,
            arguments: arguments,
            workingDirectory: request.directoryPath
        )
        let activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "Running RightKit script \(script.id)"
        )
        activityTokens[request.id] = activityToken

        Task {
            defer {
                ProcessInfo.processInfo.endActivity(activityToken)
                activityTokens.removeValue(forKey: request.id)
            }
            do {
                let result = try await xpcClient.execute(job)
                if result.succeeded {
                    NotificationService.shared.post(
                        title: script.name,
                        body: logTail(result.logPath) ?? "脚本执行完成。"
                    )
                } else {
                    NotificationService.shared.post(
                        title: "\(script.name) 执行失败",
                        body: result.errorMessage
                            ?? logTail(result.logPath)
                            ?? "退出码 \(result.exitCode ?? -1)"
                    )
                }
            } catch {
                showError(error)
            }
        }
    }

    /// Opens Terminal at the folder the action came from. Only the main app can
    /// do this: the extension is sandboxed.
    private func openInTerminal(for request: FinderActionRequest) {
        let directory = TerminalTarget.directory(
            selectedPaths: request.selectedPaths,
            directoryPath: request.directoryPath
        )

        guard let terminal = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: ToolboxCatalog.terminalBundleIdentifier
        ) else {
            DiagnosticsLog.log("openInTerminal: Terminal.app not found")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        DiagnosticsLog.log("openInTerminal: \(directory.path)")
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminal,
            configuration: configuration
        ) { _, error in
            if let error {
                DiagnosticsLog.log("openInTerminal failed: \(error.localizedDescription)")
            }
        }
    }

    private func confirmScriptExecution(_ script: ScriptPackage) -> Bool {
        let alert = NSAlert()
        alert.messageText = "要运行「\(script.name)」吗？"
        alert.informativeText = "脚本可以修改选中的文件，请确认来源可信。"
        alert.addButton(withTitle: "运行")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Last non-empty line of a script's log, so the notification says what
    /// happened instead of only that something did.
    private func logTail(_ path: String?, limit: Int = 180) -> String? {
        guard let path,
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let last = lines.last else {
            return nil
        }
        return last.count > limit ? "…" + last.suffix(limit) : last
    }

    private func showError(_ error: Error) {
        NotificationService.shared.post(
            title: "RightKit",
            body: error.localizedDescription
        )
    }

    /// Reports a failure the user just triggered. A notification is too easy to
    /// miss, which made broken menu items look like they did nothing at all.
    private func presentError(_ error: Error, title: String = "RightKit") {
        DiagnosticsLog.log("presenting error [\(title)]: \(error.localizedDescription)")
        NSLog("RightKit error: %@", error.localizedDescription)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
