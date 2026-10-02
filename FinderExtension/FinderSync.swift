import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private let snapshotLock = NSLock()
    private var snapshot: MenuSnapshot?
    private var snapshotModificationDate: Date?
    private let commandRegistry = MenuCommandRegistry()

    override init() {
        super.init()
        DiagnosticsLog.log(
            "extension init; appGroup=\(AppGroup.identifier) "
                + "container=\(AppGroup.containerURL?.path ?? "UNAVAILABLE")"
        )
        let directoryURLs = DirectoryRegistrationPolicy.urls
        FIFinderSyncController.default().directoryURLs = directoryURLs
        DiagnosticsLog.log("registered directories: \(directoryURLs.map(\.path).sorted())")
        NSLog("RightKit registered directories: %@", directoryURLs.map(\.path).sorted())
        reloadSnapshot()
        DiagnosticsLog.log("initial snapshot: \(snapshotSummary())")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(catalogDidChange),
            name: AppGroupStore.catalogDidChangeNotification,
            object: nil
        )
    }

    override var toolbarItemName: String {
        "RightKit"
    }

    override var toolbarItemToolTip: String {
        "RightKit"
    }

    override var toolbarItemImage: NSImage {
        NSImage(named: NSImage.actionTemplateName) ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let menu = MenuBuilder.makeMenu(
            for: menuKind,
            snapshot: currentSnapshot(),
            selectedURLs: selectedURLs,
            target: self,
            registry: commandRegistry
        )
        DiagnosticsLog.log(
            "menu kind=\(menuKind.rawValue) selected=\(selectedURLs.count) "
                + "targeted=\(FIFinderSyncController.default().targetedURL()?.path ?? "nil") "
                + "\(snapshotSummary()) items=\(menu?.items.count ?? 0)"
        )
        DiagnosticsLog.log("menu contents: \(describe(menu))")
        NSLog("RightKit building menu for kind: %lu", menuKind.rawValue)
        return menu
    }

    /// Flattens the built menu into `title#tag(action)` entries so a later click
    /// can be matched against exactly what was handed to Finder.
    private func describe(_ menu: NSMenu?) -> String {
        guard let menu else {
            return "nil"
        }

        return menu.items.map { item -> String in
            let action = item.action.map(NSStringFromSelector) ?? "none"
            let entry = "[\(item.title)#\(item.tag) \(action)]"
            if let submenu = item.submenu {
                return entry + "{" + describe(submenu) + "}"
            }
            return entry
        }
        .joined(separator: " ")
    }

    private func snapshotSummary() -> String {
        let current = currentSnapshot()
        return "snapshot=\(current == nil ? "nil" : "ok") "
            + "templates=\(current?.templates.count ?? 0) scripts=\(current?.scripts.count ?? 0)"
    }

    // MARK: - Toolbox actions
    //
    // These run entirely inside the extension: writing to the pasteboard and
    // asking LaunchServices for a terminal are both allowed in the sandbox, so
    // no main-app round trip (and no wake-up) is needed.

    @IBAction func copyPath(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let paths: [String]
        if selectedURLs.isEmpty, let targetURL = controller.targetedURL() {
            paths = [targetURL.path]
        } else {
            paths = selectedURLs.map(\.path)
        }

        guard !paths.isEmpty else {
            DiagnosticsLog.log("copyPath: nothing to copy")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        DiagnosticsLog.log("copyPath: copied \(paths.count) path(s)")
    }

    @IBAction func copyFileName(_ sender: AnyObject?) {
        let names = (FIFinderSyncController.default().selectedItemURLs() ?? [])
            .map(\.lastPathComponent)

        guard !names.isEmpty else {
            DiagnosticsLog.log("copyFileName: nothing selected")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
        DiagnosticsLog.log("copyFileName: copied \(names.count) name(s)")
    }

    @IBAction func openInTerminal(_ sender: AnyObject?) {
        // Handed to the main app. Doing it here looked plausible but never
        // worked: the sandbox refuses to pass a directory this extension has no
        // access to over to Terminal, which fails with a miscellaneous error.
        dispatch(FinderCommand(kind: .openInTerminal))
    }

    // MARK: - Menu actions
    //
    // One selector per kind, and the payload recovered from the item's title or
    // tag. `NSMenuItem.representedObject` cannot be used here: it does not
    // survive the trip from this extension to Finder and always arrives `nil`.

    @IBAction func newFile(_ sender: AnyObject?) {
        guard let item = menuItem(from: sender) else {
            return
        }
        guard let templateID = commandRegistry.templateID(title: item.title, tag: item.tag) else {
            DiagnosticsLog.log("newFile: no template registered for \(describe(item))")
            return
        }

        dispatch(FinderCommand(kind: .newFile, identifier: templateID))
    }

    @IBAction func runScript(_ sender: AnyObject?) {
        guard let item = menuItem(from: sender) else {
            return
        }
        guard let scriptID = commandRegistry.scriptID(title: item.title, tag: item.tag) else {
            DiagnosticsLog.log("runScript: no script registered for \(describe(item))")
            return
        }

        dispatch(FinderCommand(kind: .runScript, identifier: scriptID))
    }

    @IBAction func compress(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .compress))
    }

    @IBAction func decompress(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .decompress))
    }

    // Archive commands need the main app: only it may run the archive tool.
    // These name their operation up front instead of letting the tool ask.

    @IBAction func compressZip(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .compressZip))
    }

    @IBAction func compressSevenZip(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .compressSevenZip))
    }

    @IBAction func decompressHere(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .decompressHere))
    }

    @IBAction func decompressIntoFolder(_ sender: AnyObject?) {
        dispatch(FinderCommand(kind: .decompressIntoFolder))
    }

    private func menuItem(from sender: AnyObject?) -> NSMenuItem? {
        guard let item = sender as? NSMenuItem else {
            DiagnosticsLog.log("menu action: sender is not a menu item")
            return nil
        }
        return item
    }

    /// Logged on resolution failures so a future change in what Finder preserves
    /// is immediately visible in the diagnostics log.
    private func describe(_ item: NSMenuItem) -> String {
        "title=[\(item.title)] tag=\(item.tag) "
            + "represented=\(String(describing: item.representedObject))"
    }

    @objc private func catalogDidChange() {
        reloadSnapshot()
    }

    private func dispatch(_ command: FinderCommand) {
        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetURL = controller.targetedURL()
        guard let directoryURL = targetURL ?? selectedURLs.first?.deletingLastPathComponent() else {
            DiagnosticsLog.log("dispatch \(command.kind.rawValue): NO directory; aborting")
            return
        }

        let request = FinderActionRequest(
            id: UUID(),
            kind: command.kind,
            directoryPath: directoryURL.path,
            selectedPaths: selectedURLs.map(\.path),
            templateID: command.templateID,
            scriptID: command.scriptID
        )

        DiagnosticsLog.log(
            "dispatch \(command.kind.rawValue) template=\(command.templateID ?? "nil") "
                + "dir=\(directoryURL.path) selected=\(selectedURLs.count)"
        )

        do {
            try AppGroupStore.saveActionRequest(request)
            DiagnosticsLog.log("saved request \(request.id.uuidString)")
            NSLog(
                "RightKit saved action %@ request %@",
                command.kind.rawValue,
                request.id.uuidString
            )
            guard let url = FinderActionURL.make(for: request.id) else {
                DiagnosticsLog.log("could not build action URL")
                return
            }
            if NSWorkspace.shared.open(url) {
                DiagnosticsLog.log("opened \(url.absoluteString)")
                NSLog("RightKit opened action URL %@", url.absoluteString)
                return
            }

            // LaunchServices may not have the rightkit:// scheme registered yet,
            // for instance right after the app was moved. The request is already
            // in the App Group and the app drains that queue on launch.
            DiagnosticsLog.log("open failed for \(url.absoluteString); launching app directly")
            NSLog("RightKit could not open %@; launching the app directly", url.absoluteString)
            NSWorkspace.shared.openApplication(
                at: containingAppURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    DiagnosticsLog.log("launch failed: \(error.localizedDescription)")
                    NSLog(
                        "RightKit could not launch the app: %@",
                        error.localizedDescription
                    )
                }
            }
        } catch {
            DiagnosticsLog.log("save failed: \(error.localizedDescription)")
            NSLog("RightKit could not create action request: %@", error.localizedDescription)
        }
    }

    /// The app that embeds this extension:
    /// `RightKit.app/Contents/PlugIns/FinderExtension.appex`.
    private var containingAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func reloadSnapshot() {
        let loadedSnapshot = AppGroupStore.loadMenuSnapshot()
        let modificationDate = AppGroupStore.menuSnapshotModificationDate()
        snapshotLock.lock()
        snapshot = loadedSnapshot
        snapshotModificationDate = modificationDate
        snapshotLock.unlock()
    }

    private func currentSnapshot() -> MenuSnapshot? {
        snapshotLock.lock()
        let cachedSnapshot = snapshot
        let cachedModificationDate = snapshotModificationDate
        snapshotLock.unlock()

        if AppGroupStore.menuSnapshotModificationDate() != cachedModificationDate {
            reloadSnapshot()
            snapshotLock.lock()
            defer { snapshotLock.unlock() }
            return snapshot
        }

        return cachedSnapshot
    }
}

enum DirectoryRegistrationPolicy {
    static var urls: Set<URL> {
        let fileManager = FileManager.default
        var urls: Set<URL> = [
            fileManager.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/Users", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes", isDirectory: true)
        ]

        let iCloudURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs",
                isDirectory: true
            )
        urls.insert(iCloudURL)

        return urls
    }
}
