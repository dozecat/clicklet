import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLog.log(
            "app launched; version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") "
                + "appGroup=\(AppGroup.identifier) container=\(AppGroup.containerURL?.path ?? "UNAVAILABLE")"
        )
        let seeded = BuiltinScriptSeeder.seedIfNeeded()
        if !seeded.isEmpty {
            DiagnosticsLog.log("built-in scripts offered: \(seeded)")
        }

        do {
            let snapshot = try ScriptCatalogService.shared.refresh()
            DiagnosticsLog.log(
                "catalog refreshed: templates=\(snapshot.templates.map(\.id)) scripts=\(snapshot.scripts.count)"
            )
        } catch {
            DiagnosticsLog.log("catalog refresh failed: \(error.localizedDescription)")
            NSLog("RightKit catalog refresh failed: %@", error.localizedDescription)
        }
        ActionCoordinator.shared.start()
        NotificationService.shared.requestAuthorization()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DiagnosticsLog.log("app received urls: \(urls.map(\.absoluteString))")
        NSLog("RightKit received URLs: %@", urls.map(\.absoluteString))
        urls.forEach {
            ActionCoordinator.shared.handle(url: $0)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // There is no window at launch any more, so clicking the Dock icon has to
        // be what brings the settings window up.
        if !flag {
            SettingsOpener.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActionCoordinator.shared.invalidate()
    }
}
